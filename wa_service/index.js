/**
 * Smart Laundry v2 - WhatsApp Notification Service
 * 
 * A standalone Node.js microservice that provides REST API endpoints
 * for sending WhatsApp messages using whatsapp-web.js library.
 * 
 * The Python server communicates with this service to send
 * automated WhatsApp notifications to customers.
 * 
 * Endpoints:
 *   GET  /status  - Check WA connection status
 *   POST /send    - Send a WhatsApp message
 *   GET  /qr      - Get QR code image for login (base64)
 */

const express = require('express');
const { Client, LocalAuth, Poll } = require('whatsapp-web.js');
const qrcode = require('qrcode-terminal');
const QRCode = require('qrcode');
const path = require('path');
const fs = require('fs');
const http = require('http');

// State for testing poll vote
let latestVote = {
    sender: null,
    selected: null,
    timestamp: null
};

// File-based flag to track authentication state for background auto-reconnect
const FLAG_PATH = path.join(__dirname, '.wwebjs_auth', 'authenticated.flag');

function hasSavedSession() {
    return fs.existsSync(FLAG_PATH);
}

function markAuthenticated(auth) {
    try {
        if (auth) {
            // Ensure parent directory exists
            const dir = path.dirname(FLAG_PATH);
            if (!fs.existsSync(dir)) {
                fs.mkdirSync(dir, { recursive: true });
            }
            fs.writeFileSync(FLAG_PATH, 'true');
        } else if (fs.existsSync(FLAG_PATH)) {
            fs.unlinkSync(FLAG_PATH);
        }
    } catch (e) {
        console.error('[WA] Error updating auth flag:', e.message);
    }
}

// Maps to track chatbot cooldown states
const welcomePollCooldown = new Map();
const staffChatCooldown = new Map();
const userMenuState = new Map();

// Set to track message IDs sent automatically by the bot/system
const botSentMessageIds = new Set();

// Set to track poll message IDs that have already been responded to (to allow only 1 vote per poll bubble)
const processedPollIds = new Set();

// Helper to send a message and register its ID to botSentMessageIds
async function sendBotMessage(chatId, content) {
    try {
        const msg = await client.sendMessage(chatId, content);
        if (msg && msg.id && msg.id.id) {
            botSentMessageIds.add(msg.id.id);
            // Limit Set size to prevent memory growth
            if (botSentMessageIds.size > 1000) {
                const firstKey = botSentMessageIds.values().next().value;
                botSentMessageIds.delete(firstKey);
            }
        }
        return msg;
    } catch (e) {
        console.error('[Chatbot] Error in sendBotMessage:', e.message);
        throw e;
    }
}

// Helper to load config.json dynamically
function loadConfig() {
    try {
        const configPath = path.join(__dirname, '..', 'config.json');
        if (fs.existsSync(configPath)) {
            const raw = fs.readFileSync(configPath, 'utf8');
            return JSON.parse(raw);
        }
    } catch (e) {
        console.error('[WA] Error reading config.json:', e.message);
    }
    return {};
}

// Helper to fetch customer status from Python backend
function fetchStatusCucian(phone, serviceType, callback) {
    const config = loadConfig();
    const port = config.api_port || 5001;
    const url = `http://localhost:${port}/api/wa/chatbot/status-cucian?phone=${phone}&service_type=${serviceType}`;
    
    http.get(url, (res) => {
        let data = '';
        res.on('data', (chunk) => {
            data += chunk;
        });
        res.on('end', () => {
            try {
                const parsed = JSON.parse(data);
                callback(null, parsed.message);
            } catch (e) {
                callback(e);
            }
        });
    }).on('error', (err) => {
        callback(err);
    });
}

// --- Parent Watchdog Setup ---
const parentPidArg = process.argv.find(arg => arg.startsWith('--parent-pid='));
if (parentPidArg) {
    const parentPid = parseInt(parentPidArg.split('=')[1], 10);
    if (!isNaN(parentPid)) {
        console.log(`[Watchdog] Memulai pemantauan PID induk: ${parentPid}`);
        setInterval(() => {
            try {
                process.kill(parentPid, 0);
            } catch (e) {
                console.log("[Watchdog] Proses induk tidak ditemukan/keluar. Mengakhiri Node...");
                process.exit(0);
            }
        }, 3000);
    }
}

const app = express();
app.use(express.json());

const PORT = process.env.PORT || 3000;

// --- WhatsApp Client Setup ---
let isInitializing = false;
let isReady = false;
let isDestroying = false;
let currentQR = null;
let clientInfo = null;
let lastRequestTime = 0;

const client = new Client({
    authStrategy: new LocalAuth({
        dataPath: path.join(__dirname, '.wwebjs_auth')
    }),
    qrMaxRetries: 0,
    authTimeoutMs: 60000,
    webVersionCache: {
        type: 'remote',
        remotePath: 'https://raw.githubusercontent.com/wppconnect-team/wa-version/main/html/2.2412.54.html',
    },
    puppeteer: {
        headless: true,
        args: [
            '--no-sandbox',
            '--disable-setuid-sandbox',
            '--disable-dev-shm-usage',
            '--disable-accelerated-2d-canvas',
            '--no-first-run',
            '--no-zygote',
            '--disable-gpu'
        ]
    }
});

async function initializeClient() {
    if (isInitializing || isReady || isDestroying || currentQR !== null) {
        console.log(`[WA] Skip initialization (isInitializing=${isInitializing}, isReady=${isReady}, isDestroying=${isDestroying}, hasQR=${currentQR !== null})`);
        return;
    }
    isInitializing = true;
    currentQR = null;
    console.log('[WA] Initializing WhatsApp client...');
    try {
        await client.initialize();
    } catch (err) {
        console.error('[WA] Initialization error:', err.message);
        isInitializing = false;
    }
}

// QR Code event - store for API (do not print ASCII QR to debug logs)
client.on('qr', (qr) => {
    currentQR = qr;
    isInitializing = false;
    console.log('[WA] New QR code generated. Waiting for scan...');
    
    // Stop QR generation and close Puppeteer if settings menu hasn't been opened recently (last 15s)
    const now = Date.now();
    if (now - lastRequestTime > 15000) {
        console.log('[WA] Settings menu is not open. Stopping client to save resources...');
        isReady = false;
        isInitializing = false;
        currentQR = null;
        isDestroying = true;
        client.destroy().then(() => {
            isDestroying = false;
            console.log('[WA] Client stopped and resources released.');
        }).catch((err) => {
            isDestroying = false;
            console.error('[WA] Error while stopping client:', err.message);
        });
    }
});

// Ready event
client.on('ready', () => {
    isReady = true;
    isInitializing = false;
    currentQR = null;
    clientInfo = client.info;
    markAuthenticated(true);
    const phoneNumber = clientInfo?.wid?.user || 'unknown';
    console.log('\n========================================');
    console.log('  ✅ WHATSAPP CONNECTED!');
    console.log(`  📱 Nomor: ${phoneNumber}`);
    console.log('========================================\n');
});

// Helper to send the welcome poll dynamically
async function sendWelcomePoll(chatId, sender, config) {
    try {
        const menu = config.chatbot_menu || [];
        const options = menu.map(item => item.label);
        
        if (options.length === 0) {
            console.log('[Chatbot] Menu is empty. Welcome poll not sent.');
            return;
        }

        const welcomeTitle = config.chatbot_welcome_message || 'Halo! Selamat datang di Azima Laundry. 😊 Ada yang bisa kami bantu?';
        const welcomePoll = new Poll(
            welcomeTitle,
            options,
            { allowMultipleAnswers: false }
        );
        const sentMsg = await sendBotMessage(chatId, welcomePoll);
        
        // Reset user state to root
        userMenuState.set(sender, {
            menuPath: [],
            lastPollId: sentMsg.id.id,
            lastPollTime: Date.now()
        });
        console.log(`[Chatbot] Welcome Poll sent to ${sender}. Root state initialized.`);
    } catch (e) {
        console.error('[Chatbot] Error sending welcome poll:', e.message);
    }
}

// Helper to send text or api response as a poll if short enough, or text + separate poll if long
async function sendResponseAsPoll(chatId, sender, text, customOptions) {
    const cleanText = text || 'Informasi tidak tersedia.';
    const options = customOptions || ['🔙 Kembali ke Menu Utama', '📞 Hubungi Staff (Kasir)'];
    
    if (cleanText.length <= 255) {
        try {
            const poll = new Poll(cleanText, options, { allowMultipleAnswers: false });
            const sentMsg = await sendBotMessage(chatId, poll);
            
            // Set user state to root with the new poll ID
            userMenuState.set(sender, {
                menuPath: [],
                lastPollId: sentMsg.id.id,
                lastPollTime: Date.now()
            });
            console.log(`[Chatbot] Sent response as single poll to ${sender}.`);
            return;
        } catch (e) {
            console.error('[Chatbot] Failed to send response as poll, falling back to text:', e.message);
        }
    }
    
    // Fallback if text is > 255 characters
    try {
        await sendBotMessage(chatId, cleanText);
        
        const backPoll = new Poll(
            'Pilih opsi di bawah untuk navigasi:',
            options,
            { allowMultipleAnswers: false }
        );
        const sentMsg = await sendBotMessage(chatId, backPoll);
        userMenuState.set(sender, {
            menuPath: [],
            lastPollId: sentMsg.id.id,
            lastPollTime: Date.now()
        });
        console.log(`[Chatbot] Sent response as text + back poll to ${sender}.`);
    } catch (e) {
        console.error('[Chatbot] Error sending fallback response:', e.message);
    }
}

// Poll Vote Update event
client.on('vote_update', async (vote) => {
    // 1. Maintain test vote state
    let sender = vote.voter.replace('@c.us', '').replace('@lid', '');
    try {
        const contact = await client.getContactById(vote.voter);
        if (contact && contact.id && contact.id.user) {
            sender = contact.id.user;
        }
    } catch (e) {
        console.error('[Chatbot] Error resolving vote voter:', e.message);
    }
    const selected = vote.selectedOptions.map(opt => `${opt.name} (localId: ${opt.localId})`).join(', ');
    latestVote = {
        sender: sender,
        selected: selected || 'None (Deselected)',
        timestamp: new Date().toISOString()
    };
    console.log(`\n========================================`);
    console.log(`🗳️  POLL VOTE DETECTED!`);
    console.log(`📱 Pengirim: ${sender}`);
    console.log(`✅ Pilihan: ${latestVote.selected}`);
    console.log(`========================================\n`);

    // 2. Chatbot response logic
    const config = loadConfig();
    if (config.chatbot_enabled === false) return;
    if (!vote.selectedOptions || vote.selectedOptions.length === 0) return;
    
    const pollId = vote.parentMsgKey ? vote.parentMsgKey.id : null;
    if (processedPollIds.has(pollId)) {
        console.log(`[Chatbot] Ignoring vote on poll ${pollId} from ${sender} because this poll has already been answered.`);
        return;
    }
    processedPollIds.add(pollId);
    if (processedPollIds.size > 2000) {
        const firstKey = processedPollIds.values().next().value;
        processedPollIds.delete(firstKey);
    }
    
    // Optionally delete the voted poll message for everyone
    if (config.chatbot_delete_polls === true && vote.parentMsgKey) {
        try {
            const msgId = vote.parentMsgKey._serialized || `${vote.parentMsgKey.fromMe}_${vote.parentMsgKey.remote}_${vote.parentMsgKey.id}`;
            client.getMessageById(msgId).then(async (msg) => {
                if (msg) {
                    await msg.delete(true);
                    console.log(`[Chatbot] Voted poll ${msgId} deleted for everyone.`);
                }
            }).catch(e => {
                console.error('[Chatbot] Failed to retrieve/delete poll message:', e.message);
            });
        } catch (e) {
            console.error('[Chatbot] Error scheduling poll deletion:', e.message);
        }
    }
    
    const chatId = vote.voter;
    const choice = vote.selectedOptions[0].name;
    const choiceIndex = vote.selectedOptions[0].localId;
    
    // Check if staff is chatting with this user (cooldown from config, default 30 min)
    const lastStaffChat = staffChatCooldown.get(sender) || 0;
    const staffCooldownMs = (config.chatbot_staff_cooldown !== undefined ? config.chatbot_staff_cooldown : 30) * 60 * 1000;
    if (Date.now() - lastStaffChat < staffCooldownMs) {
        console.log(`[Chatbot] Skipping auto-reply for ${sender} because staff is active.`);
        return;
    }

    // Get or initialize user state
    let state = userMenuState.get(sender);
    if (!state) {
        state = { menuPath: [], lastPollId: pollId, lastPollTime: Date.now() };
        userMenuState.set(sender, state);
    }

    // Resolve menu structure
    const menu = config.chatbot_menu || [];
    let selectedItem = null;

    // If the user selects any back option, always return to main menu
    if (choice.includes('Kembali') || choice.includes('kembali')) {
        selectedItem = { type: 'back' };
    } else if (choice.includes('tidak menemukan') || choice.includes('cucian saya')) {
        selectedItem = { type: 'api', action: 'status_by_nota' };
    } else if (choice.includes('Hubungi Staff') || choice.includes('Kasir') || choice.includes('staff')) {
        // Find staff item in menu or fallback to a default staff item
        selectedItem = menu.find(item => item.type === 'staff') || {
            type: 'staff',
            response: 'Baik Kak, pesan Anda telah kami teruskan ke staf kasir kami. Staf kami akan segera membalas chat Anda secara manual. Terima kasih! 😊'
        };
    } else if (state.menuPath.length === 0) {
        // We are at root level
        selectedItem = menu[choiceIndex];
    } else {
        // We are at sub-menu level
        const parentIdx = state.menuPath[0];
        const parentItem = menu[parentIdx];
        if (parentItem && parentItem.children) {
            // Check if it's the auto-back option (last option in options list)
            if (choiceIndex === parentItem.children.length || choice.includes('Kembali')) {
                selectedItem = { type: 'back' };
            } else {
                selectedItem = parentItem.children[choiceIndex];
            }
        }
    }

    if (!selectedItem) {
        console.log(`[Chatbot] Menu item not found for index ${choiceIndex} at path [${state.menuPath.join(', ')}]`);
        return;
    }

    console.log(`[Chatbot] Resolved action type: ${selectedItem.type} for customer ${sender}`);



    // Process based on menu item type
    if (selectedItem.type === 'text') {
        const responseText = selectedItem.response || 'Informasi tidak tersedia.';
        await sendResponseAsPoll(chatId, sender, responseText);
    } 
    else if (selectedItem.type === 'api') {
        if (selectedItem.action === 'status_cucian') {
            fetchStatusCucian(sender, 'laundry', async (err, replyText) => {
                let responseText = replyText;
                if (err) {
                    console.error('[Chatbot] Error checking laundry status:', err.message);
                    responseText = 'Maaf, terjadi kesalahan saat mengecek status cucian Anda.';
                } else if (!replyText) {
                    responseText = 'Maaf, status cucian tidak dapat ditemukan saat ini.';
                }
                const customOpts = ['🔍 Saya tidak menemukan cucian saya', '🔙 Kembali ke Menu Utama', '📞 Hubungi Staff (Kasir)'];
                await sendResponseAsPoll(chatId, sender, responseText, customOpts);
            });
        } else if (selectedItem.action === 'status_setrika') {
            fetchStatusCucian(sender, 'gosok', async (err, replyText) => {
                let responseText = replyText;
                if (err) {
                    console.error('[Chatbot] Error checking setrika status:', err.message);
                    responseText = 'Maaf, terjadi kesalahan saat mengecek status setrika Anda.';
                } else if (!replyText) {
                    responseText = 'Maaf, status setrika tidak dapat ditemukan saat ini.';
                }
                const customOpts = ['🔍 Saya tidak menemukan cucian saya', '🔙 Kembali ke Menu Utama', '📞 Hubungi Staff (Kasir)'];
                await sendResponseAsPoll(chatId, sender, responseText, customOpts);
            });
        } else if (selectedItem.action === 'status_by_nota') {
            userMenuState.set(sender, {
                menuPath: state.menuPath,
                lastPollId: pollId,
                lastPollTime: Date.now(),
                waitingForOrderId: true
            });
            await sendBotMessage(chatId, 'Silakan ketik nomor nota Kakak secara langsung (contoh: *123*) untuk melacak status pesanan tersebut.\n\n*(Catatan: Nomor nota dapat dilihat di bagian paling atas kertas nota fisik Kakak, di sebelah tulisan *Order: #* atau *Nota #*)*');
        } else {
            await sendResponseAsPoll(chatId, sender, 'Fitur otomatis ini belum tersedia.');
        }
    } 
    else if (selectedItem.type === 'staff') {
        const responseText = selectedItem.response || 'Hubungi kasir kami.';
        await sendBotMessage(chatId, responseText);
        
        // Pause chatbot for staff cooldown period
        staffChatCooldown.set(sender, Date.now());
        console.log(`[Chatbot] Customer ${sender} requested staff. Chatbot paused.`);

        // Force the chat to be marked as UNREAD so the green dot reappears on the admin's phone!
        try {
            const chat = await client.getChatById(chatId);
            await chat.markUnread();
            console.log(`[Chatbot] Marked chat ${sender} as unread for the admin.`);
        } catch (e) {
            console.error('[Chatbot] Error marking unread:', e.message);
        }
    } 
    else if (selectedItem.type === 'poll') {
        // Send Sub-Poll menu
        try {
            const options = (selectedItem.children || []).map(child => child.label);
            // Always auto-append "Kembali" option to sub-polls
            options.push('🔙 Kembali ke Menu Utama');

            const subPollTitle = selectedItem.poll_title || selectedItem.label || 'Pilih opsi:';
            const subPoll = new Poll(
                subPollTitle,
                options,
                { allowMultipleAnswers: false }
            );
            const sentMsg = await sendBotMessage(chatId, subPoll);
            
            // Update state to point to this sub-menu
            userMenuState.set(sender, {
                menuPath: [choiceIndex],
                lastPollId: sentMsg.id.id,
                lastPollTime: Date.now()
            });
            console.log(`[Chatbot] Sent sub-poll to ${sender}. Path updated to [${choiceIndex}]`);
        } catch (e) {
            console.error('[Chatbot] Error sending sub-poll:', e.message);
        }
    } 
    else if (selectedItem.type === 'back') {
        // Go back to main menu
        await sendWelcomePoll(chatId, sender, config);
    }
});

// Incoming message listener (Trigger Welcome Poll or status commands)
client.on('message', async (msg) => {
    // Ignore groups or self messages
    if (msg.from.endsWith('@g.us')) return;
    if (msg.fromMe) return;

    const config = loadConfig();
    if (config.chatbot_enabled === false) return;

    let sender = msg.from.replace('@c.us', '').replace('@lid', '');
    try {
        const contact = await msg.getContact();
        if (contact && contact.id && contact.id.user) {
            sender = contact.id.user;
        }
    } catch (e) {
        console.error('[Chatbot] Error getting contact number:', e.message);
    }
    
    // Custom check: status [order_id]
    const msgText = msg.body ? msg.body.trim() : '';
    const msgTextLower = msgText.toLowerCase();
    
    // Check if we are waiting for an order ID from this user
    let state = userMenuState.get(sender);
    if (state && state.waitingForOrderId) {
        if (msgTextLower.includes('batal') || msgTextLower.includes('kembali')) {
            state.waitingForOrderId = false;
            userMenuState.set(sender, state);
            await sendWelcomePoll(msg.from, sender, config);
            return;
        }
        
        const numMatch = msgText.match(/\d+/);
        if (numMatch) {
            const orderId = parseInt(numMatch[0], 10);
            const port = config.api_port || 5001;
            const url = `http://localhost:${port}/api/wa/chatbot/status-cucian?order_id=${orderId}`;
            
            // Reset waiting state
            state.waitingForOrderId = false;
            userMenuState.set(sender, state);
            
            http.get(url, (res) => {
                let data = '';
                res.on('data', (chunk) => {
                    data += chunk;
                });
                res.on('end', async () => {
                    try {
                        const parsed = JSON.parse(data);
                        await sendResponseAsPoll(msg.from, sender, parsed.message);
                    } catch (e) {
                        await sendResponseAsPoll(msg.from, sender, 'Maaf Kak, terjadi kesalahan saat memproses data status Anda.');
                    }
                });
            }).on('error', async (err) => {
                console.error('[Chatbot] Error checking status by ID:', err.message);
                await sendResponseAsPoll(msg.from, sender, 'Maaf Kak, gagal menghubungi server status laundry.');
            });
            return;
        } else {
            await sendBotMessage(msg.from, 'Nomor nota tidak valid. Silakan ketik angka saja (contoh: *123*).\n\n*(Catatan: Nomor nota dapat dilihat di bagian paling atas kertas nota fisik Kakak, di sebelah tulisan *Order: #* atau *Nota #*)*\n\nKetik *batal* jika ingin kembali ke menu utama.');
            return;
        }
    }

    const statusMatch = msgTextLower.match(/^status\s*(\d+)$/);
    if (statusMatch) {
        const orderId = parseInt(statusMatch[1], 10);
        const port = config.api_port || 5001;
        const url = `http://localhost:${port}/api/wa/chatbot/status-cucian?order_id=${orderId}`;
        
        http.get(url, (res) => {
            let data = '';
            res.on('data', (chunk) => {
                data += chunk;
            });
            res.on('end', async () => {
                try {
                    const parsed = JSON.parse(data);
                    await sendResponseAsPoll(msg.from, sender, parsed.message);
                } catch (e) {
                    await sendResponseAsPoll(msg.from, sender, 'Maaf Kak, terjadi kesalahan saat memproses data status Anda.');
                }
            });
        }).on('error', async (err) => {
            console.error('[Chatbot] Error checking status by ID:', err.message);
            await sendResponseAsPoll(msg.from, sender, 'Maaf Kak, gagal menghubungi server status laundry.');
        });
        return; // Skip welcome poll trigger
    }

    // Check if staff is chatting (cooldown from config, default 30 min)
    const lastStaffChat = staffChatCooldown.get(sender) || 0;
    const staffCooldownMs = (config.chatbot_staff_cooldown !== undefined ? config.chatbot_staff_cooldown : 30) * 60 * 1000;
    if (Date.now() - lastStaffChat < staffCooldownMs) {
        return;
    }

    // Check if welcome poll already sent recently (cooldown from config, default 15 min)
    const lastWelcomePoll = welcomePollCooldown.get(sender) || 0;
    const welcomeCooldownMs = (config.chatbot_welcome_cooldown !== undefined ? config.chatbot_welcome_cooldown : 0) * 60 * 1000;
    if (Date.now() - lastWelcomePoll < welcomeCooldownMs) {
        return;
    }

    // Mark welcome poll as sent
    welcomePollCooldown.set(sender, Date.now());

    await sendWelcomePoll(msg.from, sender, config);
});

// Detect staff manual chat to pause chatbot (message_create)
client.on('message_create', (msg) => {
    if (msg.fromMe && msg.to && !msg.to.endsWith('@g.us')) {
        const to = msg.to.replace('@c.us', '').replace('@lid', '');
        const msgId = msg.id.id;
        
        // Delay processing to allow the client.sendMessage promise to resolve and register the ID
        setTimeout(() => {
            if (botSentMessageIds.has(msgId)) {
                botSentMessageIds.delete(msgId); // Clean up
                return;
            }
            
            staffChatCooldown.set(to, Date.now());
            console.log(`[Chatbot] Staff manual message detected. Chatbot auto-reply paused for ${to} for 30 minutes.`);
        }, 500);
    }
});

// Authentication success
client.on('authenticated', () => {
    console.log('[WA] Authenticated successfully (session saved)');
    markAuthenticated(true);
});

// Authentication failure
client.on('auth_failure', (msg) => {
    console.error('[WA] Authentication failed:', msg);
    isReady = false;
    isInitializing = false;
    markAuthenticated(false);
});

// Disconnected
client.on('disconnected', (reason) => {
    console.log('[WA] Disconnected:', reason);
    isReady = false;
    isInitializing = false;
    clientInfo = null;
    currentQR = null;
    markAuthenticated(false);
    
    // Auto-reconnect after 5 seconds if settings menu is open or was previously ready
    setTimeout(() => {
        const now = Date.now();
        if (now - lastRequestTime < 30000 || hasSavedSession()) {
            console.log('[WA] Attempting to reconnect...');
            initializeClient();
        }
    }, 5000);
});

// --- API Endpoints ---

/**
 * GET /status
 * Returns the current WhatsApp connection status
 */
app.get('/status', (req, res) => {
    lastRequestTime = Date.now();
    if (!isReady && !isInitializing && currentQR === null && !isDestroying) {
        initializeClient();
    }
    const phoneNumber = clientInfo?.wid?.user || null;
    res.json({
        connected: isReady,
        phone: phoneNumber ? `+${phoneNumber}` : null,
        platform: clientInfo?.platform || null,
        pushname: clientInfo?.pushname || null
    });
});

/**
 * POST /send
 * Send a WhatsApp message
 * Body: { phone: "628xxx", message: "Hello!" }
 */
app.post('/send', async (req, res) => {
    const { phone, message } = req.body;

    if (!phone || !message) {
        return res.status(400).json({
            success: false,
            error: 'Missing phone or message'
        });
    }

    if (!isReady) {
        return res.status(503).json({
            success: false,
            error: 'WhatsApp not connected. Please scan QR code first.'
        });
    }

    try {
        // Normalize phone: remove + and ensure format is 628xxx
        let cleanPhone = phone.toString().replace(/\+/g, '').replace(/-/g, '').replace(/ /g, '');
        if (cleanPhone.startsWith('0')) {
            cleanPhone = '62' + cleanPhone.substring(1);
        }

        // WhatsApp Web JS requires format: 628xxx@c.us
        const chatId = `${cleanPhone}@c.us`;
        
        // Check if number is registered on WhatsApp
        const isRegistered = await client.isRegisteredUser(chatId);
        if (!isRegistered) {
            return res.json({
                success: false,
                error: `Nomor ${phone} tidak terdaftar di WhatsApp`
            });
        }

        // Send the message
        const result = await sendBotMessage(chatId, message);
        
        console.log(`[WA] Message sent to ${cleanPhone}: "${message.substring(0, 50)}..."`);
        
        res.json({
            success: true,
            messageId: result.id?._serialized || null,
            timestamp: new Date().toISOString()
        });
    } catch (error) {
        console.error(`[WA] Error sending to ${phone}:`, error.message);
        res.json({
            success: false,
            error: error.message
        });
    }
});

/**
 * GET /qr
 * Returns the current QR code as a base64 image (for display in Flutter app)
 */
app.get('/qr', async (req, res) => {
    lastRequestTime = Date.now();
    if (!isReady && !isInitializing && currentQR === null && !isDestroying) {
        initializeClient();
    }
    
    if (isReady) {
        return res.json({
            connected: true,
            message: 'WhatsApp sudah terhubung, tidak perlu scan QR'
        });
    }

    if (!currentQR) {
        return res.json({
            connected: false,
            qr: null,
            message: 'QR code belum tersedia, tunggu beberapa detik...'
        });
    }

    try {
        // Generate QR as base64 data URL
        const qrDataUrl = await QRCode.toDataURL(currentQR, {
            width: 300,
            margin: 2,
            color: {
                dark: '#000000',
                light: '#ffffff'
            }
        });
        
        res.json({
            connected: false,
            qr: qrDataUrl,
            message: 'Scan QR code ini menggunakan WhatsApp di HP Anda'
        });
    } catch (error) {
        res.status(500).json({
            error: 'Failed to generate QR image',
            message: error.message
        });
    }
});

/**
 * GET /health
 * Simple health check endpoint
 */
app.get('/health', (req, res) => {
    res.json({ status: 'ok', uptime: process.uptime() });
});

/**
 * GET /test-poll
 * Sends a single-choice test poll to custom phone number (or fallback)
 */
app.get('/test-poll', async (req, res) => {
    if (!isReady) {
        return res.status(503).json({ success: false, error: 'WhatsApp not connected. Please scan QR code first.' });
    }
    try {
        let phone = req.query.phone || '6289522584477';
        // Bersihkan karakter non-digit
        phone = phone.replace(/[^0-9]/g, '');
        
        if (!phone) {
            return res.status(400).json({ success: false, error: 'Nomor HP tujuan tidak valid!' });
        }
        
        if (!phone.endsWith('@c.us')) {
            phone = phone + '@c.us';
        }
        
        const poll = new Poll(
            'Selamat datang kakak di toko kami, ada yang bisa kami bantu?',
            ['Jam buka', 'Status cucian', 'harga cucian'],
            { allowMultipleAnswers: false } // Only select one answer
        );
        await sendBotMessage(phone, poll);
        res.json({ success: true, message: `Poll successfully sent to ${phone.split('@')[0]}` });
    } catch (error) {
        console.error('[WA] Error sending test poll:', error.message);
        res.status(500).json({ success: false, error: error.message });
    }
});

/**
 * GET /test-poll-result
 * Returns the latest poll vote from memory
 */
app.get('/test-poll-result', (req, res) => {
    res.json(latestVote);
});

app.get('/debug-contact', async (req, res) => {
    const jid = req.query.jid || '207439001555052@lid';
    try {
        const contact = await client.getContactById(jid);
        res.json({
            jid: jid,
            contact: contact,
            keys: Object.keys(contact),
            formattedNumber: await client.getFormattedNumber(jid).catch(e => e.message),
            numberId: await client.getNumberId(jid).catch(e => e.message)
        });
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
});

// Periodic background check to keep saved session connected
setInterval(() => {
    if (hasSavedSession() && !isReady && !isInitializing && currentQR === null && !isDestroying) {
        console.log('[WA] Saved session detected but client not running. Initializing in background...');
        initializeClient();
    }
}, 15000);

// --- Start Server ---
app.listen(PORT, '127.0.0.1', () => {
    console.log(`\n[WA Service] Berjalan di http://localhost:${PORT}`);
    console.log('[WA Service] Menginisialisasi WhatsApp client...\n');
    
    // Initialize on startup to check if we can auto-login (if unauthenticated, it will automatically shut down via QR callback)
    initializeClient();
});

// Graceful shutdown
process.on('SIGINT', async () => {
    console.log('\n[WA Service] Shutting down...');
    if (isReady) {
        await client.destroy();
    }
    process.exit(0);
});

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

// Set to track active bot send operations to prevent race conditions in message_create
const activeSends = new Set();

// Map to track active polls that we need to check manually via getPollVotes (Key: pollId, Value: { chatId, sender, config, createdAt })
const activePollsToMonitor = new Map();

// Resolves both clean phone number and clean LID for a user/contact
async function resolveIdentities(target) {
    let cleanPhone = null;
    let cleanLid = null;
    try {
        let contact = null;
        if (target && target.getContact) {
            contact = await target.getContact();
        } else if (target && typeof target === 'object' && target.voter) {
            contact = await client.getContactById(target.voter);
        } else if (typeof target === 'string') {
            contact = await client.getContactById(target);
        }
        
        if (contact) {
            const user = contact.id?.user || '';
            const isLid = contact.id?.server === 'lid' || user.length > 14;
            if (isLid) {
                cleanLid = user;
            } else {
                cleanPhone = user;
            }
            if (contact.number) {
                if (contact.number.length <= 14) {
                    cleanPhone = contact.number;
                } else {
                    cleanLid = contact.number;
                }
            }
        }
    } catch (e) {
        // Heuristics handle fail cases
    }
    
    // Heuristic fallbacks
    if (typeof target === 'string') {
        const raw = target.replace('@c.us', '').replace('@lid', '');
        if (raw.length > 14) {
            cleanLid = cleanLid || raw;
        } else {
            cleanPhone = cleanPhone || raw;
        }
    } else if (target && target.from) {
        const raw = target.from.replace('@c.us', '').replace('@lid', '');
        if (raw.length > 14) {
            cleanLid = cleanLid || raw;
        } else {
            cleanPhone = cleanPhone || raw;
        }
    }
    
    return {
        phone: cleanPhone,
        lid: cleanLid
    };
}

// Helper to get state by phone or lid JID identities
function getUserState(identities) {
    if (!identities) return null;
    let state = null;
    if (identities.phone) state = userMenuState.get(identities.phone);
    if (!state && identities.lid) state = userMenuState.get(identities.lid);
    return state;
}

// Helper to save state under both phone and lid JID identities
function saveUserState(identities, state) {
    if (!identities) return;
    if (identities.phone) userMenuState.set(identities.phone, state);
    if (identities.lid) userMenuState.set(identities.lid, state);
}

// Helper to send a message and register its ID to botSentMessageIds
async function sendBotMessage(chatId, content) {
    const cleanChatId = chatId.replace('@c.us', '').replace('@lid', '');
    activeSends.add(chatId);
    activeSends.add(cleanChatId);
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
    } finally {
        setTimeout(() => {
            activeSends.delete(chatId);
            activeSends.delete(cleanChatId);
        }, 2000);
    }
}

// Helper to open chat window in Puppeteer to ensure WhatsApp Web subscribes to poll vote events
// NOTE: For @lid contacts this triggers a non-fatal IDB error (bulkGet on Table: message),
// but opening the chat IS necessary for WA Web to process and store incoming poll vote notifications.
function openChatWindowSafely(chatId) {
    if (!client || !client.interface) return;
    client.interface.openChatWindow(chatId).then(() => {
        console.log(`[Chatbot] Focus window set to chat: ${chatId}`);
    }).catch(e => {
        // Suppress common non-fatal errors for @lid contacts
        if (!e.message.includes('No LID') && !e.message.includes('lid_not_found')) {
            console.error('[Chatbot] Error focusing chat window:', e.message);
        }
    });
}

// XOR decrypt function matching python's xor_decrypt
function xorDecrypt(encodedStr, key = "AzimaSecretKey2026") {
    try {
        const xorBytes = Buffer.from(encodedStr, 'base64');
        const keyBytes = Buffer.from(key, 'utf-8');
        const keyLen = keyBytes.length;
        const decryptedBytes = Buffer.alloc(xorBytes.length);
        for (let i = 0; i < xorBytes.length; i++) {
            decryptedBytes[i] = xorBytes[i] ^ keyBytes[i % keyLen];
        }
        return decryptedBytes.toString('utf-8');
    } catch (e) {
        return encodedStr;
    }
}

// Helper to load config.json dynamically
function loadConfig() {
    try {
        const configPath = path.join(__dirname, '..', 'config.json');
        if (fs.existsSync(configPath)) {
            const raw = fs.readFileSync(configPath, 'utf8').trim();
            if (!raw) {
                return {};
            }
            if (raw.startsWith('{')) {
                return JSON.parse(raw);
            }
            const decrypted = xorDecrypt(raw);
            return JSON.parse(decrypted);
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
        headless: false,
        defaultViewport: null,
        args: [
            '--no-sandbox',
            '--disable-setuid-sandbox',
            '--disable-dev-shm-usage',
            '--no-first-run',
            '--window-size=1200,800',
            '--app=https://web.whatsapp.com'
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
        if (client.pupPage) {
            client.pupPage.on('console', msg => {
                const text = msg.text();
                // Filter out verbose logs, keep only warnings and errors or relevant vote logs
                if (text.includes('error') || text.includes('failed') || text.includes('Poll') || text.includes('WWebJS')) {
                    console.log('[Puppeteer Console]', text);
                }
            });
        }
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
client.on('ready', async () => {
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

    // --- IDB KEY PATCH ---
    // For @lid contacts, WA Web tries IDBObjectStore.get(undefined) when looking up
    // poll messages, which throws a DataError and prevents vote storage entirely.
    // This patch converts undefined/null keys to a never-match sentinel so WA Web
    // receives "not found" (undefined result) instead of an exception, allowing
    // the vote processing pipeline to continue and store votes in IDB.
    try {
        await client.pupPage.evaluate(() => {
            if (window._idbUndefinedKeyPatchApplied) return;
            window._idbUndefinedKeyPatchApplied = true;

            const origGet = IDBObjectStore.prototype.get;
            IDBObjectStore.prototype.get = function patchedGet(key) {
                if (key === undefined || key === null || key === '') {
                    // Use a sentinel key guaranteed to not exist — avoids the DataError
                    return origGet.call(this, '\u0000__NEVER_MATCH_SENTINEL__\u0000');
                }
                return origGet.call(this, key);
            };

            // Also patch bulkGet at the transaction level used by Dexie
            const origGetAll = IDBObjectStore.prototype.getAll;
            console.log('[IDBPatch] IDBObjectStore.get patched — undefined key → sentinel (never-match)');
        });
        console.log('[IDBPatch] Browser IDB patch applied successfully');
    } catch (patchErr) {
        console.error('[IDBPatch] Failed to apply IDB patch:', patchErr.message);
    }
});

// Helper to send the welcome poll dynamically
async function sendWelcomePoll(chatId, sender, config) {
    openChatWindowSafely(chatId);
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
        const createdAt = Date.now();
        const sentMsg = await sendBotMessage(chatId, welcomePoll);
        const msgId = sentMsg?.id?.id;
        const pollId = sentMsg?.id?._serialized || (msgId ? `true_${chatId}_${msgId}` : null);

        // Always register for monitoring — even if sentMsg is undefined (e.g. @lid contacts)
        // Use pollId as key when available, otherwise fall back to sender-based key
        const monitorKey = pollId || `sender:${sender}:${createdAt}`;
        activePollsToMonitor.set(monitorKey, {
            chatId: chatId,
            sender: sender,
            config: config,
            pollId: pollId,  // null for @lid contacts where sentMsg returns undefined
            createdAt: createdAt
        });
        
        // Reset user state to root
        const identities = await resolveIdentities(chatId);
        const state = {
            menuPath: [],
            lastPollId: pollId || null,
            lastPollTime: createdAt,
            currentOptions: menu.map((item, idx) => ({ index: idx, label: item.label, item: item }))
        };
        saveUserState(identities, state);
        console.log(`[Chatbot] Welcome Poll sent to ${sender}. monitorKey="${monitorKey}" pollId=${pollId}. Monitoring active.`);
    } catch (e) {
        console.error('[Chatbot] Error sending welcome poll:', e.message);
    }
}

// Helper to send text or api response as a poll if short enough, or text + separate poll if long
async function sendResponseAsPoll(chatId, sender, text, customOptions, config) {
    openChatWindowSafely(chatId);
    const cleanText = text || 'Informasi tidak tersedia.';
    const options = customOptions || ['🔙 Kembali ke Menu Utama', '📞 Hubungi Staff (Kasir)'];
    
    const mappedOptions = options.map((label, idx) => {
        let item = { type: 'back' };
        if (label.includes('Hubungi Staff') || label.includes('Kasir')) {
            item = { type: 'staff' };
        } else if (label.includes('tidak menemukan') || label.includes('cucian saya')) {
            item = { type: 'api', action: 'status_by_nota' };
        } else if (label.includes('Kembali')) {
            item = { type: 'back' };
        }
        return { index: idx, label: label, item: item };
    });

    if (cleanText.length <= 255) {
        try {
            const poll = new Poll(cleanText, options, { allowMultipleAnswers: false });
            const sentMsg = await sendBotMessage(chatId, poll);
            const msgId = sentMsg?.id?.id;
            const pollId = sentMsg?.id?._serialized || (msgId ? `true_${chatId}_${msgId}` : null);
            if (pollId) {
                activePollsToMonitor.set(pollId, {
                    chatId: chatId,
                    sender: sender,
                    config: config,
                    createdAt: Date.now()
                });
            }
            
            // Set user state to root with the new poll ID
            const identities = await resolveIdentities(chatId);
            const state = {
                menuPath: [],
                lastPollId: pollId || null,
                lastPollTime: Date.now(),
                currentOptions: mappedOptions
            };
            saveUserState(identities, state);
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
        const _backCreatedAt = Date.now();
        const sentMsg = await sendBotMessage(chatId, backPoll);
        const msgId = sentMsg?.id?.id;
        const pollId = sentMsg?.id?._serialized || (msgId ? `true_${chatId}_${msgId}` : null);
        const _backKey = pollId || `sender:${sender}:${_backCreatedAt}`;
        activePollsToMonitor.set(_backKey, {
            chatId: chatId, sender: sender, config: config,
            pollId: pollId, createdAt: _backCreatedAt
        });
        const identities = await resolveIdentities(chatId);
        const state = {
            menuPath: [],
            lastPollId: pollId || null,
            lastPollTime: Date.now(),
            currentOptions: mappedOptions
        };
        saveUserState(identities, state);
        console.log(`[Chatbot] Sent response as text + back poll to ${sender}.`);
    } catch (e) {
        console.error('[Chatbot] Error sending fallback response:', e.message);
    }
}

// Helper to execute a menu item action
async function executeMenuItem(chatId, sender, selectedItem, choiceIndex, config, pollId = null) {
    const identities = await resolveIdentities(chatId);
    const state = getUserState(identities) || { menuPath: [] };
    
    if (selectedItem.type === 'text') {
        const responseText = selectedItem.response || 'Informasi tidak tersedia.';
        await sendResponseAsPoll(chatId, sender, responseText, null, config);
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
                await sendResponseAsPoll(chatId, sender, responseText, customOpts, config);
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
                await sendResponseAsPoll(chatId, sender, responseText, customOpts, config);
            });
        } else if (selectedItem.action === 'status_by_nota') {
            userMenuState.set(sender, {
                menuPath: state.menuPath,
                lastPollId: pollId,
                lastPollTime: Date.now(),
                currentOptions: state.currentOptions,
                waitingForOrderId: true
            });
            await sendBotMessage(chatId, 'Silakan ketik nomor nota Kakak secara langsung (contoh: *123*) untuk melacak status pesanan tersebut.\n\n*(Catatan: Nomor nota dapat dilihat di bagian paling atas kertas nota fisik Kakak, di sebelah tulisan *Order: #* atau *Nota #*)*');
        } else {
            await sendResponseAsPoll(chatId, sender, 'Fitur otomatis ini belum tersedia.', null, config);
        }
    } 
    else if (selectedItem.type === 'staff') {
        const responseText = selectedItem.response || 'Hubungi kasir kami.';
        await sendBotMessage(chatId, responseText);
        
        staffChatCooldown.set(sender, Date.now());
        console.log(`[Chatbot] Customer ${sender} requested staff. Chatbot paused.`);

        try {
            const chat = await client.getChatById(chatId);
            await chat.markUnread();
            console.log(`[Chatbot] Marked chat ${sender} as unread for the admin.`);
        } catch (e) {
            console.error('[Chatbot] Error marking unread:', e.message);
        }
    } 
    else if (selectedItem.type === 'poll') {
        try {
            const options = (selectedItem.children || []).map(child => child.label);
            options.push('🔙 Kembali ke Menu Utama');

            const subPollTitle = selectedItem.poll_title || selectedItem.label || 'Pilih opsi:';
            const subPoll = new Poll(
                subPollTitle,
                options,
                { allowMultipleAnswers: false }
            );
            const _subCreatedAt = Date.now();
            const sentMsg = await sendBotMessage(chatId, subPoll);
            const msgId = sentMsg?.id?.id;
            const pollId = sentMsg?.id?._serialized || (msgId ? `true_${chatId}_${msgId}` : null);
            const _subKey = pollId || `sender:${sender}:${_subCreatedAt}`;
            if (true) {
                activePollsToMonitor.set(_subKey, {
                    chatId: chatId,
                    sender: sender,
                    config: config,
                    createdAt: Date.now()
                });
            }
            
            const mappedOptions = (selectedItem.children || []).map((child, idx) => ({ index: idx, label: child.label, item: child }));
            mappedOptions.push({ index: (selectedItem.children || []).length, label: '🔙 Kembali ke Menu Utama', item: { type: 'back' } });

            const identities = await resolveIdentities(chatId);
            const state = {
                menuPath: [choiceIndex],
                lastPollId: pollId || null,
                lastPollTime: Date.now(),
                currentOptions: mappedOptions
            };
            saveUserState(identities, state);
            console.log(`[Chatbot] Sent sub-poll to ${sender}. Path updated to [${choiceIndex}]`);
        } catch (e) {
            console.error('[Chatbot] Error sending sub-poll:', e.message);
        }
    } 
    else if (selectedItem.type === 'back') {
        await sendWelcomePoll(chatId, sender, config);
    }
}

// Helper to process vote selection (shared by event listener and manual polling)
async function handleVoteSelection(chatId, sender, choice, choiceIndex, config, pollId) {
    // Check if staff is chatting with this user (cooldown from config, default 30 min)
    const lastStaffChat = staffChatCooldown.get(sender) || 0;
    const staffCooldownMs = (config.chatbot_staff_cooldown !== undefined ? config.chatbot_staff_cooldown : 30) * 60 * 1000;
    if (Date.now() - lastStaffChat < staffCooldownMs) {
        console.log(`[Chatbot] Skipping vote reply for ${sender} karena auto-reply sedang di-pause (staff manual message terdeteksi dalam 30 menit terakhir).`);
        return;
    }

    // Get or initialize user state
    const identities = await resolveIdentities(chatId);
    let state = getUserState(identities);
    if (!state) {
        state = { menuPath: [], lastPollId: pollId, lastPollTime: Date.now() };
        saveUserState(identities, state);
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
    
    // Optionally delete the voted poll message for everyone
    if (config.chatbot_delete_polls === true && pollId) {
        try {
            client.getMessageById(pollId).then(async (msg) => {
                if (msg) {
                    await msg.delete(true);
                    console.log(`[Chatbot] Voted poll ${pollId} deleted for everyone.`);
                }
            }).catch(e => {
                console.error('[Chatbot] Failed to retrieve/delete poll message:', e.message);
            });
        } catch (e) {
            console.error('[Chatbot] Error scheduling poll deletion:', e.message);
        }
    }

    await executeMenuItem(chatId, sender, selectedItem, choiceIndex, config, pollId);
}

// Helper to manually query votes directly in browser context
// messageId: specific poll ID to filter by (null = return all votes)
// since: Unix ms timestamp — only return votes newer than this
async function getPollVotesDirectly(messageId, since) {
    if (!isReady || !client.pupPage) return [];
    try {
        const pollVotes = await client.pupPage.evaluate(async (messageId, since) => {
            try {
                const schema = window.require('WAWebPollsVotesSchema');
                const table = schema.getTable();
                const allVotes = await table.all();

                const shortMsgId = messageId ? messageId.split('_').pop() : null;

                const filtered = allVotes.filter(item => {
                    // Filter by specific poll if messageId provided
                    if (messageId) {
                        if (!item.parentMsgKey) return false;
                        try {
                            const parentKey = item.parentMsgKey._serialized ||
                                (item.parentMsgKey.toString ? item.parentMsgKey.toString() : '');
                            if (parentKey !== messageId &&
                                !(shortMsgId && shortMsgId.length > 8 && parentKey.includes(shortMsgId))) {
                                return false;
                            }
                        } catch (e) { return false; }
                    }
                    // Filter by timestamp if 'since' provided (for sender-based monitoring)
                    if (since && item.senderTimestampMs && item.senderTimestampMs <= since) return false;
                    return true;
                });

                return filtered.map((item) => {
                    const typedArray = new Uint8Array(item.selectedOptionLocalIds);
                    return {
                        voter: item.sender ? (item.sender._serialized || item.sender) : null,
                        selectedOptionLocalIds: Array.from(typedArray),
                        senderTimestampMs: item.senderTimestampMs || 0
                    };
                });
            } catch (innerErr) {
                return { error: innerErr.message };
            }
        }, messageId, since);

        if (pollVotes && pollVotes.error) {
            console.error('[PollMonitor] Browser IDB error:', pollVotes.error);
            return [];
        }
        if (pollVotes && pollVotes.length > 0) {
            console.log('[PollMonitor] Browser db returned:', JSON.stringify(pollVotes));
        }
        return pollVotes || [];
    } catch (e) {
        console.error('[PollMonitor] Puppeteer error in getPollVotesDirectly:', e.message);
        return [];
    }
}

// Counter for periodic debug logging
let _pollCheckCount = 0;

// Function to manually query votes for active polls (Workaround for unstable vote_update event)
async function checkActivePollVotes() {
    // Only check and log if WhatsApp is connected AND there are active polls waiting for customer vote
    if (!isReady || activePollsToMonitor.size === 0) return;

    _pollCheckCount++;
    if (_pollCheckCount <= 5 || _pollCheckCount % 40 === 0) {
        console.log(`[PollMonitor] ⏱ Timer #${_pollCheckCount}: isReady=${isReady} activePolls=${activePollsToMonitor.size}${activePollsToMonitor.size > 0 ? ' IDs: ' + [...activePollsToMonitor.keys()].map(k => k.split('_').pop()).join(', ') : ''}`);
    }

    const now = Date.now();
    for (const [pollId, info] of activePollsToMonitor.entries()) {
        // Expire polls after 10 minutes to avoid memory leak
        if (now - info.createdAt > 10 * 60 * 1000) {
            activePollsToMonitor.delete(pollId);
            continue;
        }

        try {
            // If info.pollId is null (e.g. @lid contacts where sentMsg returns undefined),
            // use sender+timestamp filtering instead of pollId-based IDB lookup
            const votes = info.pollId
                ? await getPollVotesDirectly(info.pollId, null)
                : await getPollVotesDirectly(null, info.createdAt);
            if (votes && votes.length > 0) {
                console.log(`[PollMonitor] Poll ${pollId} has votes: ${JSON.stringify(votes)}`);
                const cleanChatId = info.chatId.replace('@c.us', '').replace('@lid', '');
                const cleanSender = info.sender.replace('@c.us', '').replace('@lid', '');

                // FIX Bug #4: async loop to handle LID↔phone mismatch via contact lookup
                let userVote = null;
                for (const v of votes) {
                    const voter = v.voter || '';
                    const cleanVoter = voter.replace('@c.us', '').replace('@lid', '');

                    let matched = cleanVoter === cleanChatId || cleanVoter === cleanSender;

                    // If no direct string match, resolve contact to compare phone number
                    if (!matched && voter) {
                        try {
                            const voterContact = await client.getContactById(voter);
                            if (voterContact && voterContact.number) {
                                const resolvedPhone = voterContact.number;
                                matched = resolvedPhone === cleanSender || resolvedPhone === cleanChatId;
                                if (matched) {
                                    console.log(`[PollMonitor] Voter resolved via contact lookup: ${cleanVoter} → ${resolvedPhone}`);
                                }
                            }
                        } catch (e) { /* ignore lookup errors */ }
                    }

                    console.log(`[PollMonitor] Voter check: cleanVoter="${cleanVoter}", cleanSender="${cleanSender}". Matched: ${matched}`);
                    if (matched) {
                        userVote = v;
                        break;
                    }
                }

                if (userVote && userVote.selectedOptionLocalIds && userVote.selectedOptionLocalIds.length > 0) {
                    const choiceIndex = userVote.selectedOptionLocalIds[0];

                    const identities = await resolveIdentities(info.sender);
                    const state = getUserState(identities);
                    const matchedOpt = state && state.currentOptions ? state.currentOptions[choiceIndex] : null;
                    const choice = matchedOpt ? matchedOpt.label : `Option ${choiceIndex + 1}`;

                    console.log(`[PollMonitor] Detected matching vote on poll ${pollId} from ${info.sender}: "${choice}" (Index: ${choiceIndex})`);

                    // Remove from tracking and guard against duplicate processing
                    activePollsToMonitor.delete(pollId);
                    const shortPollId = pollId.split('_').pop() || pollId;
                    if (processedPollIds.has(shortPollId) || processedPollIds.has(pollId)) {
                        continue;
                    }
                    processedPollIds.add(pollId);
                    processedPollIds.add(shortPollId);

                    // FIX Bug #3: unmark on failure so vote_update can still retry
                    try {
                        await handleVoteSelection(info.chatId, info.sender, choice, choiceIndex, info.config, pollId);
                    } catch (handleErr) {
                        console.error(`[PollMonitor] handleVoteSelection failed for poll ${pollId}:`, handleErr.message);
                        processedPollIds.delete(pollId);
                        processedPollIds.delete(shortPollId);
                    }
                }
            }
        } catch (e) {
            if (!e.message.includes('idb failed')) {
                console.error(`[PollMonitor] Error checking poll ${pollId}:`, e.message);
            }
        }
    }
}

// Query active polls every 1.5 seconds
setInterval(checkActivePollVotes, 1500);

// Poll Vote Update event
client.on('vote_update', async (vote) => {
    // 1. Maintain test vote state
    const identities = await resolveIdentities(vote.voter);
    let sender = identities.phone || identities.lid || vote.voter.replace('@c.us', '').replace('@lid', '');
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
    
    const pollId = vote.parentMsgKey ? vote.parentMsgKey._serialized || vote.parentMsgKey.id : null;
    if (pollId) {
        const shortPollId = pollId.split('_').pop() || pollId;
        if (processedPollIds.has(shortPollId) || processedPollIds.has(pollId)) {
            console.log(`[vote_update] Poll ${pollId} already processed, skipping.`);
            return;
        }
        // Mark as processed immediately to block the timer from interfering
        processedPollIds.add(pollId);
        processedPollIds.add(shortPollId);
    }

    // FIX Bug #1: vote.voter may be @lid format on newer WhatsApp — resolve to @c.us for sending
    let chatId = vote.voter;
    try {
        const voterContact = await client.getContactById(vote.voter);
        if (voterContact && voterContact.number) {
            chatId = `${voterContact.number}@c.us`;
            console.log(`[vote_update] Resolved chatId from voter ${vote.voter} → ${chatId}`);
        }
    } catch (e) {
        console.log(`[vote_update] Could not resolve contact for voter ${vote.voter}, using as-is`);
    }

    const choice = vote.selectedOptions[0].name;
    const choiceIndex = vote.selectedOptions[0].localId;

    // FIX Bug #3: unmark from processedPollIds on failure so the timer can retry
    try {
        await handleVoteSelection(chatId, sender, choice, choiceIndex, config, pollId);
    } catch (e) {
        console.error('[vote_update] Error in handleVoteSelection:', e.message);
        if (pollId) {
            const shortPollId = pollId.split('_').pop() || pollId;
            processedPollIds.delete(pollId);
            processedPollIds.delete(shortPollId);
        }
    }
});

// Incoming message listener (Trigger Welcome Poll or status commands)
client.on('message', async (msg) => {
    // Ignore groups or self messages
    if (msg.from.endsWith('@g.us')) return;
    if (msg.fromMe) return;

    openChatWindowSafely(msg.from);

    const config = loadConfig();
    if (config.chatbot_enabled === false) return;

    const identities = await resolveIdentities(msg);
    const sender = identities.phone || identities.lid || msg.from.replace('@c.us', '').replace('@lid', '');

    // Use msg.from directly as chatId — for LID contacts this is @lid format which is required
    // (attempting to use @c.us for LID users causes "No LID for user" error)
    const chatId = msg.from;
    
    // Custom check: status [order_id]
    const msgText = msg.body ? msg.body.trim() : '';
    const msgTextLower = msgText.toLowerCase();
    
    // Check if we are waiting for an order ID from this user
    let state = getUserState(identities);
    if (state && state.waitingForOrderId) {
        if (msgTextLower.includes('batal') || msgTextLower.includes('kembali')) {
            state.waitingForOrderId = false;
            saveUserState(identities, state);
            await sendWelcomePoll(chatId, sender, config);
            return;
        }
        
        const numMatch = msgText.match(/\d+/);
        if (numMatch) {
            const orderId = parseInt(numMatch[0], 10);
            const port = config.api_port || 5001;
            const url = `http://localhost:${port}/api/wa/chatbot/status-cucian?order_id=${orderId}`;
            
            // Reset waiting state
            state.waitingForOrderId = false;
            saveUserState(identities, state);
            
            http.get(url, (res) => {
                let data = '';
                res.on('data', (chunk) => {
                    data += chunk;
                });
                res.on('end', async () => {
                    try {
                        const parsed = JSON.parse(data);
                        await sendResponseAsPoll(chatId, sender, parsed.message, null, config);
                    } catch (e) {
                        await sendResponseAsPoll(chatId, sender, 'Maaf Kak, terjadi kesalahan saat memproses data status Anda.', null, config);
                    }
                });
            }).on('error', async (err) => {
                console.error('[Chatbot] Error checking status by ID:', err.message);
                await sendResponseAsPoll(chatId, sender, 'Maaf Kak, gagal menghubungi server status laundry.', null, config);
            });
            return;
        } else {
            await sendBotMessage(chatId, 'Nomor nota tidak valid. Silakan ketik angka saja (contoh: *123*).\n\n*(Catatan: Nomor nota dapat dilihat di bagian paling atas kertas nota fisik Kakak, di sebelah tulisan *Order: #* atau *Nota #*)*\n\nKetik *batal* jika ingin kembali ke menu utama.');
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
                    await sendResponseAsPoll(chatId, sender, parsed.message, null, config);
                } catch (e) {
                    await sendResponseAsPoll(chatId, sender, 'Maaf Kak, terjadi kesalahan saat memproses data status Anda.', null, config);
                }
            });
        }).on('error', async (err) => {
            console.error('[Chatbot] Error checking status by ID:', err.message);
            await sendResponseAsPoll(chatId, sender, 'Maaf Kak, gagal menghubungi server status laundry.', null, config);
        });
        return; // Skip welcome poll trigger
    }

    // Check if staff is chatting (cooldown from config, default 30 min)
    const lastStaffChat = staffChatCooldown.get(sender) || 0;
    const staffCooldownMs = (config.chatbot_staff_cooldown !== undefined ? config.chatbot_staff_cooldown : 30) * 60 * 1000;
    if (Date.now() - lastStaffChat < staffCooldownMs) {
        console.log(`[Chatbot] Mengabaikan chat dari ${sender} karena auto-reply sedang di-pause (staff manual message terdeteksi dalam 30 menit terakhir).`);
        return;
    }

    // --- FALLBACK OPTIONS MATCHING FOR TEXT INPUT ---
    if (state && state.currentOptions && state.currentOptions.length > 0) {
        let matchedOption = null;
        const cleanMsgText = msgTextLower.replace(/[^a-z0-9]/g, '');
        
        const numMatch = msgText.trim().match(/^(\d+)$/);
        if (numMatch) {
            const selectedIndex = parseInt(numMatch[1], 10) - 1;
            if (selectedIndex >= 0 && selectedIndex < state.currentOptions.length) {
                matchedOption = state.currentOptions[selectedIndex];
            }
        } else {
            matchedOption = state.currentOptions.find(opt => {
                const cleanOptLabel = opt.label.toLowerCase().replace(/[^a-z0-9]/g, '');
                // If input is short (less than 3 chars), enforce exact match
                if (cleanMsgText.length < 3) {
                    return cleanMsgText === cleanOptLabel;
                }
                return cleanMsgText.includes(cleanOptLabel) || cleanOptLabel.includes(cleanMsgText);
            });
            
            // Global keyphrase checks if no label matched directly
            if (!matchedOption) {
                if (cleanMsgText.length >= 3) {
                    if (cleanMsgText.includes('kembali') || cleanMsgText === 'menu') {
                        matchedOption = state.currentOptions.find(opt => opt.item.type === 'back' || opt.label.includes('Kembali'));
                    } else if (cleanMsgText.includes('staff') || cleanMsgText.includes('kasir') || cleanMsgText.includes('hubungi')) {
                        matchedOption = state.currentOptions.find(opt => opt.item.type === 'staff' || opt.label.includes('Staff') || opt.label.includes('Kasir'));
                    } else if (cleanMsgText.includes('tidakmenemukan') || cleanMsgText.includes('nota') || cleanMsgText.includes('lacak')) {
                        matchedOption = state.currentOptions.find(opt => opt.item.action === 'status_by_nota' || opt.label.includes('tidak menemukan') || opt.label.includes('Nota'));
                    }
                }
            }
        }

        if (matchedOption) {
            console.log(`[Chatbot] Text input matched option: "${matchedOption.label}" for sender ${sender}`);
            const choiceIndex = matchedOption.index !== undefined ? matchedOption.index : 0;
            
            await executeMenuItem(chatId, sender, matchedOption.item, choiceIndex, config);
            return; // Skip sending welcome poll
        }
    }

    // Check if welcome poll already sent recently (cooldown from config, default 15 min)
    const lastWelcomePoll = welcomePollCooldown.get(sender) || 0;
    const welcomeCooldownMs = (config.chatbot_welcome_cooldown !== undefined ? config.chatbot_welcome_cooldown : 0) * 60 * 1000;
    if (Date.now() - lastWelcomePoll < welcomeCooldownMs) {
        return;
    }

    // Mark welcome poll as sent
    welcomePollCooldown.set(sender, Date.now());

    await sendWelcomePoll(chatId, sender, config);
});

// Detect staff manual chat to pause chatbot (message_create)
client.on('message_create', (msg) => {
    if (msg.fromMe && msg.to && !msg.to.endsWith('@g.us')) {
        const to = msg.to.replace('@c.us', '').replace('@lid', '');
        const msgId = msg.id.id;
        
        // If this is currently being sent by the bot, skip the manual staff message check completely
        if (activeSends.has(msg.to) || activeSends.has(to)) {
            return;
        }

        // Delay processing to allow the client.sendMessage promise to resolve and register the ID
        setTimeout(() => {
            if (botSentMessageIds.has(msgId)) {
                botSentMessageIds.delete(msgId); // Clean up
                return;
            }
            if (activeSends.has(msg.to) || activeSends.has(to)) {
                return;
            }
            
            staffChatCooldown.set(to, Date.now());
            console.log(`[Chatbot] Staff manual message detected. Chatbot auto-reply paused for ${to} for 30 minutes.`);
        }, 1000); // Increased timeout to 1s for safety
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
 * GET /open-gui
 * Activates and brings the live WhatsApp Web GUI window to the front
 */
app.get('/open-gui', async (req, res) => {
    lastRequestTime = Date.now();
    try {
        if (!isReady && !isInitializing) {
            initializeClient();
            return res.json({ success: true, message: 'Menginisialisasi jendela WhatsApp Web...' });
        }

        if (client.pupPage) {
            await client.pupPage.bringToFront();
            if (process.platform === 'win32') {
                const { exec } = require('child_process');
                exec('powershell -NoProfile -Command "(New-Object -ComObject WScript.Shell).AppActivate(\'WhatsApp\')"');
            }
            return res.json({ success: true, message: 'Jendela WhatsApp Web telah dibuka.' });
        } else {
            initializeClient();
            return res.json({ success: true, message: 'Mengaktifkan browser WhatsApp Web...' });
        }
    } catch (e) {
        console.error('[WA] Error on /open-gui:', e.message);
        res.status(500).json({ success: false, error: e.message });
    }
});

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
 * GET /debug/db
 * Returns a dump of browser-side poll and message collections
 */
app.get('/debug/db', async (req, res) => {
    if (!isReady || !client.pupPage) {
        return res.json({ error: 'Client not ready' });
    }
    try {
        const data = await client.pupPage.evaluate(async () => {
            try {
                const results = {};
                const schema = window.require('WAWebPollsVotesSchema');
                if (schema.getTable) {
                    const table = schema.getTable();
                    const items = await table.all();
                    results.votes = items.map(item => {
                        const cleanItem = { ...item };
                        if (cleanItem.selectedOptionLocalIds) {
                            cleanItem.selectedOptionLocalIds = Array.from(new Uint8Array(cleanItem.selectedOptionLocalIds));
                        }
                        if (cleanItem.sender) {
                            cleanItem.sender = cleanItem.sender._serialized || cleanItem.sender.toString() || cleanItem.sender;
                        }
                        if (cleanItem.id) {
                            cleanItem.id = cleanItem.id._serialized || cleanItem.id.toString() || cleanItem.id;
                        }
                        return cleanItem;
                    });
                }
                return results;
            } catch (e) {
                return { error: e.message };
            }
        });
        res.json(data);
    } catch (e) {
        res.json({ error: e.message });
    }
});

/**
 * GET /debug/unpause
 * Clears the staff manual message cooldown for testing purposes
 */
app.get('/debug/unpause', (req, res) => {
    staffChatCooldown.clear();
    console.log('[Chatbot] All chatbot pauses cleared via debug endpoint!');
    res.json({
        success: true,
        message: 'Semua jeda/pause chatbot telah dihapus. Bot siap merespon kembali!'
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

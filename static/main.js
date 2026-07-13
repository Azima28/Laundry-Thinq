// 1. View Switching Logic
const navBtns = document.querySelectorAll('.nav-btn');
navBtns.forEach(btn => {
    btn.addEventListener('click', (e) => {
        e.preventDefault();
        const targetView = btn.getAttribute('data-view');

        // Update all buttons with the same data-view (sync desktop and mobile)
        navBtns.forEach(b => {
            if (b.getAttribute('data-view') === targetView) {
                b.classList.add('active');
            } else {
                b.classList.remove('active');
            }
        });

        // Switch views
        document.querySelectorAll('.dashboard-view').forEach(v => {
            v.classList.remove('active');
        });
        document.getElementById(`${targetView}-view`).classList.add('active');

        // If analytics view, fetch stats and update charts
        if (targetView === 'analytics') {
            updateAnalytics();
        }

        // If settings view, fetch LG status
        if (targetView === 'settings') {
            showSettingsMain();
        }

        // If machine-logs view, load logs
        if (targetView === 'machine-logs') {
            initMachineLogs();
        }
    });
});

// 2. Global Error Monitoring
function checkGlobalErrors() {
    const errorCards = document.querySelectorAll('.error-msg-container.visible');
    const globalBanner = document.getElementById('global-error-banner');
    if (!globalBanner) return;
    if (errorCards.length > 0) {
        globalBanner.style.display = 'flex';
        const msg = document.querySelector('.alert-message');
        if (msg) msg.textContent = `Peringatan: Terdapat ${errorCards.length} mesin yang mengalami gangguan!`;
    } else {
        globalBanner.style.display = 'none';
    }
}

// Initial check on load
window.addEventListener('load', () => {
    checkGlobalErrors();
    initMonitoringFilters();
});

function initMonitoringFilters() {
    const filterChips = document.querySelectorAll('.filter-chip');
    const machineCards = document.querySelectorAll('.machine-card');

    function applyFilter(filter) {
        machineCards.forEach(card => {
            const machineId = card.id.toLowerCase();
            if (filter === 'cuci') {
                if (machineId.includes('cuci')) {
                    card.style.display = 'block';
                } else {
                    card.style.display = 'none';
                }
            } else if (filter === 'pengering') {
                if (machineId.includes('pengering') || machineId.includes('dryer')) {
                    card.style.display = 'block';
                } else {
                    card.style.display = 'none';
                }
            } else if (filter === 'all') {
                card.style.display = 'block';
            }
        });
    }

    filterChips.forEach(chip => {
        chip.addEventListener('click', () => {
            filterChips.forEach(c => c.classList.remove('active'));
            chip.classList.add('active');
            const filter = chip.getAttribute('data-filter');
            applyFilter(filter);
        });
    });

    const activeChip = document.querySelector('.filter-chip.active');
    if (activeChip) {
        applyFilter(activeChip.getAttribute('data-filter'));
    }
}

// 2. Refresh & Filter Logic
const filterMachine = document.getElementById('filter-machine');
const filterAction = document.getElementById('filter-action');
const filterDate = document.getElementById('filter-date');
const filterSource = document.getElementById('filter-source');

if (filterMachine && filterAction && filterDate) {
    [filterMachine, filterAction, filterDate, filterSource].forEach(el => {
        if (el) el.addEventListener('change', () => fetchHistory());
    });
}

const refreshBtn = document.getElementById('refresh-logs');
if (refreshBtn) {
    refreshBtn.addEventListener('click', () => fetchHistory());
}

async function fetchHistory() {
    const body = document.getElementById('history-body');
    if (!body) return;
    body.innerHTML = '<tr><td colspan="4" style="text-align: center; padding: 40px;">Memuat data...</td></tr>';

    const machine = filterMachine.value;
    const action = filterAction.value;
    const date = filterDate.value;
    const source = filterSource ? filterSource.value : 'all';

    const params = new URLSearchParams({ limit: 100 });
    if (machine !== 'all') params.append('machine', machine);
    if (action !== 'all') params.append('action', action);
    if (date) params.append('date', date);
    if (source !== 'all') params.append('source', source);

    try {
        const response = await fetch(`/api/logs?${params.toString()}`);
        const logs = await response.json();

        if (!Array.isArray(logs)) {
            const errorMsg = logs.error || 'Format data tidak valid';
            body.innerHTML = `<tr><td colspan="4" style="text-align: center; padding: 40px; color: var(--color-danger);">Gagal: ${errorMsg}</td></tr>`;
            updateHistoryStats([]);
            return;
        }

        if (logs.length === 0) {
            body.innerHTML = '<tr><td colspan="4" style="text-align: center; padding: 40px; color: var(--text-muted);">Tidak ada data yang cocok dengan filter.</td></tr>';
            updateHistoryStats([]);
            return;
        }

        body.innerHTML = logs.map(log => `
            <tr>
                <td>${log.timestamp}</td>
                <td><strong>${log.short_name}</strong></td>
                <td><span class="badge-${(log.action || '').toLowerCase().split(':')[0].trim()}">${log.action}</span></td>
                <td class="hide-mobile">
                    <span class="source-badge source-${(log.source || 'customer').toLowerCase()}">
                        ${log.source === 'admin' ? '<i data-lucide="user-cog" style="width: 14px; height: 14px; vertical-align: middle; margin-right: 4px;"></i> Admin' : (log.source === 'customer' || !log.source ? '<i data-lucide="users" style="width: 14px; height: 14px; vertical-align: middle; margin-right: 4px;"></i> Customer' : '<i data-lucide="user" style="width: 14px; height: 14px; vertical-align: middle; margin-right: 4px;"></i> ' + log.source.charAt(0).toUpperCase() + log.source.slice(1))}
                    </span>
                </td>
                <td class="hide-mobile" style="color: var(--text-muted); font-size: 0.8rem;">${log.entity_id}</td>
            </tr>
        `).join('');

        lucide.createIcons();
        updateHistoryStats(logs);
    } catch (error) {
        body.innerHTML = '<tr><td colspan="4" style="text-align: center; padding: 40px; color: var(--color-danger);">Gagal memuat data riwayat.</td></tr>';
        updateHistoryStats([]);
    }
}

function updateHistoryStats(logs) {
    let countOn = 0, countOff = 0, countError = 0;
    logs.forEach(log => {
        const action = (log.action || '').toUpperCase();
        if (action === 'ON') countOn++;
        else if (action === 'OFF') countOff++;
        else if (action.startsWith('ERROR')) countError++;
    });
    const sOn = document.getElementById('stat-on');
    const sOff = document.getElementById('stat-off');
    const sErr = document.getElementById('stat-error');
    const sTot = document.getElementById('stat-total');
    if (sOn) sOn.textContent = countOn;
    if (sOff) sOff.textContent = countOff;
    if (sErr) sErr.textContent = countError;
    if (sTot) sTot.textContent = logs.length;
}

// --- ANALYTICS LOGIC ---
let dailyChart, machineChart;
async function updateAnalytics() {
    try {
        const response = await fetch('/api/stats');
        const data = await response.json();
        renderDailyChart(data.daily);
        renderMachineChart(data.machines);
    } catch (error) { console.error('Error fetching stats:', error); }
}

function renderDailyChart(dailyData) {
    const canvas = document.getElementById('dailyUsageChart');
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    const labels = Object.keys(dailyData).map(d => d.split('-').slice(1).join('-'));
    const values = Object.values(dailyData);
    if (dailyChart) {
        dailyChart.data.labels = labels;
        dailyChart.data.datasets[0].data = values;
        dailyChart.update();
        return;
    }
    dailyChart = new Chart(ctx, {
        type: 'line',
        data: {
            labels: labels,
            datasets: [{
                label: 'Total Penggunaan',
                data: values,
                borderColor: '#a855f7',
                backgroundColor: 'rgba(168, 85, 247, 0.1)',
                fill: true,
                tension: 0.4,
                borderWidth: 3,
                pointBackgroundColor: '#a855f7',
                pointRadius: 4
            }]
        },
        options: {
            responsive: true,
            plugins: { legend: { display: false } },
            scales: {
                y: { beginAtZero: true, ticks: { stepSize: 1, color: '#94a3b8' }, grid: { color: 'rgba(255, 255, 255, 0.05)' } },
                x: { ticks: { color: '#94a3b8' }, grid: { display: false } }
            }
        }
    });
}

function renderMachineChart(machineData) {
    const canvas = document.getElementById('machineUsageChart');
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    const labels = Object.keys(machineData).map(key => key.replace(/_/g, ' ').replace(/\b\w/g, l => l.toUpperCase()));
    const values = Object.values(machineData);
    if (machineChart) {
        machineChart.data.labels = labels;
        machineChart.data.datasets[0].data = values;
        machineChart.update();
        return;
    }
    machineChart = new Chart(ctx, {
        type: 'bar',
        data: {
            labels: labels,
            datasets: [{
                label: 'Total Penggunaan',
                data: values,
                backgroundColor: ['#a855f7', '#ec4899', '#3b82f6', '#10b981', '#f59e0b', '#ef4444'],
                borderRadius: 8,
                borderSkipped: false,
            }]
        },
        options: {
            responsive: true,
            indexAxis: 'y',
            plugins: { legend: { display: false } },
            scales: {
                x: { beginAtZero: true, ticks: { stepSize: 1, color: '#94a3b8' }, grid: { color: 'rgba(255, 255, 255, 0.05)' } },
                y: { ticks: { color: '#94a3b8' }, grid: { display: false } }
            }
        }
    });
}

function handleLogEvent(data) {
    const parts = data.split('|');
    const timestamp = parts[1], short_name = parts[2], action = parts[3], entity_id = parts[4];
    const source = parts[5] || 'customer';
    const body = document.getElementById('history-body');
    if (!body) return;

    const fMachine = filterMachine.value, fAction = filterAction.value, fDate = filterDate.value;
    const fSource = filterSource ? filterSource.value : 'all';

    if (fMachine !== 'all' && fMachine !== entity_id && fMachine !== short_name) return;
    if (fAction !== 'all' && fAction.toLowerCase() !== action.toLowerCase()) return;
    if (fDate && !timestamp.startsWith(fDate)) return;
    if (fSource !== 'all' && fSource.toLowerCase() !== source.toLowerCase()) return;

    const tr = document.createElement('tr');
    tr.style.animation = 'fadeInDown 0.5s ease-out';
    tr.innerHTML = `
        <td>${timestamp}</td><td><strong>${short_name}</strong></td>
        <td><span class="badge-${action.toLowerCase()}">${action}</span></td>
        <td>
            <span class="source-badge source-${source.toLowerCase()}">
                ${source === 'admin' ? '<i data-lucide="user-cog" style="width: 14px; height: 14px; vertical-align: middle; margin-right: 4px;"></i> Admin' : (source === 'system' ? '<i data-lucide="cpu" style="width: 14px; height: 14px; vertical-align: middle; margin-right: 4px;"></i> System' : (source === 'customer' ? '<i data-lucide="users" style="width: 14px; height: 14px; vertical-align: middle; margin-right: 4px;"></i> Customer' : '<i data-lucide="user" style="width: 14px; height: 14px; vertical-align: middle; margin-right: 4px;"></i> ' + source.charAt(0).toUpperCase() + source.slice(1)))}
            </span>
        </td>
        <td class="hide-mobile" style="color: var(--text-muted); font-size: 0.8rem;">${entity_id}</td>
    `;
    if (body.querySelector('td[colspan]')) body.innerHTML = '';
    body.insertBefore(tr, body.firstChild);
    lucide.createIcons();
    while (body.children.length > 100) body.removeChild(body.lastChild);
}

// 3. Real-time Monitoring Logic (SSE)
const evtSource = new EventSource("/events");

function getProgressPercentage(timeString) {
    if (timeString === '--:--') return 0;
    const [minutes, seconds] = timeString.split(':').map(Number);
    const remainingSeconds = minutes * 60 + seconds;
    const maxTimeSeconds = 3600;
    if (remainingSeconds <= 0) return 100;
    if (remainingSeconds > maxTimeSeconds) return 0;
    return Math.min(100, Math.max(0, ((maxTimeSeconds - remainingSeconds) / maxTimeSeconds) * 100));
}

evtSource.onmessage = function (e) {
    if (e.data.startsWith('LOG|')) { handleLogEvent(e.data); return; }
    if (e.data.startsWith('ML_LOG|')) { handleMachineLogEvent(e.data); return; }
    const parts = e.data.split("|");
    const [sensor, state, run_state, remain_time, current_course, error_msg, completed, control_time] = parts;
    let card = document.getElementById(sensor);
    if (!card) return; // Simplified: don't dynamic create for now to keep it lean

    const statusBadge = card.querySelector('.status-badge');
    let statusClass = state.toLowerCase().trim();
    if (statusClass === 'ready' || statusClass === 'off') statusClass = 'ready';
    card.setAttribute('data-status', statusClass);
    if (statusBadge) {
        statusBadge.className = `status-badge status-${statusClass}`;
        statusBadge.textContent = state;
    }
    const cycleVal = card.querySelector('.value.cycle');
    const courseVal = card.querySelector('.value.course');
    const timeVal = card.querySelector('.value.time');
    const controlVal = card.querySelector('.value.control');
    if (cycleVal) cycleVal.textContent = run_state;
    if (courseVal) courseVal.textContent = current_course;
    if (timeVal) timeVal.textContent = remain_time;

    // Handle control field (position 7) - show/hide and update
    const detailGrid = card.querySelector('.detail-grid');
    if (control_time && control_time !== '-' && control_time !== '') {
        if (controlVal) {
            controlVal.textContent = control_time;
        } else if (detailGrid) {
            // Create control field if it doesn't exist
            const labelSpan = document.createElement('span');
            labelSpan.className = 'label';
            labelSpan.textContent = 'Control:';
            const valueSpan = document.createElement('span');
            valueSpan.className = 'value control';
            valueSpan.style.color = '#f59e0b';
            valueSpan.textContent = control_time;
            detailGrid.appendChild(labelSpan);
            detailGrid.appendChild(valueSpan);
        }
    } else {
        // Remove control field if exists and timer is off
        if (controlVal) {
            const labelEl = controlVal.previousElementSibling;
            if (labelEl && labelEl.classList.contains('label')) labelEl.remove();
            controlVal.remove();
        }
    }

    const ctrlState = document.getElementById(`control-state-${sensor}`);
    const ctrlTime = document.getElementById(`control-time-${sensor}`);
    if (ctrlState) { ctrlState.textContent = state; ctrlState.className = `info-value state-text state-${state.toLowerCase()}`; }
    if (ctrlTime) ctrlTime.textContent = remain_time;

    const errorContainer = card.querySelector('.error-msg-container');
    const errorText = card.querySelector('.error-text');
    if (error_msg && error_msg !== '-' && error_msg !== '') {
        if (errorText) errorText.textContent = error_msg;
        if (errorContainer) errorContainer.classList.add('visible');
    } else {
        if (errorContainer) errorContainer.classList.remove('visible');
    }

    const progressBar = card.querySelector('.progress-bar');
    if (progressBar) {
        if (statusClass === 'running') progressBar.style.width = `${getProgressPercentage(remain_time)}%`;
        else if (statusClass === 'error') progressBar.style.width = '100%';
        else progressBar.style.width = '0%';
    }
    checkGlobalErrors();
};

async function adminControl(entityId, action) {
    const durationInput = document.getElementById(`duration-${entityId}`);
    const bypassCheckbox = document.getElementById('bypass-cooldown');
    const statusDiv = document.getElementById(`control-status-${entityId}`);
    const duration = parseInt(durationInput.value) || 5;
    const bypassCooldown = bypassCheckbox.checked;
    if (statusDiv) { statusDiv.textContent = 'Processing...'; statusDiv.style.color = '#f59e0b'; }
    try {
        const response = await fetch('/api/admin/control', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ entity_id: entityId, action: action, duration: duration, bypass_cooldown: bypassCooldown })
        });
        const result = await response.json();
        if (response.ok) {
            statusDiv.innerHTML = `<i data-lucide="check" style="width: 14px; height: 14px; vertical-align: middle; margin-right: 4px;"></i> ${action.toUpperCase()} berhasil (${duration} menit)`;
            statusDiv.style.color = '#10b981';
            lucide.createIcons();
            if (document.getElementById('history-view').classList.contains('active')) fetchHistory();
        } else {
            if (response.status === 423 && result.bypass_available) { statusDiv.textContent = '⚠️ Cooldown! Use Force Control.'; statusDiv.style.color = '#ff4757'; }
            else { statusDiv.innerHTML = `<i data-lucide="x" style="width: 14px; height: 14px; vertical-align: middle; margin-right: 4px;"></i> Error: ${result.error}`; statusDiv.style.color = '#ff4757'; lucide.createIcons(); }
        }
    } catch (error) { statusDiv.textContent = '❌ Gagal menghubungi server'; statusDiv.style.color = '#ff4757'; }
    setTimeout(() => { if (statusDiv) { statusDiv.innerHTML = 'Ready'; statusDiv.style.color = ''; } }, 5000);
}

// --- SETTINGS NAVIGATION ---
function showSettingsMain() {
    document.querySelectorAll('.settings-subview').forEach(v => { v.style.display = 'none'; v.classList.remove('active'); });
    const main = document.getElementById('settings-main');
    if (main) { main.style.display = 'block'; main.classList.add('active'); }
    const backBtn = document.getElementById('btn-settings-back');
    if (backBtn) backBtn.style.display = 'none';
    const title = document.getElementById('settings-title');
    const sub = document.getElementById('settings-subtitle');
    if (title) title.innerHTML = '<i data-lucide="settings" style="width: 24px; height: 24px; vertical-align: middle; margin-right: 12px;"></i>Pengaturan';
    if (sub) sub.textContent = 'Konfigurasi dan preferensi sistem';
    lucide.createIcons();
    checkLgStatus();
}

function showSettingsLg() {
    document.querySelectorAll('.settings-subview').forEach(v => { v.style.display = 'none'; v.classList.remove('active'); });
    const lgView = document.getElementById('settings-lg');
    if (lgView) { lgView.style.display = 'block'; lgView.classList.add('active'); }
    const backBtn = document.getElementById('btn-settings-back');
    if (backBtn) backBtn.style.display = 'block';
    const title = document.getElementById('settings-title');
    const sub = document.getElementById('settings-subtitle');
    if (title) title.innerHTML = '<i data-lucide="wifi" style="width: 24px; height: 24px; vertical-align: middle; margin-right: 12px;"></i>LG ThinQ Service';
    if (sub) sub.textContent = 'Koneksi perangkat LG ThinQ';
    lucide.createIcons();
    checkLgStatus();
}

async function showSettingsAbout() {
    document.querySelectorAll('.settings-subview').forEach(v => { v.style.display = 'none'; v.classList.remove('active'); });
    const aboutView = document.getElementById('settings-about');
    if (aboutView) { aboutView.style.display = 'block'; aboutView.classList.add('active'); }
    const backBtn = document.getElementById('btn-settings-back');
    if (backBtn) backBtn.style.display = 'block';
    const title = document.getElementById('settings-title');
    const sub = document.getElementById('settings-subtitle');
    if (title) title.innerHTML = '<i data-lucide="info" style="width: 24px; height: 24px; vertical-align: middle; margin-right: 12px;"></i>Tentang Sistem';
    if (sub) sub.textContent = 'Informasi konfigurasi server';
    lucide.createIcons();
    try {
        const response = await fetch('/api/system');
        const data = await response.json();
        document.getElementById('sys-dashboard-port').textContent = data.dashboard_port;
        document.getElementById('sys-api-port').textContent = data.api_port;
        document.getElementById('sys-local-ip').textContent = data.local_ip;
        const urlEl = document.getElementById('sys-local-url');
        urlEl.textContent = data.local_url; urlEl.href = data.local_url;
        document.getElementById('sys-hostname').textContent = data.hostname;
        document.getElementById('sys-host').textContent = data.host;
        document.getElementById('sys-db-path').textContent = data.db_path;
        const deviceList = document.getElementById('sys-device-list');
        let html = '';
        if (data.devices && data.devices.length > 0) {
            html += '<strong>LG ThinQ:</strong><ul>' + data.devices.map(d => `<li>${d.replace(/_/g, ' ')}</li>`).join('') + '</ul>';
        }
        if (data.dryers && data.dryers.length > 0) {
            html += '<strong>Manual Dryers:</strong><ul>' + data.dryers.map(d => `<li>${d.replace(/_/g, ' ')}</li>`).join('') + '</ul>';
        }
        if (!html) html = '<li>Belum ada mesin terdeteksi</li>';
        deviceList.innerHTML = html;
    } catch (error) { console.error('Error fetching system info:', error); }
}

async function showSettingsConfig() {
    document.querySelectorAll('.settings-subview').forEach(v => { v.style.display = 'none'; v.classList.remove('active'); });
    const configView = document.getElementById('settings-config');
    if (configView) { configView.style.display = 'block'; configView.classList.add('active'); }
    const backBtn = document.getElementById('btn-settings-back');
    if (backBtn) backBtn.style.display = 'block';
    const title = document.getElementById('settings-title');
    const sub = document.getElementById('settings-subtitle');
    if (title) title.innerHTML = '<i data-lucide="settings" style="width: 24px; height: 24px; vertical-align: middle; margin-right: 12px;"></i>Konfigurasi Sistem';
    if (sub) sub.textContent = 'Pengaturan polling, timeout, dan trigger';

    try {
        const response = await fetch('/api/config');
        const config = await response.json();

        document.getElementById('cfg-monitoring-interval').value = config.monitoring_interval;
        document.getElementById('cfg-request-timeout').value = config.request_timeout;
        document.getElementById('cfg-worker-threads').value = config.worker_threads;
        document.getElementById('cfg-sse-timeout').value = config.sse_keep_alive_timeout;

        // LG Triggers
        const lgContainer = document.getElementById('cfg-triggers-container');
        lgContainer.innerHTML = '<h4>LG ThinQ Machines</h4>';
        const attrSelect = document.getElementById('attr-machine-select');
        attrSelect.innerHTML = '<option value="">-- Pilih Mesin --</option>';
        for (const [name, url] of Object.entries(config.machine_triggers || {})) {
            lgContainer.innerHTML += `<div class="input-field" style="margin-bottom: 15px;"><label>${name.replace(/_/g, ' ')}</label><input type="text" value="${url}" data-machine="${name}" class="cfg-trigger-input lg-trigger"></div>`;
            attrSelect.innerHTML += `<option value="${name}">${name.replace(/_/g, ' ')}</option>`;
        }

        // Manual Dryers
        const dryerContainer = document.getElementById('cfg-dryers-list');
        dryerContainer.innerHTML = '';
        if (config.dryer_triggers && Object.keys(config.dryer_triggers).length > 0) {
            for (const [name, url] of Object.entries(config.dryer_triggers)) {
                dryerContainer.innerHTML += `
                    <div class="input-field" style="margin-bottom: 15px; display: flex; align-items: flex-end; gap: 10px;">
                        <div style="flex: 1;">
                            <label>${name.replace(/_/g, ' ')}</label>
                            <input type="text" value="${url}" data-machine="${name}" class="cfg-trigger-input dryer-trigger">
                        </div>
                        <button class="btn-secondary" onclick="this.parentElement.remove()" style="background: var(--color-danger); border: none; width: 35px; height: 45px; margin-bottom: 0;">
                            <i data-lucide="trash-2"></i>
                        </button>
                    </div>`;
            }
        }
        lucide.createIcons();
    } catch (error) { console.error('Error fetching config:', error); }
}

async function saveConfigSettings() {
    const statusEl = document.getElementById('cfg-save-status');
    if (statusEl) { statusEl.textContent = 'Menyimpan...'; statusEl.style.color = '#f59e0b'; }
    const triggers = {};
    const dryerTriggers = {};
    document.querySelectorAll('.cfg-trigger-input.lg-trigger').forEach(input => {
        const machineID = input.getAttribute('data-machine');
        if (machineID) triggers[machineID] = input.value.trim();
    });

    // Collect existing manual dryers (including those just removed from list but still in DOM before save)
    document.querySelectorAll('.cfg-trigger-input.dryer-trigger').forEach(input => {
        const machineID = input.getAttribute('data-machine');
        if (machineID) dryerTriggers[machineID] = input.value.trim();
    });
    const payload = {
        monitoring_interval: parseInt(document.getElementById('cfg-monitoring-interval').value),
        request_timeout: parseInt(document.getElementById('cfg-request-timeout').value),
        worker_threads: parseInt(document.getElementById('cfg-worker-threads').value),
        sse_keep_alive_timeout: parseInt(document.getElementById('cfg-sse-timeout').value),
        machine_triggers: triggers,
        dryer_triggers: dryerTriggers
    };
    try {
        const response = await fetch('/api/config', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload) });
        if (response.ok) { statusEl.innerHTML = '✅ Berhasil disimpan!'; statusEl.style.color = '#10b981'; }
        else { statusEl.textContent = '❌ Gagal menyimpan'; statusEl.style.color = '#ef4444'; }
    } catch (error) { statusEl.textContent = '❌ Error: ' + error.message; }
    setTimeout(() => { if (statusEl) statusEl.textContent = ''; }, 5000);
}

async function checkLgStatus() {
    try {
        const response = await fetch('/api/lg/status');
        const data = await response.json();
        const badge = document.getElementById('lg-status-badge');
        const menuStatus = document.getElementById('menu-lg-status');
        const connState = document.getElementById('lg-state-connected');
        const disconnState = document.getElementById('lg-state-disconnected');
        if (data.connected) {
            if (badge) { badge.textContent = 'Connected'; badge.className = 'status-badge status-on'; }
            if (menuStatus) { menuStatus.textContent = 'Connected'; menuStatus.style.color = '#10b981'; }
            if (connState) connState.style.display = 'block';
            if (disconnState) disconnState.style.display = 'none';
        } else {
            if (badge) { badge.textContent = 'Disconnected'; badge.className = 'status-badge status-off'; }
            if (menuStatus) { menuStatus.textContent = 'Disconnected'; menuStatus.style.color = '#ef4444'; }
            if (connState) connState.style.display = 'none';
            if (disconnState) disconnState.style.display = 'block';
        }
    } catch (error) { console.error('Error checking LG status:', error); }
}

async function initMachineLogs() {
    try {
        const response = await fetch('/api/system');
        const data = await response.json();
        const select = document.getElementById('ml-filter-machine');
        if (select) {
            select.innerHTML = '<option value="all">Semua Mesin</option>';
            (data.devices || []).forEach(d => select.innerHTML += `<option value="${d}">${d.replace(/_/g, ' ')}</option>`);
            (data.dryers || []).forEach(d => select.innerHTML += `<option value="${d}">${d.replace(/_/g, ' ')}</option>`);
        }
    } catch (e) { }
    loadMachineLogStats();
    loadMachineLogs();
}

async function loadMachineLogStats() {
    const mach = document.getElementById('ml-filter-machine').value;
    const date = document.getElementById('ml-filter-date').value;
    let url = `/api/machine-logs/stats?machine=${mach}&date=${date}`;
    try {
        const res = await fetch(url);
        const stats = await res.json();
        document.getElementById('ml-stat-today').textContent = stats.today || 0;
        document.getElementById('ml-stat-week').textContent = stats.week || 0;
        document.getElementById('ml-stat-month').textContent = stats.month || 0;
    } catch (e) { }
}

async function loadMachineLogs() {
    const mach = document.getElementById('ml-filter-machine').value;
    const date = document.getElementById('ml-filter-date').value;
    let url = `/api/machine-logs?limit=200&machine=${mach}&date=${date}`;
    try {
        const res = await fetch(url);
        const logs = await res.json();
        const tbody = document.getElementById('ml-table-body');
        if (!tbody) return;
        if (logs.length === 0) { tbody.innerHTML = '<tr><td colspan="2" style="text-align: center;">Tidak ada data</td></tr>'; return; }
        tbody.innerHTML = logs.map(l => `<tr><td>${l.machine.replace(/_/g, ' ')}</td><td>${l.completed_at}</td></tr>`).join('');
    } catch (e) { }
}

function handleMachineLogEvent(data) {
    loadMachineLogStats();
    loadMachineLogs();
}

async function printMachineAttributes() {
    const name = document.getElementById('attr-machine-select').value;
    if (!name) return;
    const out = document.getElementById('attr-output');
    if (out) out.textContent = 'Loading...';
    try {
        const res = await fetch(`/api/machine/attributes/${name}`);
        const data = await res.json();
        if (out) out.textContent = JSON.stringify(data, null, 4);
    } catch (e) { if (out) out.textContent = 'Error: ' + e.message; }
}

function addNewDryerFromForm() {
    const nameInput = document.getElementById('new-dryer-name');
    const urlInput = document.getElementById('new-dryer-url');
    const name = nameInput.value.trim().replace(/\s+/g, '_');
    const url = urlInput.value.trim();

    if (!name) { alert('Nama pengering tidak boleh kosong'); return; }

    const container = document.getElementById('cfg-dryers-list');
    const rowHTML = `
        <div class="input-field" style="margin-bottom: 15px; display: flex; align-items: flex-end; gap: 10px;">
            <div style="flex: 1;">
                <label>${name.replace(/_/g, ' ')}</label>
                <input type="text" value="${url}" data-machine="${name}" class="cfg-trigger-input dryer-trigger">
            </div>
            <button class="btn-secondary" onclick="this.parentElement.remove()" style="background: var(--color-danger); border: none; width: 35px; height: 45px; margin-bottom: 0;">
                <i data-lucide="trash-2"></i>
            </button>
        </div>`;

    container.insertAdjacentHTML('beforeend', rowHTML);
    lucide.createIcons();

    // Clear form
    nameInput.value = '';
    urlInput.value = '';
}

lucide.createIcons();

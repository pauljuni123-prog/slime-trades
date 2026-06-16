const API_URL = 'http://localhost:8000';
let token = localStorage.getItem('token') || '';
let user = JSON.parse(localStorage.getItem('user') || 'null');

function showTab(tab) {
    document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));
    document.querySelectorAll('.auth-form').forEach(f => f.classList.remove('active'));
    if (tab === 'login') {
        document.querySelectorAll('.tab-btn')[0].classList.add('active');
        document.getElementById('login-form').classList.add('active');
    } else {
        document.querySelectorAll('.tab-btn')[1].classList.add('active');
        document.getElementById('register-form').classList.add('active');
    }
}

function showPage(page) {
    document.querySelectorAll('.nav-links li').forEach(l => l.classList.remove('active'));
    document.querySelectorAll('.page').forEach(p => p.classList.remove('active'));
    const pages = ['dashboard','mind-scan','ai-coach','guardian','mt5'];
    const idx = pages.indexOf(page);
    if (idx >= 0) {
        document.querySelectorAll('.nav-links li')[idx].classList.add('active');
        document.getElementById('page-' + page).classList.add('active');
    }
    if (page === 'mt5') loadMT5Accounts();
}

function checkAuth() {
    if (token) {
        document.getElementById('auth-screen').classList.remove('active');
        document.getElementById('dashboard-screen').classList.add('active');
        if (user) document.getElementById('user-name').textContent = user.display_name || user.email;
        loadDashboard();
    }
}

document.getElementById('login-form').addEventListener('submit', async (e) => {
    e.preventDefault();
    const email = document.getElementById('login-email').value;
    const password = document.getElementById('login-password').value;
    try {
        const res = await fetch(`${API_URL}/auth/login`, {
            method: 'POST',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify({email, password})
        });
        const data = await res.json();
        if (res.ok) {
            token = data.access_token;
            localStorage.setItem('token', token);
            user = {email};
            localStorage.setItem('user', JSON.stringify(user));
            document.getElementById('auth-screen').classList.remove('active');
            document.getElementById('dashboard-screen').classList.add('active');
            document.getElementById('user-name').textContent = email;
            loadDashboard();
        } else {
            document.getElementById('login-error').textContent = data.detail || 'Login failed';
        }
    } catch (err) {
        document.getElementById('login-error').textContent = 'Server error';
    }
});

document.getElementById('register-form').addEventListener('submit', async (e) => {
    e.preventDefault();
    const email = document.getElementById('reg-email').value;
    const password = document.getElementById('reg-password').value;
    const display_name = document.getElementById('reg-name').value;
    try {
        const res = await fetch(`${API_URL}/auth/register`, {
            method: 'POST',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify({email, password, display_name})
        });
        const data = await res.json();
        if (res.ok) {
            document.getElementById('reg-error').textContent = 'Account created! Please login.';
            document.getElementById('reg-error').style.color = '#10b981';
            showTab('login');
        } else {
            document.getElementById('reg-error').textContent = data.detail || 'Registration failed';
            document.getElementById('reg-error').style.color = '#ef4444';
        }
    } catch (err) {
        document.getElementById('reg-error').textContent = 'Server error';
        document.getElementById('reg-error').style.color = '#ef4444';
    }
});

function logout() {
    token = '';
    user = null;
    localStorage.removeItem('token');
    localStorage.removeItem('user');
    localStorage.removeItem('ai_session');
    document.getElementById('dashboard-screen').classList.remove('active');
    document.getElementById('auth-screen').classList.add('active');
}

async function api(endpoint, options = {}) {
    const headers = {
        'Content-Type': 'application/json',
        ...(token && {'Authorization': `Bearer ${token}`})
    };
    const res = await fetch(`${API_URL}${endpoint}`, {...options, headers});
    if (!res.ok) {
        const err = await res.json().catch(() => ({detail: 'Unknown error'}));
        throw new Error(err.detail || 'Request failed');
    }
    return res.json();
}

async function loadDashboard() {
    try {
        const scans = await api('/mind-scans/');
        if (scans.length > 0) {
            const latest = scans[0];
            document.getElementById('readiness').textContent = latest.readiness_score;
            document.getElementById('readiness').style.color = 
                latest.readiness_score >= 70 ? '#10b981' : 
                latest.readiness_score >= 40 ? '#f59e0b' : '#ef4444';
        } else {
            document.getElementById('readiness').textContent = 'N/A';
        }
    } catch (e) {
        document.getElementById('readiness').textContent = '--';
    }
}

['stress','focus','confidence','sleep'].forEach(id => {
    document.getElementById(id).addEventListener('input', (e) => {
        document.getElementById(id + '-val').textContent = e.target.value;
    });
});

async function submitMindScan() {
    const stress = parseInt(document.getElementById('stress').value);
    const focus = parseInt(document.getElementById('focus').value);
    const confidence = parseInt(document.getElementById('confidence').value);
    const sleep = parseInt(document.getElementById('sleep').value);
    try {
        const data = await api('/mind-scans/', {
            method: 'POST',
            body: JSON.stringify({stress, focus, confidence, sleep})
        });
        document.getElementById('scan-result').classList.remove('hidden');
        document.getElementById('score').textContent = data.readiness_score;
        document.getElementById('label').textContent = data.label;
        document.getElementById('advice').textContent = data.advice;
        const scoreEl = document.getElementById('score');
        scoreEl.style.color = data.readiness_score >= 70 ? '#10b981' : 
                             data.readiness_score >= 40 ? '#f59e0b' : '#ef4444';
        loadDashboard();
    } catch (err) {
        alert('Error: ' + err.message);
    }
}

async function sendMessage() {
    const input = document.getElementById('chat-message');
    const content = input.value.trim();
    if (!content) return;
    const messagesDiv = document.getElementById('chat-messages');
    messagesDiv.innerHTML += `<div class="message user"><p>${content}</p></div>`;
    input.value = '';
    messagesDiv.scrollTop = messagesDiv.scrollHeight;
    try {
        let sessionId = localStorage.getItem('ai_session');
        if (!sessionId) {
            const session = await api('/ai/sessions', {
                method: 'POST',
                body: JSON.stringify({personality: 'balanced', title: 'Trading Chat'})
            });
            sessionId = session.id;
            localStorage.setItem('ai_session', sessionId);
        }
        const response = await api('/ai/messages', {
            method: 'POST',
            body: JSON.stringify({conversation_id: sessionId, content})
        });
        messagesDiv.innerHTML += `<div class="message ai"><p>${response.content}</p></div>`;
        messagesDiv.scrollTop = messagesDiv.scrollHeight;
    } catch (err) {
        messagesDiv.innerHTML += `<div class="message ai"><p>Error: ${err.message}</p></div>`;
    }
}

async function calcPositionSize() {
    const balance = parseFloat(document.getElementById('ps-balance').value);
    const risk_percent = parseFloat(document.getElementById('ps-risk').value);
    const stop_loss_pips = parseFloat(document.getElementById('ps-sl').value);
    const pair = document.getElementById('ps-pair').value;
    if (!balance || !risk_percent || !stop_loss_pips) {
        alert('Please fill in Balance, Risk %, and Stop Loss');
        return;
    }
    try {
        const data = await api('/guardian/position-size', {
            method: 'POST',
            body: JSON.stringify({balance, risk_percent, stop_loss_pips, pair})
        });
        const result = document.getElementById('ps-result');
        result.classList.remove('hidden');
        result.innerHTML = `
            <p><strong>Risk Amount:</strong> $${data.risk_amount.toFixed(2)}</p>
            <p><strong>Lot Size:</strong> ${data.lot_size.toFixed(2)}</p>
            <p><strong>Units:</strong> ${data.units.toLocaleString()}</p>
        `;
    } catch (err) {
        alert('Error: ' + err.message);
    }
}

async function calcRiskOfRuin() {
    const balance = parseFloat(document.getElementById('rr-balance').value);
    const risk_percent = parseFloat(document.getElementById('rr-risk').value);
    const win_rate = parseFloat(document.getElementById('rr-winrate').value);
    const reward_risk_ratio = parseFloat(document.getElementById('rr-rr').value);
    if (!balance || !risk_percent || !win_rate || !reward_risk_ratio) {
        alert('Please fill in ALL fields: Balance, Risk %, Win Rate, and Reward:Risk Ratio');
        return;
    }
    try {
        const data = await api('/guardian/risk-of-ruin', {
            method: 'POST',
            body: JSON.stringify({balance, risk_percent, win_rate, reward_risk_ratio})
        });
        const result = document.getElementById('rr-result');
        result.classList.remove('hidden');
        const color = data.risk_label === 'Safe' ? '#10b981' : data.risk_label === 'Moderate' ? '#f59e0b' : '#ef4444';
        result.innerHTML = `
            <p><strong>Risk Label:</strong> <span style="color:${color}">${data.risk_label}</span></p>
            <p><strong>Ruin Probability:</strong> ${data.ruin_probability}%</p>
            <p><strong>Max Drawdown:</strong> $${data.max_drawdown.toFixed(2)}</p>
            <p><strong>Expected Value/Trade:</strong> $${data.expected_value_per_trade.toFixed(2)}</p>
        `;
    } catch (err) {
        alert('Error: ' + err.message);
    }
}

async function connectMT5() {
    const broker = document.getElementById('mt5-broker').value;
    const server = document.getElementById('mt5-server').value;
    const account_number = document.getElementById('mt5-account').value;
    const password = document.getElementById('mt5-password').value;
    if (!broker || !server || !account_number || !password) {
        alert('Please fill in all MT5 fields');
        return;
    }
    try {
        const data = await api('/mt5/accounts', {
            method: 'POST',
            body: JSON.stringify({broker, server, account_number, password})
        });
        alert('Account added! Now connecting to MT5...');
        
        // Try live connection
        try {
            const live = await api('/mt5/connect-live', {
                method: 'POST',
                body: JSON.stringify({account_id: data.id, password})
            });
            alert('Connected to MT5! Balance: $' + live.account_info.balance);
        } catch (liveErr) {
            alert('Account saved but live connection failed: ' + liveErr.message);
        }
        
        loadMT5Accounts();
    } catch (err) {
        alert('Error: ' + err.message);
    }
}

async function loadMT5Accounts() {
    try {
        const accounts = await api('/mt5/accounts');
        const container = document.getElementById('mt5-accounts');
        if (accounts.length === 0) {
            container.innerHTML = '<p style="color:#6b7280">No accounts linked yet</p>';
            return;
        }
        container.innerHTML = accounts.map(acc => `
            <div class="account-item">
                <h4>${acc.broker}</h4>
                <p>Server: ${acc.server}</p>
                <p>Account: ${acc.account_number}</p>
                <p><span class="status-dot ${acc.is_connected ? 'connected' : 'disconnected'}"></span>
                ${acc.is_connected ? 'Connected' : 'Disconnected'}</p>
                ${acc.is_connected ? `<p style="color:#10b981">Last sync: ${new Date(acc.last_sync).toLocaleString()}</p>` : ''}
            </div>
        `).join('');
    } catch (e) {
        document.getElementById('mt5-accounts').innerHTML = '<p style="color:#6b7280">No accounts linked</p>';
    }
}

checkAuth();

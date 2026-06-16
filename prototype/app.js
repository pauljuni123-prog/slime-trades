// ========================================
// SLIME TRADES — PROTOTYPE JAVASCRIPT
// Working calculators + interactive features
// ========================================

// ===== LIVE CLOCK =====
function updateClock() {
    const now = new Date();
    const timeStr = now.toISOString().split('T')[1].split('.')[0] + ' UTC';
    const el = document.querySelector('.dashboard-time');
    if (el) el.textContent = timeStr;
}
setInterval(updateClock, 1000);
updateClock();

// ===== MIND SCAN SLIDERS =====
const sliders = ['stress', 'focus', 'confidence', 'sleep'];
sliders.forEach(id => {
    const slider = document.getElementById(id + 'Slider');
    const value = document.getElementById(id + 'Value');
    if (slider && value) {
        slider.addEventListener('input', () => {
            value.textContent = slider.value + '%';
            // Color code the value
            const val = parseInt(slider.value);
            if (id === 'stress') {
                value.style.color = val > 60 ? '#FF4757' : val > 30 ? '#FFA502' : '#00FF88';
            } else {
                value.style.color = val > 70 ? '#00FF88' : val > 40 ? '#FFA502' : '#FF4757';
            }
        });
    }
});

// ===== MIND SCAN ANALYSIS =====
document.getElementById('scanBtn').addEventListener('click', function() {
    const stress = parseInt(document.getElementById('stressSlider').value);
    const focus = parseInt(document.getElementById('focusSlider').value);
    const confidence = parseInt(document.getElementById('confidenceSlider').value);
    const sleep = parseInt(document.getElementById('sleepSlider').value);

    // Calculate readiness score (0-100)
    // Lower stress is better, higher focus/confidence/sleep is better
    const readiness = Math.round(
        ((100 - stress) * 0.35) + 
        (focus * 0.30) + 
        (confidence * 0.20) + 
        (sleep * 0.15)
    );

    let label, advice, color;
    if (readiness >= 80) {
        label = 'Excellent';
        advice = 'You are in peak mental condition. This is an ideal time to trade with confidence. Stick to your plan and maintain discipline.';
        color = '#00FF88';
    } else if (readiness >= 60) {
        label = 'Good to Trade';
        advice = 'Your mental state is solid. You can trade, but stay mindful of your emotions. Consider smaller position sizes today.';
        color = '#00FF88';
    } else if (readiness >= 40) {
        label = 'Caution Advised';
        advice = 'Your readiness is moderate. Consider paper trading or taking a break. Review your trading plan before entering any positions.';
        color = '#FFA502';
    } else {
        label = 'Do Not Trade';
        advice = 'Your emotional state suggests high risk of poor decisions. Step away from the charts. Go for a walk, rest, and come back tomorrow.';
        color = '#FF4757';
    }

    const resultHTML = `
        <div class="result-score" style="color: ${color}">${readiness}</div>
        <div class="result-label" style="color: ${color}">${label}</div>
        <p class="result-advice">${advice}</p>
        <div class="result-breakdown">
            <div class="breakdown-item">
                <span>Stress Management</span>
                <div style="display:flex;align-items:center;gap:12px">
                    <div class="breakdown-bar"><div class="breakdown-fill" style="width:${100-stress}%;background:${100-stress > 60 ? '#00FF88' : '#FFA502'}"></div></div>
                    <span style="font-family:'JetBrains Mono',monospace;font-size:13px">${100-stress}</span>
                </div>
            </div>
            <div class="breakdown-item">
                <span>Focus Level</span>
                <div style="display:flex;align-items:center;gap:12px">
                    <div class="breakdown-bar"><div class="breakdown-fill" style="width:${focus}%;background:${focus > 60 ? '#00FF88' : '#FFA502'}"></div></div>
                    <span style="font-family:'JetBrains Mono',monospace;font-size:13px">${focus}</span>
                </div>
            </div>
            <div class="breakdown-item">
                <span>Confidence</span>
                <div style="display:flex;align-items:center;gap:12px">
                    <div class="breakdown-bar"><div class="breakdown-fill" style="width:${confidence}%;background:${confidence > 60 ? '#00FF88' : '#FFA502'}"></div></div>
                    <span style="font-family:'JetBrains Mono',monospace;font-size:13px">${confidence}</span>
                </div>
            </div>
            <div class="breakdown-item">
                <span>Sleep Quality</span>
                <div style="display:flex;align-items:center;gap:12px">
                    <div class="breakdown-bar"><div class="breakdown-fill" style="width:${sleep}%;background:${sleep > 60 ? '#00FF88' : '#FFA502'}"></div></div>
                    <span style="font-family:'JetBrains Mono',monospace;font-size:13px">${sleep}</span>
                </div>
            </div>
        </div>
    `;

    document.getElementById('scanResult').innerHTML = resultHTML;

    // Animate the score
    const scoreEl = document.querySelector('.result-score');
    if (scoreEl) {
        scoreEl.style.transform = 'scale(0)';
        setTimeout(() => {
            scoreEl.style.transition = 'transform 0.5s cubic-bezier(0.34, 1.56, 0.64, 1)';
            scoreEl.style.transform = 'scale(1)';
        }, 50);
    }
});

// ===== POSITION SIZE CALCULATOR =====
function calculatePositionSize() {
    const balance = parseFloat(document.getElementById('psBalance').value) || 0;
    const riskPercent = parseFloat(document.getElementById('psRisk').value) || 0;
    const stopLoss = parseFloat(document.getElementById('psStopLoss').value) || 1;
    const pipValue = parseFloat(document.getElementById('psPair').value) || 0.0001;

    const riskAmount = balance * (riskPercent / 100);
    const stopLossValue = stopLoss * pipValue;
    const units = riskAmount / stopLossValue;
    const lotSize = units / 100000;

    document.getElementById('psRiskAmount').textContent = '$' + riskAmount.toFixed(2);
    document.getElementById('psLotSize').textContent = lotSize.toFixed(2) + ' lots';
    document.getElementById('psUnits').textContent = Math.round(units).toLocaleString();
}

['psBalance', 'psRisk', 'psStopLoss', 'psPair'].forEach(id => {
    const el = document.getElementById(id);
    if (el) el.addEventListener('input', calculatePositionSize);
});
calculatePositionSize();

// ===== RISK OF RUIN CALCULATOR =====
function calculateRiskOfRuin() {
    const balance = parseFloat(document.getElementById('rorBalance').value) || 1;
    const riskPercent = parseFloat(document.getElementById('rorRisk').value) || 1;
    const winRate = parseFloat(document.getElementById('rorWinRate').value) || 50;
    const rr = parseFloat(document.getElementById('rorRR').value) || 1;

    // Risk of Ruin formula (simplified)
    // Using the formula: ROR = ((1 - Edge) / (1 + Edge)) ^ (Bankroll / RiskUnit)
    // where Edge = (WinRate * RR) - (1 - WinRate)
    const winRateDecimal = winRate / 100;
    const edge = (winRateDecimal * rr) - (1 - winRateDecimal);

    let ror;
    if (edge <= 0) {
        ror = 100;
    } else {
        const riskUnit = balance * (riskPercent / 100);
        const bankrollUnits = balance / riskUnit;
        const q = (1 - edge) / (1 + edge);
        ror = Math.pow(q, bankrollUnits) * 100;
    }

    // Expected value per trade
    const ev = (winRateDecimal * rr * riskPercent) - ((1 - winRateDecimal) * riskPercent);

    // Max drawdown estimate (simplified)
    const maxDrawdown = balance * (riskPercent / 100) * 10 * (1 - winRateDecimal);

    // Clamp ROR
    ror = Math.min(100, Math.max(0, ror));

    document.getElementById('rorProbability').textContent = ror.toFixed(1) + '%';
    document.getElementById('rorDrawdown').textContent = '$' + maxDrawdown.toFixed(0);
    document.getElementById('rorExpected').textContent = (ev >= 0 ? '+' : '') + '$' + ev.toFixed(2) + '/trade';

    // Update visual bar
    document.getElementById('riskFill').style.width = ror + '%';

    // Update label
    let riskLabel = 'Safe';
    if (ror > 15) riskLabel = 'Moderate';
    if (ror > 35) riskLabel = 'High Risk';
    if (ror > 60) riskLabel = 'Danger';
    document.getElementById('riskLabel').textContent = riskLabel;
    document.getElementById('riskLabel').style.color = ror > 35 ? '#FF4757' : ror > 15 ? '#FFA502' : '#00FF88';
}

['rorBalance', 'rorRisk', 'rorWinRate', 'rorRR'].forEach(id => {
    const el = document.getElementById(id);
    if (el) el.addEventListener('input', calculateRiskOfRuin);
});
calculateRiskOfRuin();

// ===== AI CHAT =====
document.getElementById('sendBtn').addEventListener('click', sendMessage);
document.getElementById('chatInput').addEventListener('keypress', (e) => {
    if (e.key === 'Enter') sendMessage();
});

function sendMessage() {
    const input = document.getElementById('chatInput');
    const text = input.value.trim();
    if (!text) return;

    const messages = document.getElementById('chatMessages');
    const time = new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });

    // Add user message
    const userMsg = document.createElement('div');
    userMsg.className = 'message user-message';
    userMsg.innerHTML = `
        <div class="message-bubble">
            <p>${escapeHtml(text)}</p>
            <span class="message-time">${time}</span>
        </div>
        <div class="message-avatar">👤</div>
    `;
    messages.appendChild(userMsg);
    input.value = '';
    messages.scrollTop = messages.scrollHeight;

    // Simulate AI response
    setTimeout(() => {
        const response = generateAIResponse(text);
        const aiMsg = document.createElement('div');
        aiMsg.className = 'message ai-message';
        aiMsg.innerHTML = `
            <div class="message-avatar">🧪</div>
            <div class="message-bubble">
                <p>${response}</p>
                <span class="message-time">${new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}</span>
            </div>
        `;
        messages.appendChild(aiMsg);
        messages.scrollTop = messages.scrollHeight;
    }, 800 + Math.random() * 1000);
}

function generateAIResponse(text) {
    const lower = text.toLowerCase();

    if (lower.includes('loss') || lower.includes('lost') || lower.includes('losing')) {
        return "I understand losses are tough. Remember: <strong>one trade does not define you</strong>. Let's review your risk per trade — are you keeping it under 1-2%? Also, check your Mind Scan score before your next session.";
    }
    if (lower.includes('fear') || lower.includes('scared') || lower.includes('nervous')) {
        return "Fear is a natural response — it means you respect the market. But if fear is paralyzing you, your position sizes might be too large. Try reducing your risk to 0.5% per trade until confidence returns.";
    }
    if (lower.includes('greed') || lower.includes('fomo') || lower.includes('miss')) {
        return "FOMO is one of the biggest account killers. The market will always be there tomorrow. Set alerts at your entry zones and walk away. <strong>Missing a trade is better than taking a bad one.</strong>";
    }
    if (lower.includes('plan') || lower.includes('strategy')) {
        return "A solid trading plan is your foundation. Make sure it includes: entry criteria, exit criteria, risk per trade, max daily loss, and when to stop trading. Want me to help you build one?";
    }
    if (lower.includes('journal') || lower.includes('review')) {
        return "Journaling is one of the highest-ROI habits for traders. Track: setup, emotion before entry, outcome, and lesson. I can analyze your journal patterns to spot recurring mistakes.";
    }
    if (lower.includes('help') || lower.includes('how')) {
        return "I'm here to help! I can assist with trading psychology, risk management, strategy review, journal analysis, or emotional readiness. What would you like to focus on today?";
    }

    return "That's a great question. Based on your trading profile, I'd recommend focusing on <strong>process over outcomes</strong>. Every trader has ups and downs — what separates pros from amateurs is how they respond. Want to dive deeper into this?";
}

function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
}

// ===== GUARDIAN TOGGLES =====
document.querySelectorAll('.toggle-switch').forEach(toggle => {
    toggle.addEventListener('click', function() {
        this.classList.toggle('active');
        const card = this.closest('.guardian-card');
        const label = this.nextElementSibling;

        if (this.classList.contains('active')) {
            card.classList.add('active');
            label.textContent = 'Active';
        } else {
            card.classList.remove('active');
            label.textContent = 'Off';
        }
    });
});

// ===== SMOOTH SCROLL FOR NAV LINKS =====
document.querySelectorAll('a[href^="#"]').forEach(anchor => {
    anchor.addEventListener('click', function(e) {
        e.preventDefault();
        const target = document.querySelector(this.getAttribute('href'));
        if (target) {
            target.scrollIntoView({ behavior: 'smooth', block: 'start' });
        }
    });
});

// ===== NAVBAR SCROLL EFFECT =====
let lastScroll = 0;
window.addEventListener('scroll', () => {
    const navbar = document.querySelector('.navbar');
    const currentScroll = window.pageYOffset;

    if (currentScroll > 50) {
        navbar.style.background = 'rgba(10, 10, 10, 0.95)';
        navbar.style.boxShadow = '0 4px 24px rgba(0,0,0,0.3)';
    } else {
        navbar.style.background = 'rgba(10, 10, 10, 0.8)';
        navbar.style.boxShadow = 'none';
    }

    lastScroll = currentScroll;
});

// ===== ANIMATE ON SCROLL =====
const observerOptions = {
    threshold: 0.1,
    rootMargin: '0px 0px -50px 0px'
};

const observer = new IntersectionObserver((entries) => {
    entries.forEach(entry => {
        if (entry.isIntersecting) {
            entry.target.style.opacity = '1';
            entry.target.style.transform = 'translateY(0)';
        }
    });
}, observerOptions);

document.querySelectorAll('.section-header, .dash-widget, .guardian-card, .pricing-card, .tool-card').forEach(el => {
    el.style.opacity = '0';
    el.style.transform = 'translateY(30px)';
    el.style.transition = 'opacity 0.6s ease, transform 0.6s ease';
    observer.observe(el);
});

console.log('🧪 Slime Trades prototype loaded successfully!');


// ===== JOURNAL FUNCTIONALITY =====
// Direction toggle
let selectedDir = 'LONG';
document.querySelectorAll('.dir-btn').forEach(btn => {
    btn.addEventListener('click', () => {
        document.querySelectorAll('.dir-btn').forEach(b => b.classList.remove('active'));
        btn.classList.add('active');
        selectedDir = btn.dataset.dir;
    });
});

// Outcome toggle
let selectedOutcome = 'WIN';
document.querySelectorAll('.out-btn').forEach(btn => {
    btn.addEventListener('click', () => {
        document.querySelectorAll('.out-btn').forEach(b => b.classList.remove('active'));
        btn.classList.add('active');
        selectedOutcome = btn.dataset.out;
    });
});

// Emotion tags
let selectedEmotion = '';
document.querySelectorAll('.emotion-tag').forEach(tag => {
    tag.addEventListener('click', () => {
        document.querySelectorAll('.emotion-tag').forEach(t => t.classList.remove('active'));
        tag.classList.add('active');
        selectedEmotion = tag.dataset.emotion;
    });
});

// Set today's date
document.getElementById('jDate').valueAsDate = new Date();

// Add journal entry
document.getElementById('addJournalBtn').addEventListener('click', () => {
    const pair = document.getElementById('jPair').value;
    const pnl = parseFloat(document.getElementById('jPnl').value) || 0;
    const notes = document.getElementById('jNotes').value;
    const date = new Date().toLocaleDateString('en-US', { month: 'short', day: 'numeric' });

    if (!pnl && pnl !== 0) {
        alert('Please enter a P&L value');
        return;
    }

    const emotion = selectedEmotion || 'Calm';
    const pnlClass = pnl >= 0 ? 'positive' : 'negative';
    const pnlSign = pnl >= 0 ? '+' : '';

    const entryHTML = `
        <div class="journal-entry" style="animation: fadeIn 0.4s ease">
            <div class="entry-main">
                <div class="entry-pair">${pair}</div>
                <div class="entry-meta">
                    <span class="entry-dir ${selectedDir.toLowerCase()}">${selectedDir}</span>
                    <span class="entry-date">${date}</span>
                </div>
            </div>
            <div class="entry-pnl ${pnlClass}">${pnlSign}$${Math.abs(pnl).toFixed(2)}</div>
            <div class="entry-emotion">${emotion}</div>
        </div>
    `;

    const entriesContainer = document.getElementById('journalEntries');
    entriesContainer.insertAdjacentHTML('afterbegin', entryHTML);

    // Clear form
    document.getElementById('jPnl').value = '';
    document.getElementById('jNotes').value = '';
    document.getElementById('jEntry').value = '';
    document.getElementById('jExit').value = '';

    // Update stats
    updateJournalStats();
});

function updateJournalStats() {
    const entries = document.querySelectorAll('.journal-entry');
    let wins = 0, losses = 0;
    entries.forEach(e => {
        const pnl = e.querySelector('.entry-pnl');
        if (pnl.classList.contains('positive')) wins++;
        else losses++;
    });
    const total = wins + losses;
    const wr = total > 0 ? Math.round((wins / total) * 100) : 0;

    const statsContainer = document.querySelector('.journal-stats');
    if (statsContainer) {
        statsContainer.innerHTML = `
            <span class="j-stat win">${wins} Wins</span>
            <span class="j-stat loss">${losses} Losses</span>
            <span class="j-stat">${wr}% WR</span>
        `;
    }
}

// ===== MT5 CONNECTION =====
let isConnected = false;
const mt5ConnectBtn = document.getElementById('mt5ConnectBtn');
const mt5Fields = document.getElementById('mt5Fields');
const mt5Connected = document.getElementById('mt5Connected');
const mt5Status = document.getElementById('mt5Status');
const mt5SyncLog = document.getElementById('mt5SyncLog');

mt5ConnectBtn.addEventListener('click', () => {
    if (!isConnected) {
        // Simulate connection
        mt5ConnectBtn.textContent = 'Connecting...';
        mt5ConnectBtn.disabled = true;

        setTimeout(() => {
            isConnected = true;
            mt5Fields.style.display = 'none';
            mt5Connected.style.display = 'block';
            mt5ConnectBtn.textContent = 'Connected';
            mt5ConnectBtn.classList.remove('btn-primary');
            mt5ConnectBtn.classList.add('btn-outline');
            mt5ConnectBtn.disabled = false;

            mt5Status.innerHTML = `
                <span class="status-indicator online"></span>
                <span class="status-text" style="color:#00FF88">Connected to ${document.getElementById('mt5Server').value}</span>
            `;

            addLogEntry(`Connected to ${document.getElementById('mt5Server').value}`);
        }, 1500);
    }
});

document.getElementById('mt5DisconnectBtn').addEventListener('click', () => {
    isConnected = false;
    mt5Connected.style.display = 'none';
    mt5Fields.style.display = 'block';
    mt5ConnectBtn.textContent = 'Connect';
    mt5ConnectBtn.classList.add('btn-primary');
    mt5ConnectBtn.classList.remove('btn-outline');

    mt5Status.innerHTML = `
        <span class="status-indicator offline"></span>
        <span class="status-text">Disconnected</span>
    `;

    addLogEntry('Disconnected from broker');
});

document.getElementById('mt5SyncBtn').addEventListener('click', () => {
    if (!isConnected) return;

    document.getElementById('mt5SyncBtn').textContent = 'Syncing...';

    setTimeout(() => {
        document.getElementById('lastSync').textContent = 'Just now';
        document.getElementById('mt5SyncBtn').textContent = '🔄 Sync Now';
        addLogEntry('Manual sync completed. 0 new trades.');
    }, 1000);
});

function addLogEntry(message) {
    const time = new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' });
    const entry = document.createElement('div');
    entry.className = 'log-entry';
    entry.innerHTML = `<span class="log-time">${time}</span> ${message}`;
    mt5SyncLog.insertBefore(entry, mt5SyncLog.firstChild);
}

// ===== SETTINGS TABS =====
document.querySelectorAll('.settings-tab').forEach(tab => {
    tab.addEventListener('click', () => {
        // Remove active from all tabs
        document.querySelectorAll('.settings-tab').forEach(t => t.classList.remove('active'));
        document.querySelectorAll('.settings-panel').forEach(p => p.classList.remove('active'));

        // Add active to clicked tab
        tab.classList.add('active');

        // Show corresponding panel
        const panelId = 'panel-' + tab.dataset.tab;
        document.getElementById(panelId).classList.add('active');
    });
});

// Personality cards
document.querySelectorAll('.personality-card').forEach(card => {
    card.addEventListener('click', () => {
        document.querySelectorAll('.personality-card').forEach(c => c.classList.remove('active'));
        card.classList.add('active');
    });
});

// Settings toggles
document.querySelectorAll('.settings-panel .toggle-switch').forEach(toggle => {
    toggle.addEventListener('click', function() {
        this.classList.toggle('active');
    });
});

// Save buttons feedback
['saveProfileBtn', 'saveTradingBtn', 'saveAIBtn', 'saveSecurityBtn'].forEach(id => {
    const btn = document.getElementById(id);
    if (btn) {
        btn.addEventListener('click', () => {
            const originalText = btn.textContent;
            btn.textContent = '✓ Saved!';
            btn.style.background = '#00FF88';
            btn.style.color = '#000';

            setTimeout(() => {
                btn.textContent = originalText;
                btn.style.background = '';
                btn.style.color = '';
            }, 2000);
        });
    }
});

// Auto-calculate P&L from entry/exit
document.getElementById('jEntry').addEventListener('input', calculateJournalPnL);
document.getElementById('jExit').addEventListener('input', calculateJournalPnL);

function calculateJournalPnL() {
    const entry = parseFloat(document.getElementById('jEntry').value);
    const exit = parseFloat(document.getElementById('jExit').value);
    const dir = selectedDir;

    if (entry && exit) {
        let pnl = 0;
        if (dir === 'LONG') {
            pnl = (exit - entry) * 100000 * 0.5; // rough estimate for 0.5 lots
        } else {
            pnl = (entry - exit) * 100000 * 0.5;
        }
        document.getElementById('jPnl').value = Math.round(pnl);
    }
}

console.log('🧪 Slime Trades v2 loaded — Journal, MT5, and Settings added!');

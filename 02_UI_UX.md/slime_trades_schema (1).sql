
-- ============================================================================
-- SLIME TRADES — Production Database Schema
-- PostgreSQL 16+ with TimescaleDB, pgvector, pgcrypto
-- Enterprise-Grade | Row-Level Security | Partitioned | Indexed
-- ============================================================================

-- ============================================================================
-- 1. EXTENSIONS & CONFIGURATION
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";        -- Fuzzy text search
CREATE EXTENSION IF NOT EXISTS "pgvector";       -- AI embeddings (pgvector)
CREATE EXTENSION IF NOT EXISTS "timescaledb";    -- Time-series optimization

-- ============================================================================
-- 2. CUSTOM TYPES & DOMAINS
-- ============================================================================

CREATE TYPE trade_direction AS ENUM ('BUY', 'SELL');
CREATE TYPE scan_type AS ENUM ('PRE', 'POST', 'CRISIS');
CREATE TYPE guardian_action AS ENUM ('BLOCK', 'WARN', 'ALLOW', 'COOLDOWN');
CREATE TYPE violation_severity AS ENUM ('LOW', 'MEDIUM', 'HIGH', 'CRITICAL');
CREATE TYPE subscription_status AS ENUM ('TRIAL', 'ACTIVE', 'PAST_DUE', 'CANCELLED', 'EXPIRED');
CREATE TYPE notification_priority AS ENUM ('LOW', 'NORMAL', 'HIGH', 'URGENT');
CREATE TYPE ai_role AS ENUM ('USER', 'AI', 'SYSTEM');
CREATE TYPE entry_type AS ENUM ('DAILY', 'TRADE', 'WEEKLY', 'CRISIS');
CREATE TYPE broker_type AS ENUM ('MT4', 'MT5', 'CTRADER', 'CUSTOM');

-- ============================================================================
-- 3. USER MANAGEMENT
-- ============================================================================

CREATE TABLE users (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email               VARCHAR(255) NOT NULL UNIQUE,
    password_hash       TEXT NOT NULL,
    subscription_tier   VARCHAR(20) DEFAULT 'FREE',
    trading_experience  VARCHAR(30),
    timezone            VARCHAR(50) DEFAULT 'UTC',
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    last_login          TIMESTAMPTZ,
    is_active           BOOLEAN DEFAULT TRUE,
    mfa_enabled         BOOLEAN DEFAULT FALSE,
    mfa_secret_encrypted BYTEA,
    email_verified      BOOLEAN DEFAULT FALSE,
    referral_code       VARCHAR(20),
    referred_by         UUID REFERENCES users(id) ON DELETE SET NULL,
    deleted_at          TIMESTAMPTZ,
    CONSTRAINT valid_email CHECK (email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$')
);

CREATE TABLE user_profiles (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    risk_tolerance      VARCHAR(30) DEFAULT 'MODERATE',
    trading_style       VARCHAR(30),
    markets_traded      TEXT[] DEFAULT '{}',
    avg_trade_duration  INTERVAL,
    psychological_triggers TEXT[] DEFAULT '{}',
    emergency_contact   JSONB,
    avatar_url          TEXT,
    bio                 TEXT,
    updated_at          TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE user_settings (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             UUID NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
    guardian_enabled    BOOLEAN DEFAULT TRUE,
    mind_scan_required  BOOLEAN DEFAULT FALSE,
    max_daily_loss      DECIMAL(18,8) DEFAULT 500.00,
    max_daily_trades    INT DEFAULT 10,
    cooldown_minutes    INT DEFAULT 10,
    notification_prefs  JSONB DEFAULT '{"push": true, "email": true, "sms": false}',
    privacy_settings    JSONB DEFAULT '{"share_analytics": false, "public_profile": false}',
    theme               VARCHAR(10) DEFAULT 'DARK',
    language            VARCHAR(5) DEFAULT 'en',
    updated_at          TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE user_sessions (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    session_token_hash  TEXT NOT NULL,
    ip_address          INET,
    user_agent          TEXT,
    expires_at          TIMESTAMPTZ NOT NULL,
    revoked             BOOLEAN DEFAULT FALSE,
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    last_active_at      TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================================
-- 4. BILLING & SUBSCRIPTIONS
-- ============================================================================

CREATE TABLE subscription_plans (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    plan_name           VARCHAR(50) NOT NULL UNIQUE,
    plan_code           VARCHAR(20) NOT NULL UNIQUE,
    price_monthly       DECIMAL(10,2) NOT NULL,
    price_annual        DECIMAL(10,2) NOT NULL,
    features            JSONB NOT NULL DEFAULT '{}',
    max_accounts        INT DEFAULT 1,
    max_guardian_rules  INT DEFAULT 3,
    ai_credits_monthly  INT DEFAULT 50,
    max_journal_storage_mb INT DEFAULT 100,
    is_active           BOOLEAN DEFAULT TRUE,
    sort_order          INT DEFAULT 0,
    created_at          TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE subscriptions (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    plan_id             UUID NOT NULL REFERENCES subscription_plans(id),
    status              subscription_status DEFAULT 'TRIAL',
    stripe_customer_id  VARCHAR(100),
    stripe_sub_id       VARCHAR(100),
    trial_ends_at       TIMESTAMPTZ,
    current_period_start TIMESTAMPTZ,
    current_period_end  TIMESTAMPTZ,
    cancel_at_period_end BOOLEAN DEFAULT FALSE,
    cancellation_reason TEXT,
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    updated_at          TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, stripe_sub_id)
);

CREATE TABLE payments (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    subscription_id     UUID REFERENCES subscriptions(id) ON DELETE SET NULL,
    user_id             UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    stripe_payment_intent_id VARCHAR(100),
    stripe_invoice_id   VARCHAR(100),
    amount              DECIMAL(10,2) NOT NULL,
    currency            VARCHAR(3) DEFAULT 'USD',
    status              VARCHAR(20) NOT NULL,
    paid_at             TIMESTAMPTZ,
    receipt_url         TEXT,
    failure_message     TEXT,
    created_at          TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE invoices (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    subscription_id     UUID REFERENCES subscriptions(id) ON DELETE SET NULL,
    user_id             UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    invoice_number      VARCHAR(50) NOT NULL UNIQUE,
    amount_due          DECIMAL(10,2) NOT NULL,
    amount_paid         DECIMAL(10,2) DEFAULT 0,
    currency            VARCHAR(3) DEFAULT 'USD',
    status              VARCHAR(20) NOT NULL,
    due_date            DATE,
    paid_at             TIMESTAMPTZ,
    line_items          JSONB,
    created_at          TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================================
-- 5. BROKER INTEGRATIONS (MT4/MT5)
-- ============================================================================

CREATE TABLE broker_connections (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    broker_type         broker_type NOT NULL DEFAULT 'MT5',
    account_id_encrypted BYTEA NOT NULL,          -- AES-256 encrypted
    api_key_encrypted   BYTEA NOT NULL,            -- AES-256 encrypted
    api_secret_encrypted BYTEA NOT NULL,           -- AES-256 encrypted
    server_name         VARCHAR(100),
    account_name        VARCHAR(100),
    last_sync_at        TIMESTAMPTZ,
    is_active           BOOLEAN DEFAULT TRUE,
    sync_frequency_seconds INT DEFAULT 30,
    sync_errors_count   INT DEFAULT 0,
    max_sync_errors     INT DEFAULT 10,
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    updated_at          TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, broker_type, server_name)
);

CREATE TABLE trading_accounts (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    broker_connection_id UUID NOT NULL REFERENCES broker_connections(id) ON DELETE CASCADE,
    account_number      VARCHAR(50) NOT NULL,
    account_type        VARCHAR(20) DEFAULT 'LIVE',
    balance             DECIMAL(18,8) DEFAULT 0,
    equity              DECIMAL(18,8) DEFAULT 0,
    margin_used         DECIMAL(18,8) DEFAULT 0,
    free_margin         DECIMAL(18,8) DEFAULT 0,
    currency            VARCHAR(3) DEFAULT 'USD',
    leverage            INT DEFAULT 100,
    profit_today        DECIMAL(18,8) DEFAULT 0,
    trades_today        INT DEFAULT 0,
    synced_at           TIMESTAMPTZ,
    is_active           BOOLEAN DEFAULT TRUE,
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, broker_connection_id, account_number)
);

CREATE TABLE broker_sync_queue (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    broker_connection_id UUID NOT NULL REFERENCES broker_connections(id) ON DELETE CASCADE,
    queue_type          VARCHAR(20) NOT NULL,     -- 'TRADES', 'ORDERS', 'ACCOUNT', 'HISTORY'
    payload             JSONB NOT NULL,
    priority            INT DEFAULT 5,             -- 1=urgent, 10=low
    status              VARCHAR(20) DEFAULT 'PENDING', -- PENDING, PROCESSING, COMPLETED, FAILED
    retry_count         INT DEFAULT 0,
    max_retries         INT DEFAULT 3,
    error_message       TEXT,
    scheduled_at        TIMESTAMPTZ DEFAULT NOW(),
    processed_at        TIMESTAMPTZ,
    created_at          TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE mt5_sync_logs (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    broker_connection_id UUID NOT NULL REFERENCES broker_connections(id) ON DELETE CASCADE,
    user_id             UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    sync_type           VARCHAR(20) NOT NULL,
    records_synced      INT DEFAULT 0,
    records_failed      INT DEFAULT 0,
    sync_status         VARCHAR(20) NOT NULL,
    error_message       TEXT,
    duration_ms         INT,
    started_at          TIMESTAMPTZ DEFAULT NOW(),
    completed_at        TIMESTAMPTZ
);

-- ============================================================================
-- 6. TRADE CORE
-- ============================================================================

CREATE TABLE trades (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    trading_account_id  UUID NOT NULL REFERENCES trading_accounts(id) ON DELETE CASCADE,
    broker_trade_id     VARCHAR(50) NOT NULL,
    symbol              VARCHAR(20) NOT NULL,
    direction           trade_direction NOT NULL,
    entry_price         DECIMAL(18,8) NOT NULL,
    exit_price          DECIMAL(18,8),
    volume              DECIMAL(18,8) NOT NULL,
    stop_loss           DECIMAL(18,8),
    take_profit         DECIMAL(18,8),
    realized_pnl        DECIMAL(18,8) DEFAULT 0,
    commission          DECIMAL(18,8) DEFAULT 0,
    swap                DECIMAL(18,8) DEFAULT 0,
    net_pnl             DECIMAL(18,8) GENERATED ALWAYS AS (COALESCE(realized_pnl,0) - COALESCE(commission,0) - COALESCE(swap,0)) STORED,
    strategy_tag        VARCHAR(50),
    emotion_tag         VARCHAR(50),
    time_frame          VARCHAR(10),
    opened_at           TIMESTAMPTZ NOT NULL,
    closed_at           TIMESTAMPTZ,
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    updated_at          TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, trading_account_id, broker_trade_id)
);

CREATE TABLE open_positions (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    trading_account_id  UUID NOT NULL REFERENCES trading_accounts(id) ON DELETE CASCADE,
    trade_id            UUID REFERENCES trades(id) ON DELETE SET NULL,
    symbol              VARCHAR(20) NOT NULL,
    direction           trade_direction NOT NULL,
    entry_price         DECIMAL(18,8) NOT NULL,
    current_price       DECIMAL(18,8),
    volume              DECIMAL(18,8) NOT NULL,
    unrealized_pnl      DECIMAL(18,8) DEFAULT 0,
    stop_loss           DECIMAL(18,8),
    take_profit         DECIMAL(18,8),
    opened_at           TIMESTAMPTZ NOT NULL,
    updated_at          TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE closed_positions (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    trade_id            UUID NOT NULL REFERENCES trades(id) ON DELETE CASCADE,
    trading_account_id  UUID NOT NULL REFERENCES trading_accounts(id) ON DELETE CASCADE,
    symbol              VARCHAR(20) NOT NULL,
    direction           trade_direction NOT NULL,
    entry_price         DECIMAL(18,8) NOT NULL,
    exit_price          DECIMAL(18,8) NOT NULL,
    volume              DECIMAL(18,8) NOT NULL,
    realized_pnl        DECIMAL(18,8) NOT NULL,
    exit_reason         VARCHAR(50),              -- 'TP', 'SL', 'MANUAL', 'MARGIN_CALL'
    duration_seconds    INT,
    closed_at           TIMESTAMPTZ NOT NULL,
    created_at          TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE risk_metrics (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    trade_id            UUID REFERENCES trades(id) ON DELETE CASCADE,
    risk_per_trade_r    DECIMAL(5,2),
    risk_reward_ratio   DECIMAL(5,2),
    position_size_lots  DECIMAL(18,8),
    account_risk_percent DECIMAL(5,2),
    max_drawdown        DECIMAL(18,8),
    daily_risk_used     DECIMAL(18,8),
    daily_risk_limit    DECIMAL(18,8),
    calculated_at       TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================================
-- 7. PSYCHOLOGY ENGINE
-- ============================================================================

CREATE TABLE mind_scans (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    scan_type           scan_type NOT NULL DEFAULT 'PRE',
    stress_level        INT NOT NULL CHECK (stress_level BETWEEN 1 AND 10),
    confidence_score    INT NOT NULL CHECK (confidence_score BETWEEN 1 AND 10),
    readiness_score     INT NOT NULL CHECK (readiness_score BETWEEN 0 AND 100),
    fomo_level          INT NOT NULL CHECK (fomo_level BETWEEN 1 AND 5),
    revenge_urge        INT NOT NULL CHECK (revenge_urge BETWEEN 1 AND 5),
    fatigue_level       INT NOT NULL CHECK (fatigue_level BETWEEN 1 AND 5),
    overall_mood        VARCHAR(20),
    notes               TEXT,
    biometric_snapshot  JSONB,                    -- HRV, sleep, etc.
    timestamp           TIMESTAMPTZ DEFAULT NOW(),
    created_at          TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE mind_scan_answers (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    mind_scan_id        UUID NOT NULL REFERENCES mind_scans(id) ON DELETE CASCADE,
    user_id             UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    question_id         VARCHAR(50) NOT NULL,
    question_text       TEXT NOT NULL,
    answer_value        INT NOT NULL,
    answer_label        VARCHAR(50),
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(mind_scan_id, question_id)
);

CREATE TABLE sanctuary_sessions (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    session_type        VARCHAR(30) NOT NULL DEFAULT 'BREATHING',
    technique_used      VARCHAR(30) NOT NULL DEFAULT 'BOX_BREATHING',
    duration_seconds    INT NOT NULL DEFAULT 180,
    actual_duration_seconds INT,
    hr_before           INT,
    hr_after            INT,
    hr_min              INT,
    hr_max              INT,
    stress_delta        DECIMAL(5,2),
    completed           BOOLEAN DEFAULT FALSE,
    abandoned           BOOLEAN DEFAULT FALSE,
    trigger_context     TEXT,                     -- 'POST_LOSS', 'PRE_MARKET', 'STRESS'
    started_at          TIMESTAMPTZ DEFAULT NOW(),
    ended_at            TIMESTAMPTZ
);

CREATE TABLE emotional_timeline (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    trade_id            UUID REFERENCES trades(id) ON DELETE SET NULL,
    timestamp           TIMESTAMPTZ DEFAULT NOW(),
    emotion_primary     VARCHAR(30) NOT NULL,     -- 'CALM', 'ANXIOUS', 'ANGRY', 'EXCITED'
    emotion_secondary   VARCHAR(30),
    emotion_intensity   INT CHECK (emotion_intensity BETWEEN 1 AND 10),
    market_context      VARCHAR(50),              -- 'PRE_MARKET', 'DURING_TRADE', 'POST_TRADE'
    session_context     VARCHAR(50),              -- 'LONDON', 'NY', 'ASIAN'
    biometric_data      JSONB,
    notes               TEXT,
    created_at          TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE emotional_states (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    state_name          VARCHAR(30) NOT NULL,
    state_category      VARCHAR(20) NOT NULL,       -- 'POSITIVE', 'NEGATIVE', 'NEUTRAL'
    intensity           INT CHECK (intensity BETWEEN 1 AND 10),
    trigger_event       VARCHAR(100),
    trigger_trade_id    UUID REFERENCES trades(id) ON DELETE SET NULL,
    duration_minutes    INT,
    resolved            BOOLEAN DEFAULT FALSE,
    resolution_method   VARCHAR(50),              -- 'SANCTUARY', 'TIME', 'GUARDIAN'
    started_at          TIMESTAMPTZ DEFAULT NOW(),
    ended_at            TIMESTAMPTZ
);

CREATE TABLE recovery_plans (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    plan_type           VARCHAR(30) NOT NULL,       -- 'POST_LOSS', 'PRE_MARKET', 'DAILY'
    trigger_pattern     VARCHAR(50),
    trigger_trade_id    UUID REFERENCES trades(id) ON DELETE SET NULL,
    steps               JSONB NOT NULL,             -- Ordered array of steps
    sanctuary_session_ids UUID[],
    completed           BOOLEAN DEFAULT FALSE,
    effectiveness_score   INT CHECK (effectiveness_score BETWEEN 1 AND 10),
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    completed_at        TIMESTAMPTZ
);

-- ============================================================================
-- 8. TRADE GUARDIAN
-- ============================================================================

CREATE TABLE trade_guardian_rules (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    rule_name           VARCHAR(50) NOT NULL,
    rule_type           VARCHAR(30) NOT NULL,     -- 'DAILY_LOSS', 'MAX_TRADES', 'COOLDOWN', 'MIND_SCAN_GATE', 'TIME_OF_DAY', 'CONSECUTIVE_LOSS'
    rule_config         JSONB NOT NULL,           -- Flexible configuration per rule type
    is_active           BOOLEAN DEFAULT TRUE,
    priority            INT DEFAULT 5,             -- 1=highest
    alert_message       TEXT,
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    updated_at          TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE trade_guardian_logs (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    trade_id            UUID REFERENCES trades(id) ON DELETE SET NULL,
    rule_id             UUID REFERENCES trade_guardian_rules(id) ON DELETE SET NULL,
    rule_type           VARCHAR(30) NOT NULL,
    rule_config         JSONB,
    triggered           BOOLEAN DEFAULT FALSE,
    action_taken        guardian_action NOT NULL DEFAULT 'ALLOW',
    blocked_trade       BOOLEAN DEFAULT FALSE,
    violation_severity  violation_severity,
    user_override       BOOLEAN DEFAULT FALSE,
    override_reason     TEXT,
    market_context      JSONB,                    -- Symbol, price, time
    timestamp           TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE trade_guardian_violations (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    trade_id            UUID REFERENCES trades(id) ON DELETE SET NULL,
    rule_id             UUID REFERENCES trade_guardian_rules(id) ON DELETE SET NULL,
    violation_type      VARCHAR(30) NOT NULL,
    violation_details   JSONB,
    consequence_pnl     DECIMAL(18,8),
    acknowledged        BOOLEAN DEFAULT FALSE,
    acknowledged_at     TIMESTAMPTZ,
    timestamp           TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE trade_readiness_scores (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    mind_scan_id        UUID REFERENCES mind_scans(id) ON DELETE SET NULL,
    readiness_score     INT NOT NULL CHECK (readiness_score BETWEEN 0 AND 100),
    threshold_used      INT NOT NULL DEFAULT 50,
    passed                BOOLEAN DEFAULT FALSE,
    trade_attempted     BOOLEAN DEFAULT FALSE,
    trade_executed      BOOLEAN DEFAULT FALSE,
    timestamp           TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE discipline_scores (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    score_period        VARCHAR(20) NOT NULL,     -- 'DAILY', 'WEEKLY', 'MONTHLY'
    score_date          DATE NOT NULL,
    discipline_score    INT NOT NULL CHECK (discipline_score BETWEEN 0 AND 100),
    rule_adherence_percent DECIMAL(5,2),
    override_count      INT DEFAULT 0,
    sanctuary_sessions_count INT DEFAULT 0,
    mind_scan_compliance INT DEFAULT 0,          -- Percentage
    trades_taken        INT DEFAULT 0,
    trades_planned      INT DEFAULT 0,
    calculated_at       TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, score_period, score_date)
);

-- ============================================================================
-- 9. SLIME JOURNAL
-- ============================================================================

CREATE TABLE journal_entries (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    trade_id            UUID REFERENCES trades(id) ON DELETE SET NULL,
    entry_type          entry_type NOT NULL DEFAULT 'DAILY',
    narrative           TEXT,
    lessons_learned     TEXT,
    what_i_saw          TEXT,
    what_i_felt         TEXT,
    what_i_did          TEXT,
    what_next           TEXT,
    mood_rating         INT CHECK (mood_rating BETWEEN 1 AND 10),
    discipline_score    INT CHECK (discipline_score BETWEEN 0 AND 100),
    ai_summary          TEXT,
    ai_sentiment        VARCHAR(20),
    ai_keywords         TEXT[],
    is_favorite         BOOLEAN DEFAULT FALSE,
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    updated_at          TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE journal_attachments (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    journal_entry_id    UUID NOT NULL REFERENCES journal_entries(id) ON DELETE CASCADE,
    user_id             UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    attachment_type     VARCHAR(20) NOT NULL,     -- 'IMAGE', 'VIDEO', 'AUDIO', 'SCREENSHOT'
    file_url            TEXT NOT NULL,
    file_path           TEXT,                     -- Internal storage path
    file_size_bytes     INT,
    mime_type           VARCHAR(50),
    thumbnail_url       TEXT,
    duration_seconds    INT,                      -- For video/audio
    uploaded_at         TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE journal_tags (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tag_name            VARCHAR(50) NOT NULL,
    tag_category        VARCHAR(30),              -- 'STRATEGY', 'EMOTION', 'MISTAKE', 'LESSON'
    usage_count         INT DEFAULT 1,
    color_hex           VARCHAR(7) DEFAULT '#10B981',
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, tag_name)
);

CREATE TABLE journal_entry_tags (
    journal_entry_id    UUID NOT NULL REFERENCES journal_entries(id) ON DELETE CASCADE,
    tag_id              UUID NOT NULL REFERENCES journal_tags(id) ON DELETE CASCADE,
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (journal_entry_id, tag_id)
);

-- ============================================================================
-- 10. SLIME AI
-- ============================================================================

CREATE TABLE ai_conversations (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    session_id          VARCHAR(50) NOT NULL,
    conversation_title  VARCHAR(100),
    context_summary     TEXT,
    is_active           BOOLEAN DEFAULT TRUE,
    model_version       VARCHAR(20) DEFAULT 'gpt-4',
    total_tokens_used   INT DEFAULT 0,
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    updated_at          TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, session_id)
);

CREATE TABLE ai_messages (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id     UUID NOT NULL REFERENCES ai_conversations(id) ON DELETE CASCADE,
    user_id             UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    message_content     TEXT NOT NULL,
    role                ai_role NOT NULL,
    intent_detected     VARCHAR(50),
    sentiment_score     DECIMAL(4,3) CHECK (sentiment_score BETWEEN -1 AND 1),
    context_vector      VECTOR(1536),             -- OpenAI embedding
    referenced_trade_id UUID REFERENCES trades(id) ON DELETE SET NULL,
    referenced_journal_id UUID REFERENCES journal_entries(id) ON DELETE SET NULL,
    tokens_used         INT,
    processing_time_ms  INT,
    created_at          TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE ai_insights (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    conversation_id     UUID REFERENCES ai_conversations(id) ON DELETE SET NULL,
    insight_type        VARCHAR(30) NOT NULL,       -- 'PATTERN', 'CORRELATION', 'PREDICTION', 'RECOMMENDATION'
    pattern_detected    VARCHAR(100),
    confidence_score    DECIMAL(5,4) CHECK (confidence_score BETWEEN 0 AND 1),
    recommendation      TEXT,
    supporting_data     JSONB,
    actionable          BOOLEAN DEFAULT TRUE,
    dismissed           BOOLEAN DEFAULT FALSE,
    dismissed_at        TIMESTAMPTZ,
    implemented         BOOLEAN DEFAULT FALSE,
    implemented_at      TIMESTAMPTZ,
    generated_at        TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE behavior_patterns (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    pattern_name        VARCHAR(100) NOT NULL,
    pattern_category    VARCHAR(30) NOT NULL,       -- 'REVENGE', 'OVERTRADING', 'FOMO', 'PARALYSIS', 'DISCIPLINE'
    pattern_data        JSONB NOT NULL,            -- Detailed pattern definition
    frequency_7d        INT DEFAULT 0,
    frequency_30d       INT DEFAULT 0,
    frequency_90d       INT DEFAULT 0,
    total_occurrences   INT DEFAULT 0,
    avg_consequence_pnl DECIMAL(18,8),
    risk_level          VARCHAR(20) DEFAULT 'MEDIUM', -- 'LOW', 'MEDIUM', 'HIGH', 'CRITICAL'
    first_observed      TIMESTAMPTZ,
    last_observed       TIMESTAMPTZ,
    ai_model_version    VARCHAR(20),
    is_active           BOOLEAN DEFAULT TRUE,
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    updated_at          TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================================
-- 11. ANALYTICS & METRICS
-- ============================================================================

CREATE TABLE analytics_snapshots (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    snapshot_type       VARCHAR(30) NOT NULL,       -- 'DAILY', 'WEEKLY', 'MONTHLY', 'TRADE_REVIEW'
    snapshot_period     VARCHAR(20) NOT NULL,
    snapshot_date       DATE NOT NULL,
    metrics             JSONB NOT NULL,
    trade_count         INT DEFAULT 0,
    win_count           INT DEFAULT 0,
    loss_count          INT DEFAULT 0,
    total_pnl           DECIMAL(18,8) DEFAULT 0,
    avg_r_per_trade     DECIMAL(5,2),
    max_drawdown        DECIMAL(18,8),
    sharpe_ratio        DECIMAL(5,2),
    emotional_stability_score INT,
    calculated_at       TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, snapshot_type, snapshot_date)
);

CREATE TABLE analytics_events (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    event_type          VARCHAR(50) NOT NULL,       -- 'PAGE_VIEW', 'BUTTON_CLICK', 'FEATURE_USED', 'ERROR'
    event_category      VARCHAR(30) NOT NULL,       -- 'NAVIGATION', 'TRADING', 'PSYCHOLOGY', 'AI', 'GUARDIAN'
    event_data          JSONB,
    session_id          VARCHAR(50),
    client_timestamp    TIMESTAMPTZ,
    server_timestamp    TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================================
-- 12. NOTIFICATIONS
-- ============================================================================

CREATE TABLE notifications (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    notification_type   VARCHAR(30) NOT NULL,       -- 'GUARDIAN_ALERT', 'AI_INSIGHT', 'TRADE_SYNC', 'BILLING'
    title               VARCHAR(100) NOT NULL,
    message             TEXT NOT NULL,
    priority            notification_priority DEFAULT 'NORMAL',
    read                BOOLEAN DEFAULT FALSE,
    action_url          TEXT,
    action_type         VARCHAR(30),                -- 'NAVIGATE', 'MODAL', 'EXTERNAL'
    metadata            JSONB,
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    read_at             TIMESTAMPTZ,
    expires_at          TIMESTAMPTZ
);

CREATE TABLE notification_preferences (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             UUID NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
    email_enabled       BOOLEAN DEFAULT TRUE,
    push_enabled        BOOLEAN DEFAULT TRUE,
    sms_enabled         BOOLEAN DEFAULT FALSE,
    guardian_alerts     BOOLEAN DEFAULT TRUE,
    ai_insights         BOOLEAN DEFAULT TRUE,
    trade_sync          BOOLEAN DEFAULT TRUE,
    billing_alerts      BOOLEAN DEFAULT TRUE,
    marketing_emails    BOOLEAN DEFAULT FALSE,
    daily_summary_time  TIME DEFAULT '18:00',
    quiet_hours_start   TIME,
    quiet_hours_end     TIME,
    updated_at          TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================================
-- 13. INDEXING STRATEGY
-- ============================================================================

-- Users & Auth
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_active ON users(is_active) WHERE is_active = TRUE;
CREATE INDEX idx_users_last_login ON users(last_login DESC);
CREATE INDEX idx_sessions_token ON user_sessions(session_token_hash);
CREATE INDEX idx_sessions_expires ON user_sessions(expires_at) WHERE revoked = FALSE;
CREATE INDEX idx_sessions_user ON user_sessions(user_id, created_at DESC);

-- Billing
CREATE INDEX idx_subscriptions_user ON subscriptions(user_id, status);
CREATE INDEX idx_subscriptions_stripe ON subscriptions(stripe_sub_id);
CREATE INDEX idx_payments_user ON payments(user_id, created_at DESC);
CREATE INDEX idx_payments_status ON payments(status, created_at DESC);
CREATE INDEX idx_invoices_user ON invoices(user_id, created_at DESC);

-- Broker Integrations
CREATE INDEX idx_broker_conn_user ON broker_connections(user_id, is_active);
CREATE INDEX idx_broker_conn_active ON broker_connections(is_active, last_sync_at DESC);
CREATE INDEX idx_trading_accounts_user ON trading_accounts(user_id, is_active);
CREATE INDEX idx_sync_queue_status ON broker_sync_queue(status, priority DESC, scheduled_at);
CREATE INDEX idx_sync_queue_user ON broker_sync_queue(user_id, created_at DESC);
CREATE INDEX idx_mt5_logs_conn ON mt5_sync_logs(broker_connection_id, started_at DESC);

-- Trades (Heavy indexing for real-time dashboards)
CREATE INDEX idx_trades_user_symbol ON trades(user_id, symbol, opened_at DESC);
CREATE INDEX idx_trades_user_date ON trades(user_id, opened_at DESC);
CREATE INDEX idx_trades_user_closed ON trades(user_id, closed_at DESC) WHERE closed_at IS NOT NULL;
CREATE INDEX idx_trades_broker ON trades(trading_account_id, broker_trade_id);
CREATE INDEX idx_trades_strategy ON trades(user_id, strategy_tag, opened_at DESC);
CREATE INDEX idx_trades_emotion ON trades(user_id, emotion_tag, opened_at DESC);
CREATE INDEX idx_trades_pnl ON trades(user_id, realized_pnl, opened_at DESC);
CREATE INDEX idx_open_positions_user ON open_positions(user_id, updated_at DESC);
CREATE INDEX idx_closed_positions_user ON closed_positions(user_id, closed_at DESC);
CREATE INDEX idx_risk_metrics_user ON risk_metrics(user_id, calculated_at DESC);
CREATE INDEX idx_risk_metrics_trade ON risk_metrics(trade_id);

-- Psychology (Time-series optimized)
CREATE INDEX idx_mind_scans_user_time ON mind_scans(user_id, timestamp DESC);
CREATE INDEX idx_mind_scans_user_type ON mind_scans(user_id, scan_type, timestamp DESC);
CREATE INDEX idx_mind_scans_readiness ON mind_scans(user_id, readiness_score, timestamp DESC);
CREATE INDEX idx_mind_scan_answers_scan ON mind_scan_answers(mind_scan_id);
CREATE INDEX idx_sanctuary_user ON sanctuary_sessions(user_id, started_at DESC);
CREATE INDEX idx_sanctuary_completed ON sanctuary_sessions(user_id, completed, started_at DESC);
CREATE INDEX idx_emotional_timeline_user ON emotional_timeline(user_id, timestamp DESC);
CREATE INDEX idx_emotional_timeline_trade ON emotional_timeline(trade_id);
CREATE INDEX idx_emotional_timeline_emotion ON emotional_timeline(user_id, emotion_primary, timestamp DESC);
CREATE INDEX idx_emotional_states_user ON emotional_states(user_id, started_at DESC);
CREATE INDEX idx_emotional_states_resolved ON emotional_states(user_id, resolved, started_at DESC);
CREATE INDEX idx_recovery_user ON recovery_plans(user_id, created_at DESC);

-- Guardian (High-frequency lookups)
CREATE INDEX idx_guardian_rules_user ON trade_guardian_rules(user_id, is_active, priority);
CREATE INDEX idx_guardian_logs_user ON trade_guardian_logs(user_id, timestamp DESC);
CREATE INDEX idx_guardian_logs_trade ON trade_guardian_logs(trade_id);
CREATE INDEX idx_guardian_logs_action ON trade_guardian_logs(user_id, action_taken, timestamp DESC);
CREATE INDEX idx_guardian_violations_user ON trade_guardian_violations(user_id, timestamp DESC);
CREATE INDEX idx_guardian_violations_ack ON trade_guardian_violations(user_id, acknowledged, timestamp DESC);
CREATE INDEX idx_readiness_user ON trade_readiness_scores(user_id, timestamp DESC);
CREATE INDEX idx_discipline_user_period ON discipline_scores(user_id, score_period, score_date DESC);

-- Journal (Full-text search + tagging)
CREATE INDEX idx_journal_user_type ON journal_entries(user_id, entry_type, created_at DESC);
CREATE INDEX idx_journal_user_trade ON journal_entries(user_id, trade_id);
CREATE INDEX idx_journal_created ON journal_entries(user_id, created_at DESC);
CREATE INDEX idx_journal_fts ON journal_entries USING gin(to_tsvector('english', COALESCE(narrative,'') || ' ' || COALESCE(lessons_learned,'')));
CREATE INDEX idx_journal_attachments_entry ON journal_attachments(journal_entry_id);
CREATE INDEX idx_journal_tags_user ON journal_tags(user_id, usage_count DESC);
CREATE INDEX idx_journal_entry_tags ON journal_entry_tags(tag_id);

-- AI (Vector + semantic search)
CREATE INDEX idx_ai_conversations_user ON ai_conversations(user_id, updated_at DESC);
CREATE INDEX idx_ai_messages_conv ON ai_messages(conversation_id, created_at DESC);
CREATE INDEX idx_ai_messages_vector ON ai_messages USING ivfflat (context_vector vector_cosine_ops) WITH (lists = 100);
CREATE INDEX idx_ai_insights_user ON ai_insights(user_id, generated_at DESC);
CREATE INDEX idx_ai_insights_dismissed ON ai_insights(user_id, dismissed, generated_at DESC) WHERE dismissed = FALSE;
CREATE INDEX idx_behavior_patterns_user ON behavior_patterns(user_id, risk_level, last_observed DESC);
CREATE INDEX idx_behavior_patterns_active ON behavior_patterns(user_id, is_active, last_observed DESC);

-- Analytics
CREATE INDEX idx_analytics_snapshots_user ON analytics_snapshots(user_id, snapshot_type, snapshot_date DESC);
CREATE INDEX idx_analytics_events_user ON analytics_events(user_id, server_timestamp DESC);
CREATE INDEX idx_analytics_events_type ON analytics_events(event_type, server_timestamp DESC);

-- Notifications
CREATE INDEX idx_notifications_user ON notifications(user_id, created_at DESC);
CREATE INDEX idx_notifications_unread ON notifications(user_id, read, created_at DESC) WHERE read = FALSE;
CREATE INDEX idx_notifications_type ON notifications(user_id, notification_type, created_at DESC);

-- ============================================================================
-- 14. ROW LEVEL SECURITY (RLS) POLICIES
-- ============================================================================

ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE broker_connections ENABLE ROW LEVEL SECURITY;
ALTER TABLE trading_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE broker_sync_queue ENABLE ROW LEVEL SECURITY;
ALTER TABLE mt5_sync_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE trades ENABLE ROW LEVEL SECURITY;
ALTER TABLE open_positions ENABLE ROW LEVEL SECURITY;
ALTER TABLE closed_positions ENABLE ROW LEVEL SECURITY;
ALTER TABLE risk_metrics ENABLE ROW LEVEL SECURITY;
ALTER TABLE mind_scans ENABLE ROW LEVEL SECURITY;
ALTER TABLE mind_scan_answers ENABLE ROW LEVEL SECURITY;
ALTER TABLE sanctuary_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE emotional_timeline ENABLE ROW LEVEL SECURITY;
ALTER TABLE emotional_states ENABLE ROW LEVEL SECURITY;
ALTER TABLE recovery_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE trade_guardian_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE trade_guardian_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE trade_guardian_violations ENABLE ROW LEVEL SECURITY;
ALTER TABLE trade_readiness_scores ENABLE ROW LEVEL SECURITY;
ALTER TABLE discipline_scores ENABLE ROW LEVEL SECURITY;
ALTER TABLE journal_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE journal_attachments ENABLE ROW LEVEL SECURITY;
ALTER TABLE journal_tags ENABLE ROW LEVEL SECURITY;
ALTER TABLE journal_entry_tags ENABLE ROW LEVEL SECURITY;
ALTER TABLE ai_conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE ai_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE ai_insights ENABLE ROW LEVEL SECURITY;
ALTER TABLE behavior_patterns ENABLE ROW LEVEL SECURITY;
ALTER TABLE analytics_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE analytics_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE notification_preferences ENABLE ROW LEVEL SECURITY;

-- Create RLS application role
CREATE ROLE slime_app_user NOLOGIN;

-- Users: can only see own record (admins see all via separate role)
CREATE POLICY users_own_data ON users
    FOR ALL TO slime_app_user
    USING (id = current_setting('app.current_user_id')::UUID);

-- Generic user-owned table policy function
CREATE OR REPLACE FUNCTION create_user_rls_policy(table_name text)
RETURNS void AS $$
BEGIN
    EXECUTE format('
        CREATE POLICY %I_user_isolation ON %I
        FOR ALL TO slime_app_user
        USING (user_id = current_setting(''app.current_user_id'')::UUID);
    ', table_name, table_name);
END;
$$ LANGUAGE plpgsql;

-- Apply to all user-owned tables
SELECT create_user_rls_policy('user_profiles');
SELECT create_user_rls_policy('user_settings');
SELECT create_user_rls_policy('user_sessions');
SELECT create_user_rls_policy('subscriptions');
SELECT create_user_rls_policy('payments');
SELECT create_user_rls_policy('invoices');
SELECT create_user_rls_policy('broker_connections');
SELECT create_user_rls_policy('trading_accounts');
SELECT create_user_rls_policy('broker_sync_queue');
SELECT create_user_rls_policy('mt5_sync_logs');
SELECT create_user_rls_policy('trades');
SELECT create_user_rls_policy('open_positions');
SELECT create_user_rls_policy('closed_positions');
SELECT create_user_rls_policy('risk_metrics');
SELECT create_user_rls_policy('mind_scans');
SELECT create_user_rls_policy('mind_scan_answers');
SELECT create_user_rls_policy('sanctuary_sessions');
SELECT create_user_rls_policy('emotional_timeline');
SELECT create_user_rls_policy('emotional_states');
SELECT create_user_rls_policy('recovery_plans');
SELECT create_user_rls_policy('trade_guardian_rules');
SELECT create_user_rls_policy('trade_guardian_logs');
SELECT create_user_rls_policy('trade_guardian_violations');
SELECT create_user_rls_policy('trade_readiness_scores');
SELECT create_user_rls_policy('discipline_scores');
SELECT create_user_rls_policy('journal_entries');
SELECT create_user_rls_policy('journal_attachments');
SELECT create_user_rls_policy('journal_tags');
SELECT create_user_rls_policy('ai_conversations');
SELECT create_user_rls_policy('ai_messages');
SELECT create_user_rls_policy('ai_insights');
SELECT create_user_rls_policy('behavior_patterns');
SELECT create_user_rls_policy('analytics_snapshots');
SELECT create_user_rls_policy('analytics_events');
SELECT create_user_rls_policy('notifications');
SELECT create_user_rls_policy('notification_preferences');

-- Journal entry tags junction table needs special policy
CREATE POLICY journal_entry_tags_user_isolation ON journal_entry_tags
    FOR ALL TO slime_app_user
    USING (journal_entry_id IN (SELECT id FROM journal_entries WHERE user_id = current_setting('app.current_user_id')::UUID));

-- Subscription plans: readable by all authenticated users
CREATE POLICY subscription_plans_readable ON subscription_plans
    FOR SELECT TO slime_app_user
    USING (is_active = TRUE);

-- ============================================================================
-- 15. PARTITIONING STRATEGY
-- ============================================================================

-- Trades: Range partition by opened_at (monthly) for 100K+ traders
CREATE TABLE trades_partitioned (
    LIKE trades INCLUDING ALL
) PARTITION BY RANGE (opened_at);

-- Create monthly partitions for current year + next year
DO $$
DECLARE
    start_date DATE;
    end_date DATE;
    partition_name TEXT;
BEGIN
    FOR i IN 0..13 LOOP
        start_date := DATE_TRUNC('month', CURRENT_DATE + (i || ' months')::INTERVAL);
        end_date := start_date + INTERVAL '1 month';
        partition_name := 'trades_' || TO_CHAR(start_date, 'YYYY_MM');

        EXECUTE format('
            CREATE TABLE %I PARTITION OF trades_partitioned
            FOR VALUES FROM (%L) TO (%L);
        ', partition_name, start_date, end_date);
    END LOOP;
END $$;

-- Convert original trades to partitioned (migration step)
-- NOTE: In production, use pg_partman or manual migration

-- Analytics events: Range partition by server_timestamp (daily) using TimescaleDB
SELECT create_hypertable('analytics_events', 'server_timestamp', 
    chunk_time_interval => INTERVAL '1 day',
    if_not_exists => TRUE);

-- Emotional timeline: Range partition by timestamp (weekly) using TimescaleDB
SELECT create_hypertable('emotional_timeline', 'timestamp',
    chunk_time_interval => INTERVAL '7 days',
    if_not_exists => TRUE);

-- Mind scans: Range partition by timestamp (monthly)
SELECT create_hypertable('mind_scans', 'timestamp',
    chunk_time_interval => INTERVAL '30 days',
    if_not_exists => TRUE);

-- Guardian logs: Range partition by timestamp (weekly)
SELECT create_hypertable('trade_guardian_logs', 'timestamp',
    chunk_time_interval => INTERVAL '7 days',
    if_not_exists => TRUE);

-- Notifications: Range partition by created_at (monthly)
SELECT create_hypertable('notifications', 'created_at',
    chunk_time_interval => INTERVAL '30 days',
    if_not_exists => TRUE);

-- ============================================================================
-- 16. FUNCTIONS & TRIGGERS
-- ============================================================================

-- Auto-update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply to all tables with updated_at
CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_user_profiles_updated_at BEFORE UPDATE ON user_profiles
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_user_settings_updated_at BEFORE UPDATE ON user_settings
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_subscriptions_updated_at BEFORE UPDATE ON subscriptions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_broker_connections_updated_at BEFORE UPDATE ON broker_connections
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_trades_updated_at BEFORE UPDATE ON trades
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_open_positions_updated_at BEFORE UPDATE ON open_positions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_trade_guardian_rules_updated_at BEFORE UPDATE ON trade_guardian_rules
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_journal_entries_updated_at BEFORE UPDATE ON journal_entries
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_ai_conversations_updated_at BEFORE UPDATE ON ai_conversations
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_behavior_patterns_updated_at BEFORE UPDATE ON behavior_patterns
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_notification_prefs_updated_at BEFORE UPDATE ON notification_preferences
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Auto-calculate net_pnl on trade update
CREATE OR REPLACE FUNCTION calculate_trade_net_pnl()
RETURNS TRIGGER AS $$
BEGIN
    NEW.net_pnl = COALESCE(NEW.realized_pnl, 0) - COALESCE(NEW.commission, 0) - COALESCE(NEW.swap, 0);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_calculate_net_pnl BEFORE INSERT OR UPDATE ON trades
    FOR EACH ROW EXECUTE FUNCTION calculate_trade_net_pnl();

-- Auto-increment journal tag usage count
CREATE OR REPLACE FUNCTION increment_tag_usage()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE journal_tags SET usage_count = usage_count + 1 WHERE id = NEW.tag_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_increment_tag_usage AFTER INSERT ON journal_entry_tags
    FOR EACH ROW EXECUTE FUNCTION increment_tag_usage();

-- Auto-decrement journal tag usage count
CREATE OR REPLACE FUNCTION decrement_tag_usage()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE journal_tags SET usage_count = GREATEST(usage_count - 1, 0) WHERE id = OLD.tag_id;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_decrement_tag_usage AFTER DELETE ON journal_entry_tags
    FOR EACH ROW EXECUTE FUNCTION decrement_tag_usage();

-- ============================================================================
-- 17. VIEWS FOR COMMON QUERIES
-- ============================================================================

-- Daily trading summary per user
CREATE OR REPLACE VIEW v_daily_trading_summary AS
SELECT 
    user_id,
    DATE(opened_at) as trade_date,
    COUNT(*) as total_trades,
    SUM(CASE WHEN realized_pnl > 0 THEN 1 ELSE 0 END) as win_count,
    SUM(CASE WHEN realized_pnl < 0 THEN 1 ELSE 0 END) as loss_count,
    SUM(realized_pnl) as total_pnl,
    AVG(realized_pnl) as avg_pnl,
    MAX(realized_pnl) as best_trade,
    MIN(realized_pnl) as worst_trade,
    SUM(commission + swap) as total_costs
FROM trades
WHERE closed_at IS NOT NULL
GROUP BY user_id, DATE(opened_at);

-- Emotional-Financial correlation per user
CREATE OR REPLACE VIEW v_emotion_trade_correlation AS
SELECT 
    t.user_id,
    t.symbol,
    t.emotion_tag,
    AVG(t.realized_pnl) as avg_pnl,
    COUNT(*) as trade_count,
    AVG(ms.readiness_score) as avg_readiness,
    AVG(ms.stress_level) as avg_stress
FROM trades t
LEFT JOIN mind_scans ms ON ms.user_id = t.user_id 
    AND ms.timestamp BETWEEN t.opened_at - INTERVAL '1 hour' AND t.opened_at
WHERE t.closed_at IS NOT NULL
GROUP BY t.user_id, t.symbol, t.emotion_tag;

-- Guardian effectiveness summary
CREATE OR REPLACE VIEW v_guardian_effectiveness AS
SELECT 
    user_id,
    DATE(timestamp) as check_date,
    COUNT(*) as total_evaluations,
    SUM(CASE WHEN blocked_trade THEN 1 ELSE 0 END) as blocks_count,
    SUM(CASE WHEN user_override THEN 1 ELSE 0 END) as overrides_count,
    SUM(CASE WHEN action_taken = 'WARN' THEN 1 ELSE 0 END) as warnings_count,
    AVG(CASE WHEN blocked_trade THEN 1 ELSE 0 END) * 100 as block_rate_percent
FROM trade_guardian_logs
GROUP BY user_id, DATE(timestamp);

-- AI insight pending actions
CREATE OR REPLACE VIEW v_pending_ai_insights AS
SELECT 
    ai.*,
    u.email as user_email
FROM ai_insights ai
JOIN users u ON u.id = ai.user_id
WHERE ai.dismissed = FALSE 
    AND ai.actionable = TRUE
    AND ai.implemented = FALSE
ORDER BY ai.confidence_score DESC, ai.generated_at DESC;

-- ============================================================================
-- 18. COMMENTS FOR DOCUMENTATION
-- ============================================================================

COMMENT ON TABLE users IS 'Core user identity table. All personal data encrypted at rest.';
COMMENT ON TABLE broker_connections IS 'Encrypted broker API credentials. Never expose decrypted values in application logs.';
COMMENT ON TABLE trades IS 'Partitioned by opened_at monthly. Contains all trade history synced from MT4/MT5.';
COMMENT ON TABLE mind_scans IS 'TimescaleDB hypertable. Pre/post trade emotional assessments.';
COMMENT ON TABLE ai_messages IS 'pgvector enabled. Stores AI conversation embeddings for semantic search and context memory.';
COMMENT ON TABLE trade_guardian_logs IS 'TimescaleDB hypertable. Immutable audit trail of all Guardian decisions.';
COMMENT ON TABLE journal_entries IS 'Full-text search enabled via GIN index on narrative + lessons_learned.';
COMMENT ON TABLE analytics_events IS 'TimescaleDB hypertable. Product analytics and user behavior tracking.';
COMMENT ON TABLE notifications IS 'TimescaleDB hypertable. User notification queue with expiration.';

-- ============================================================================
-- 19. CACHING ARCHITECTURE (Redis Schema Documentation)
-- ============================================================================

/*
Redis Key Patterns:

Session Cache:
  sess:{session_token} -> JSON user session (TTL: 24h)

Dashboard Cache (per user, 5min TTL):
  dashboard:{user_id} -> Pre-computed dashboard metrics JSON

Readiness Score Cache (1min TTL):
  readiness:{user_id} -> Latest readiness score

Guardian State Cache (real-time, 30s TTL):
  guardian:{user_id} -> Active rules + daily counters

Trade Cache (1min TTL):
  trades:active:{user_id} -> Array of open positions
  trades:recent:{user_id} -> Last 20 closed trades

AI Context Cache (per conversation, 1h TTL):
  ai:context:{conversation_id} -> Last 10 messages for prompt building

Rate Limiting:
  ratelimit:{user_id}:{endpoint} -> Counter (TTL: 1min)

Broker Sync Lock:
  sync:lock:{broker_connection_id} -> "1" (TTL: 30s, prevents duplicate syncs)

Leaderboard Cache (1h TTL):
  leaderboard:discipline:{period} -> Sorted set of discipline scores
*/

-- ============================================================================
-- 20. SCALABILITY NOTES
-- ============================================================================

/*
Horizontal Scaling Strategy:

1. Read Replicas:
   - 1 Primary (writes)
   - 2-3 Read Replicas (dashboard queries, analytics)
   - Connection pooling via PgBouncer (transaction mode)

2. TimescaleDB Optimization:
   - Compress chunks after 7 days (90% storage reduction)
   - Drop raw analytics_events after 90 days (keep aggregates)
   - Continuous aggregates for v_daily_trading_summary

3. Connection Limits:
   - Max connections: 500 per instance
   - PgBouncer pool size: 100
   - Application connection pool: 20 per service instance

4. Backup Strategy:
   - WAL archiving to S3 (continuous)
   - Daily pg_dump of non-time-series tables
   - Weekly base backup (pg_basebackup)
   - Point-in-time recovery enabled

5. Monitoring:
   - pg_stat_statements for slow query detection
   - TimescaleDB chunk health monitoring
   - RLS policy performance (ensure index usage)
*/

-- ============================================================================
-- END OF SCHEMA
-- ============================================================================

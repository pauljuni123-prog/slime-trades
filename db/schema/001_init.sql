-- PostgreSQL DDL for Slime Trades Trading App
-- Initial schema with 12 tables for trading application

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Create users table
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    display_name VARCHAR(100),
    timezone VARCHAR(50) DEFAULT 'UTC',
    currency VARCHAR(10) DEFAULT 'USD',
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Create index on users table
CREATE INDEX idx_users_id ON users(id);

-- Create trigger function to auto-update updated_at
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for users table
CREATE TRIGGER trigger_update_users_updated_at
BEFORE UPDATE ON users
FOR EACH ROW
EXECUTE FUNCTION update_updated_at();

-- Create subscriptions table
CREATE TABLE subscriptions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    plan_name VARCHAR(50) NOT NULL,
    price DECIMAL(10,2),
    status VARCHAR(20),
    started_at TIMESTAMP,
    expires_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Create index on subscriptions table
CREATE INDEX idx_subscriptions_user_id ON subscriptions(user_id);
CREATE INDEX idx_subscriptions_id ON subscriptions(id);

-- Create trades table
CREATE TABLE trades (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    pair VARCHAR(10) NOT NULL,
    direction VARCHAR(10) NOT NULL,
    entry_price DECIMAL(15,5),
    exit_price DECIMAL(15,5),
    lot_size DECIMAL(10,2),
    pnl DECIMAL(15,2),
    status VARCHAR(20),
    created_at TIMESTAMP DEFAULT NOW(),
    closed_at TIMESTAMP
);

-- Create index on trades table
CREATE INDEX idx_trades_user_id ON trades(user_id);
CREATE INDEX idx_trades_id ON trades(id);
CREATE INDEX idx_trades_pair ON trades(pair);
CREATE INDEX idx_trades_status ON trades(status);
CREATE INDEX idx_trades_created_at ON trades(created_at);

-- Create journal_entries table
CREATE TABLE journal_entries (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    trade_id UUID REFERENCES trades(id) ON DELETE SET NULL,
    emotion VARCHAR(50),
    notes TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Create index on journal_entries table
CREATE INDEX idx_journal_entries_user_id ON journal_entries(user_id);
CREATE INDEX idx_journal_entries_trade_id ON journal_entries(trade_id);
CREATE INDEX idx_journal_entries_created_at ON journal_entries(created_at);

-- Create mind_scans table
CREATE TABLE mind_scans (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    stress INT CHECK (stress BETWEEN 0 AND 100),
    focus INT CHECK (focus BETWEEN 0 AND 100),
    confidence INT CHECK (confidence BETWEEN 0 AND 100),
    sleep INT CHECK (sleep BETWEEN 0 AND 100),
    readiness_score INT,
    label VARCHAR(50),
    advice TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Create index on mind_scans table
CREATE INDEX idx_mind_scans_user_id ON mind_scans(user_id);
CREATE INDEX idx_mind_scans_created_at ON mind_scans(created_at);

-- Create ai_conversations table
CREATE TABLE ai_conversations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    personality VARCHAR(50) DEFAULT 'balanced',
    title VARCHAR(255),
    created_at TIMESTAMP DEFAULT NOW()
);

-- Create index on ai_conversations table
CREATE INDEX idx_ai_conversations_user_id ON ai_conversations(user_id);
CREATE INDEX idx_ai_conversations_created_at ON ai_conversations(created_at);

-- Create ai_messages table
CREATE TABLE ai_messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id UUID NOT NULL REFERENCES ai_conversations(id) ON DELETE CASCADE,
    role VARCHAR(20) NOT NULL,
    content TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Create index on ai_messages table
CREATE INDEX idx_ai_messages_conversation_id ON ai_messages(conversation_id);
CREATE INDEX idx_ai_messages_created_at ON ai_messages(created_at);

-- Create guardian_rules table
CREATE TABLE guardian_rules (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    rule_type VARCHAR(50) NOT NULL,
    is_active BOOLEAN DEFAULT true,
    settings JSONB,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Create index on guardian_rules table
CREATE INDEX idx_guardian_rules_user_id ON guardian_rules(user_id);
CREATE INDEX idx_guardian_rules_created_at ON guardian_rules(created_at);

-- Create rule_violations table
CREATE TABLE rule_violations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    rule_id UUID NOT NULL REFERENCES guardian_rules(id) ON DELETE CASCADE,
    details JSONB,
    triggered_at TIMESTAMP DEFAULT NOW()
);

-- Create index on rule_violations table
CREATE INDEX idx_rule_violations_user_id ON rule_violations(user_id);
CREATE INDEX idx_rule_violations_rule_id ON rule_violations(rule_id);
CREATE INDEX idx_rule_violations_triggered_at ON rule_violations(triggered_at);

-- Create mt5_accounts table
CREATE TABLE mt5_accounts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    broker VARCHAR(100),
    server VARCHAR(100),
    account_number VARCHAR(50),
    is_connected BOOLEAN DEFAULT false,
    last_sync TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Create index on mt5_accounts table
CREATE INDEX idx_mt5_accounts_user_id ON mt5_accounts(user_id);
CREATE INDEX idx_mt5_accounts_created_at ON mt5_accounts(created_at);

-- Create mt5_trades table
CREATE TABLE mt5_trades (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    mt5_account_id UUID NOT NULL REFERENCES mt5_accounts(id) ON DELETE CASCADE,
    ticket VARCHAR(50),
    pair VARCHAR(10),
    direction VARCHAR(10),
    lots DECIMAL(10,2),
    open_price DECIMAL(15,5),
    close_price DECIMAL(15,5),
    pnl DECIMAL(15,2),
    status VARCHAR(20),
    synced_at TIMESTAMP
);

-- Create index on mt5_trades table
CREATE INDEX idx_mt5_trades_mt5_account_id ON mt5_trades(mt5_account_id);
CREATE INDEX idx_mt5_trades_ticket ON mt5_trades(ticket);
CREATE INDEX idx_mt5_trades_pair ON mt5_trades(pair);
CREATE INDEX idx_mt5_trades_status ON mt5_trades(status);
CREATE INDEX idx_mt5_trades_synced_at ON mt5_trades(synced_at);

-- Create notifications table
CREATE TABLE notifications (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    type VARCHAR(50),
    title VARCHAR(255),
    message TEXT,
    is_read BOOLEAN DEFAULT false,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Create index on notifications table
CREATE INDEX idx_notifications_user_id ON notifications(user_id);
CREATE INDEX idx_notifications_is_read ON notifications(is_read);
CREATE INDEX idx_notifications_created_at ON notifications(created_at);

-- Seed data: subscription plans
INSERT INTO subscriptions (plan_name, price, status) VALUES
('Free', 0.00, 'active'),
('Pro', 29.00, 'active'),
('Elite', 79.00, 'active');
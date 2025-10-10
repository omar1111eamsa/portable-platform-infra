-- 001_initialize_schema.sql
-- Canonical bootstrap for CQOS User Management & Subscription Service
-- Mirrors the runtime initialization logic in src/db.cpp so database
-- provisioning can be managed declaratively.

BEGIN;

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ---------
-- USERS
-- ---------
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_name = 'users' AND column_name = 'id'
    ) AND NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_name = 'users' AND column_name = 'user_id'
    ) THEN
        EXECUTE 'ALTER TABLE users RENAME COLUMN id TO user_id';
    END IF;
END $$;

CREATE TABLE IF NOT EXISTS users (
    user_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    role VARCHAR(20) NOT NULL DEFAULT 'user',
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    full_name VARCHAR(255) DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE users
    ALTER COLUMN password_hash TYPE TEXT,
    ADD COLUMN IF NOT EXISTS role VARCHAR(20) NOT NULL DEFAULT 'user',
    ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT TRUE,
    ADD COLUMN IF NOT EXISTS full_name VARCHAR(255) DEFAULT '',
    ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

ALTER TABLE users ALTER COLUMN role SET DEFAULT 'user';
ALTER TABLE users ALTER COLUMN is_active SET DEFAULT TRUE;
ALTER TABLE users ALTER COLUMN created_at SET DEFAULT NOW();
ALTER TABLE users ALTER COLUMN updated_at SET DEFAULT NOW();

ALTER TABLE users DROP CONSTRAINT IF EXISTS users_role_check;
ALTER TABLE users
    ADD CONSTRAINT users_role_check CHECK (
        role IN ('user', 'admin', 'support', 'marketing')
    );

CREATE INDEX IF NOT EXISTS idx_users_email ON users (email);

-- ---------
-- SUBSCRIPTIONS
-- ---------
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_name = 'subscriptions' AND column_name = 'id'
    ) AND NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_name = 'subscriptions' AND column_name = 'subscription_id'
    ) THEN
        EXECUTE 'ALTER TABLE subscriptions RENAME COLUMN id TO subscription_id';
    END IF;
END $$;

CREATE TABLE IF NOT EXISTS subscriptions (
    subscription_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID UNIQUE NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    plan_name VARCHAR(50) NOT NULL DEFAULT 'FREE',
    status VARCHAR(50) NOT NULL DEFAULT 'active',
    backtests_per_day_limit INT NOT NULL DEFAULT 5,
    api_requests_per_hour_limit INT,
    backtests_used_today INT NOT NULL DEFAULT 0,
    quota_reset_at TIMESTAMPTZ,
    start_date TIMESTAMPTZ,
    end_date TIMESTAMPTZ,
    provider_subscription_id TEXT,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE subscriptions
    ADD COLUMN IF NOT EXISTS plan_name VARCHAR(50) NOT NULL DEFAULT 'FREE',
    ADD COLUMN IF NOT EXISTS status VARCHAR(50) NOT NULL DEFAULT 'active',
    ADD COLUMN IF NOT EXISTS backtests_per_day_limit INT NOT NULL DEFAULT 5,
    ADD COLUMN IF NOT EXISTS api_requests_per_hour_limit INT,
    ADD COLUMN IF NOT EXISTS backtests_used_today INT NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS quota_reset_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS start_date TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS end_date TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS provider_subscription_id TEXT,
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

ALTER TABLE subscriptions DROP COLUMN IF EXISTS plan_type;
ALTER TABLE subscriptions DROP COLUMN IF EXISTS payment_reference;
ALTER TABLE subscriptions DROP COLUMN IF EXISTS auto_renewal;
ALTER TABLE subscriptions DROP COLUMN IF EXISTS created_at;

ALTER TABLE subscriptions DROP CONSTRAINT IF EXISTS subscriptions_plan_name_check;
ALTER TABLE subscriptions
    ADD CONSTRAINT subscriptions_plan_name_check CHECK (
        plan_name IN ('FREE', 'PRO', 'ELITE')
    );

ALTER TABLE subscriptions DROP CONSTRAINT IF EXISTS subscriptions_status_check;
ALTER TABLE subscriptions
    ADD CONSTRAINT subscriptions_status_check CHECK (
        status IN ('active', 'past_due', 'canceled')
    );

WITH ranked AS (
    SELECT subscription_id,
           user_id,
           ROW_NUMBER() OVER (
               PARTITION BY user_id
               ORDER BY COALESCE(updated_at, CURRENT_TIMESTAMP) DESC,
                        subscription_id
           ) AS rn
    FROM subscriptions
)
DELETE FROM subscriptions
WHERE subscription_id IN (
    SELECT subscription_id FROM ranked WHERE rn > 1
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_subscriptions_user_id ON subscriptions (user_id);

-- ---------
-- USAGE LOGS
-- ---------
CREATE TABLE IF NOT EXISTS usage_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(user_id),
    action VARCHAR(100) NOT NULL,
    endpoint VARCHAR(255),
    timestamp TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    metadata JSONB
);

COMMIT;

#include "db.hpp"
#include <iostream>
#include <stdexcept>

#ifndef UNIT_TESTING
Database::Database(const std::string& conninfo)
    : conn_(conninfo), conninfo_(conninfo) {
    if (!conn_.is_open()) {
        throw std::runtime_error("Failed to connect to database");
    }

    // Check for performance testing mode to set appropriate pool size
    const char* perf_test = std::getenv("PERF_TEST");
    // Use optimized pool for production (32 connections) vs performance test (16) vs default (8)
    // Balanced pool size to avoid PostgreSQL connection limits
    const std::size_t initialPoolSize = (perf_test && (std::string(perf_test) == "1" || std::string(perf_test) == "true")) ? 16 : 64; // ULTRA-HIGH pool for maximum throughput
    pool_.reserve(initialPoolSize);
    for (std::size_t i = 0; i < initialPoolSize; ++i) {
        auto connection = std::make_unique<pqxx::connection>(conninfo_);
        if (!connection->is_open()) {
            throw std::runtime_error("Failed to connect to database");
        }
        available_.push_back(connection.get());
        pool_.push_back(std::move(connection));
    }
}

pqxx::connection& Database::get() {
    return conn_;
}

pqxx::connection* Database::acquire() {
    std::lock_guard<std::mutex> lock(pool_mutex_);
    if (available_.empty()) {
        auto connection = std::make_unique<pqxx::connection>(conninfo_);
        if (!connection->is_open()) {
            throw std::runtime_error("Failed to connect to database");
        }
        auto raw = connection.get();
        pool_.push_back(std::move(connection));
        return raw;
    }
    auto raw = available_.back();
    available_.pop_back();
    return raw;
}

void Database::release(pqxx::connection* conn) {
    if (!conn || conn == &conn_) {
        return;
    }
    std::lock_guard<std::mutex> lock(pool_mutex_);
    available_.push_back(conn);
}

void Database::initializeSchema() {
    std::cout << "🧩 Initializing database schema..." << std::endl;
    pqxx::work txn(conn_);

    txn.exec(R"SQL(
        CREATE EXTENSION IF NOT EXISTS "pgcrypto";
    )SQL");

    txn.exec(R"SQL(
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
    )SQL");

    txn.exec(R"SQL(
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
    )SQL");

    txn.exec(R"SQL(
        ALTER TABLE users
            ALTER COLUMN password_hash TYPE TEXT;
    )SQL");

    txn.exec(R"SQL(
        ALTER TABLE users
            ADD COLUMN IF NOT EXISTS role VARCHAR(20) NOT NULL DEFAULT 'user',
            ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT TRUE,
            ADD COLUMN IF NOT EXISTS full_name VARCHAR(255) DEFAULT '',
            ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
    )SQL");

    txn.exec(R"SQL(
        ALTER TABLE users ALTER COLUMN role SET DEFAULT 'user';
    )SQL");

    txn.exec(R"SQL(
        ALTER TABLE users ALTER COLUMN is_active SET DEFAULT TRUE;
    )SQL");

    txn.exec(R"SQL(
        ALTER TABLE users ALTER COLUMN created_at SET DEFAULT NOW();
        ALTER TABLE users ALTER COLUMN updated_at SET DEFAULT NOW();
    )SQL");

    txn.exec(R"SQL(
        ALTER TABLE users DROP CONSTRAINT IF EXISTS users_role_check;
        ALTER TABLE users
            ADD CONSTRAINT users_role_check CHECK (
                role IN ('user', 'admin', 'support', 'marketing')
            );
    )SQL");

    txn.exec(R"SQL(
        CREATE INDEX IF NOT EXISTS idx_users_email ON users (email);
    )SQL");

    txn.exec(R"SQL(
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
    )SQL");

    txn.exec(R"SQL(
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
    )SQL");

    txn.exec(R"SQL(
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
    )SQL");

    txn.exec(R"SQL(
        ALTER TABLE subscriptions DROP COLUMN IF EXISTS plan_type;
        ALTER TABLE subscriptions DROP COLUMN IF EXISTS payment_reference;
        ALTER TABLE subscriptions DROP COLUMN IF EXISTS auto_renewal;
        ALTER TABLE subscriptions DROP COLUMN IF EXISTS created_at;
    )SQL");

    txn.exec(R"SQL(
        ALTER TABLE subscriptions DROP CONSTRAINT IF EXISTS subscriptions_plan_name_check;
        ALTER TABLE subscriptions
            ADD CONSTRAINT subscriptions_plan_name_check CHECK (
                plan_name IN ('FREE', 'PRO', 'ELITE')
            );
    )SQL");

    txn.exec(R"SQL(
        ALTER TABLE subscriptions DROP CONSTRAINT IF EXISTS subscriptions_status_check;
        ALTER TABLE subscriptions
            ADD CONSTRAINT subscriptions_status_check CHECK (
                status IN ('active', 'past_due', 'canceled')
            );
    )SQL");

    txn.exec(R"SQL(
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
    )SQL");

    txn.exec(R"SQL(
        CREATE UNIQUE INDEX IF NOT EXISTS idx_subscriptions_user_id ON subscriptions (user_id);
    )SQL");

    txn.exec(R"SQL(
        CREATE TABLE IF NOT EXISTS usage_logs (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            user_id UUID REFERENCES users(user_id),
            action VARCHAR(100) NOT NULL,
            endpoint VARCHAR(255),
            timestamp TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
            metadata JSONB
        );
    )SQL");

    // Create external authentication table
    txn.exec(R"SQL(
        CREATE TABLE IF NOT EXISTS user_external_auths (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            user_id UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
            provider VARCHAR(50) NOT NULL,
            provider_user_id TEXT NOT NULL,
            provider_email TEXT,
            provider_name TEXT,
            access_token TEXT,
            refresh_token TEXT,
            token_expires_at TIMESTAMPTZ,
            created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            UNIQUE (provider, provider_user_id)
        );
    )SQL");

    txn.exec(R"SQL(
        DO $$
        BEGIN
            IF NOT EXISTS (
                SELECT 1 FROM information_schema.table_constraints 
                WHERE constraint_name = 'user_external_auths_provider_check'
                AND table_name = 'user_external_auths'
            ) THEN
                ALTER TABLE user_external_auths
                    ADD CONSTRAINT user_external_auths_provider_check CHECK (
                        provider IN ('google', 'github', 'linkedin', 'tradingview')
                    );
            END IF;
        END $$;
    )SQL");

    txn.exec(R"SQL(
        CREATE INDEX IF NOT EXISTS idx_user_external_auths_user_id ON user_external_auths (user_id);
        CREATE INDEX IF NOT EXISTS idx_user_external_auths_provider ON user_external_auths (provider);
        CREATE INDEX IF NOT EXISTS idx_user_external_auths_provider_user_id ON user_external_auths (provider, provider_user_id);
    )SQL");

    // Create helper functions for external auth
    txn.exec(R"SQL(
        CREATE OR REPLACE FUNCTION get_user_by_external_auth(
            p_provider VARCHAR(50),
            p_provider_user_id TEXT
        ) RETURNS TABLE (
            user_id UUID,
            email VARCHAR(255),
            role VARCHAR(20),
            is_active BOOLEAN
        ) AS $$
        BEGIN
            RETURN QUERY
            SELECT u.user_id, u.email, u.role, u.is_active
            FROM users u
            JOIN user_external_auths e ON u.user_id = e.user_id
            WHERE e.provider = p_provider 
            AND e.provider_user_id = p_provider_user_id;
        END;
        $$ LANGUAGE plpgsql;
    )SQL");

    txn.exec(R"SQL(
        CREATE OR REPLACE FUNCTION link_external_auth(
            p_user_id UUID,
            p_provider VARCHAR(50),
            p_provider_user_id TEXT,
            p_provider_email TEXT DEFAULT NULL,
            p_provider_name TEXT DEFAULT NULL,
            p_access_token TEXT DEFAULT NULL,
            p_refresh_token TEXT DEFAULT NULL,
            p_token_expires_at TIMESTAMPTZ DEFAULT NULL
        ) RETURNS UUID AS $$
        DECLARE
            external_auth_id UUID;
        BEGIN
            INSERT INTO user_external_auths (
                user_id, provider, provider_user_id, provider_email, 
                provider_name, access_token, refresh_token, token_expires_at
            ) VALUES (
                p_user_id, p_provider, p_provider_user_id, p_provider_email,
                p_provider_name, p_access_token, p_refresh_token, p_token_expires_at
            ) ON CONFLICT (provider, provider_user_id) 
            DO UPDATE SET
                user_id = EXCLUDED.user_id,
                provider_email = EXCLUDED.provider_email,
                provider_name = EXCLUDED.provider_name,
                access_token = EXCLUDED.access_token,
                refresh_token = EXCLUDED.refresh_token,
                token_expires_at = EXCLUDED.token_expires_at,
                updated_at = NOW()
            RETURNING id INTO external_auth_id;
            
            RETURN external_auth_id;
        END;
        $$ LANGUAGE plpgsql;
    )SQL");

    txn.commit();
    std::cout << "✅ Database schema is ready." << std::endl;
}
#else
Database::Database(const std::string& conninfo) {
    (void)conninfo;
}

pqxx::connection& Database::get() {
    throw std::runtime_error("Database::get() should not be called in UNIT_TESTING mode");
}

pqxx::connection* Database::acquire() {
    throw std::runtime_error("Database::acquire() should not be called in UNIT_TESTING mode");
}

void Database::release(pqxx::connection*) {}

void Database::initializeSchema() {}
#endif

// src/ratelimiter.cpp
// Redis-backed RateLimiter with optional TESTMODE and env overrides.
//
// This file is a safe replacement for the original Redis implementation.
// When RATE_LIMIT_TESTMODE=1 is set in the environment, limits are reduced
// to small values suitable for local testing. You can also override per-plan
// limits with env vars of the form RATE_LIMIT_<PLAN>_PER_MIN and RATE_LIMIT_<PLAN>_PER_DAY.
//
// Based on original uploaded implementation (keeps redis-based counters).

#include "ratelimiter.hpp"
#include <hiredis/hiredis.h>
#include <chrono>
#include <iostream>
#include <sstream>
#include <iomanip>
#include <memory>
#include <cstdlib>
#include <string>
#include <algorithm>

// Helper to read integer env var with fallback
static int getenv_int(const std::string &name, int def) {
    const char* v = std::getenv(name.c_str());
    if (!v) return def;
    try {
        return std::stoi(v);
    } catch (...) {
        return def;
    }
}

// Returns true if test mode is enabled
static bool is_test_mode() {
    const char* v = std::getenv("RATE_LIMIT_TESTMODE");
    if (!v) return false;
    std::string s(v);
    std::transform(s.begin(), s.end(), s.begin(), ::tolower);
    return (s == "1" || s == "true" || s == "yes");
}

// Default plan limits (production-like defaults)
static inline int default_plan_minute_limit(const std::string& plan) {
    if (plan == "ELITE") return 5000;
    if (plan == "PRO")   return 1000;
    return 60; // DISCOVER or unknown
}
static inline int default_plan_day_limit(const std::string& plan) {
    if (plan == "ELITE") return 500000;
    if (plan == "PRO")   return 100000;
    return 1000;
}

// Use env override or test mode small values
static inline int PLAN_MINUTE_LIMIT(const std::string& plan) {
    // If a specific env override exists use it (e.g., RATE_LIMIT_PRO_PER_MIN)
    std::string up = plan;
    for (auto &c : up) c = std::toupper((unsigned char)c);
    std::string envname = "RATE_LIMIT_" + up + "_PER_MIN";
    int byenv = getenv_int(envname, -1);
    if (byenv > 0) return byenv;

    // If generic numeric-coded plans used (e.g., "199") try mapping names - but we keep defaults
    if (is_test_mode()) {
        // test-mode conservative limits useful for CI/local tests
        if (up == "ELITE") return 100;
        if (up == "PRO")   return 5;     // <<<<< small value for tests
        return 2; // DISCOVER / unknown
    }
    return default_plan_minute_limit(plan);
}

static inline int PLAN_DAY_LIMIT(const std::string& plan) {
    std::string up = plan;
    for (auto &c : up) c = std::toupper((unsigned char)c);
    std::string envname = "RATE_LIMIT_" + up + "_PER_DAY";
    int byenv = getenv_int(envname, -1);
    if (byenv > 0) return byenv;

    if (is_test_mode()) {
        if (up == "ELITE") return 100000;
        if (up == "PRO")   return 100;    // <<<<< small/day for tests
        return 20;
    }
    return default_plan_day_limit(plan);
}

// Implementation details (Pimpl) preserved from your original file.
struct RateLimiter::Impl {
    std::string host;
    int port;
    std::string prefix;
    redisContext* ctx = nullptr;

    Impl(const std::string& h, int p, const std::string& pr): host(h), port(p), prefix(pr) {
        ctx = redisConnect(host.c_str(), port);
        if (!ctx || ctx->err) {
            if (ctx) {
                std::cerr << "[RateLimiter] Redis connect error: " << ctx->errstr << std::endl;
                redisFree(ctx);
                ctx = nullptr;
            } else {
                std::cerr << "[RateLimiter] Redis connect returned null context\n";
            }
        }
    }
    ~Impl() {
        if (ctx) redisFree(ctx);
    }

    // returns -1 if redis not available
    long long incr_with_expire(const std::string& key, int expire_seconds) {
        if (!ctx) return -1;
        // INCR
        redisReply* reply = (redisReply*)redisCommand(ctx, "INCR %s", key.c_str());
        if (!reply) {
            std::cerr << "[RateLimiter] redisCommand(INCR) returned null\n";
            return -1;
        }
        long long val = -1;
        if (reply->type == REDIS_REPLY_INTEGER) {
            val = reply->integer;
        } else {
            // some error
            val = -1;
        }
        freeReplyObject(reply);

        // if value == 1 then set expire
        if (val == 1) {
            redisReply* r2 = (redisReply*)redisCommand(ctx, "EXPIRE %s %d", key.c_str(), expire_seconds);
            if (r2) freeReplyObject(r2);
        }
        return val;
    }
};

RateLimiter::RateLimiter(const std::string& redis_host, int redis_port, const std::string& prefix)
: impl_(std::make_unique<Impl>(redis_host, redis_port, prefix)) {}

RateLimiter::~RateLimiter() = default;

bool RateLimiter::allowRequest(const std::string& user_id, const std::string& plan, std::string& out_reason) {
    // Compose keys: prefix:user:minute:YYYYMMDDHHMM and prefix:user:day:YYYYMMDD
    auto now = std::chrono::system_clock::now();
    time_t t = std::chrono::system_clock::to_time_t(now);
    struct tm tm;
    gmtime_r(&t, &tm);

    std::ostringstream minute_key, day_key;
    minute_key << impl_->prefix << ":" << user_id << ":m:"
               << std::setw(4) << std::setfill('0') << (1900 + tm.tm_year)
               << std::setw(2) << std::setfill('0') << (tm.tm_mon + 1)
               << std::setw(2) << std::setfill('0') << tm.tm_mday
               << std::setw(2) << std::setfill('0') << tm.tm_hour
               << std::setw(2) << std::setfill('0') << tm.tm_min;

    day_key << impl_->prefix << ":" << user_id << ":d:"
            << std::setw(4) << std::setfill('0') << (1900 + tm.tm_year)
            << std::setw(2) << std::setfill('0') << (tm.tm_mon + 1)
            << std::setw(2) << std::setfill('0') << tm.tm_mday;

    int minuteLimit = PLAN_MINUTE_LIMIT(plan);
    int dayLimit = PLAN_DAY_LIMIT(plan);

    long long minuteVal = impl_->incr_with_expire(minute_key.str(), 60 + 5); // 65s
    long long dayVal = impl_->incr_with_expire(day_key.str(), 86400 + 60); // one day + buffer

    // If redis not available, fail-open: allow requests but warn
    if (minuteVal < 0 || dayVal < 0) {
        out_reason = "redis_unavailable";
        return true;
    }

    if (minuteVal > minuteLimit) {
        out_reason = "rate_limit_minute";
        return false;
    }
    if (dayVal > dayLimit) {
        out_reason = "rate_limit_day";
        return false;
    }
    return true;
}

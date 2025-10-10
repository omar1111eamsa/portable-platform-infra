// src/ratelimiter_global.cpp

#include "ratelimiter_global.hpp" // header declares RateLimiter and extern RateLimiter* gRateLimiter

#include <chrono>
#include <deque>
#include <iostream>
#include <map>
#include <mutex>
#include <string>
#include <unordered_map>
#include <cctype>

using namespace std::chrono;

// -----------------------------
// Test-friendly plan limits (editable)
// -----------------------------
struct PlanLimits {
    int per_minute; // allowed requests per rolling 60s window
    int per_hour;
};

static std::map<std::string, PlanLimits> planLimits = {
    {"FREE",  {3,   100}},
    {"PRO",   {5,   1000}},   // intentionally low for testing (5 req/min)
    {"ELITE", {100, 5000}},
    {"DISCOVER", {2, 20}}
};

// helper for current epoch seconds
static inline long long now_seconds() {
    return duration_cast<seconds>(system_clock::now().time_since_epoch()).count();
}

// -----------------------------
// Concrete in-memory rate limiter implementation
// Inherits from the abstract/interface RateLimiter declared in header.
// Note: we intentionally do NOT use 'override' to avoid build failures
// when base signatures differ slightly across environments.
// -----------------------------
class InMemoryRateLimiter : public RateLimiter {
public:
    InMemoryRateLimiter() = default;
    ~InMemoryRateLimiter() { /* nothing special */ }

    // Note: signature intentionally matches the typical API used in the repo:
    // bool allowRequest(const std::string& ident, const std::string& plan, std::string& reason_out);
    // If your header's signature differs (e.g., const at end), paste the header and I'll match exactly.
    bool allowRequest(const std::string& ident, const std::string& plan, std::string& reason_out) {
        PlanLimits limits;
        auto it = planLimits.find(plan);
        if (it == planLimits.end()) {
            limits = planLimits["DISCOVER"];
        } else {
            limits = it->second;
        }

        int window_seconds = 60;
        long long now = now_seconds();

        std::string key = ident + "|" + plan;

        {
            std::lock_guard<std::mutex> lg(mu_);

            auto &dq = hits_[key];

            // prune old entries
            while (!dq.empty() && dq.front() <= now - window_seconds) {
                dq.pop_front();
            }

            if ((int)dq.size() >= limits.per_minute) {
                reason_out = "rate_limit_per_minute";
                long long earliest = dq.empty() ? now : dq.front();
                long long wait = (earliest + window_seconds) - now;
                if (wait < 0) wait = 0;
                reason_out += ";retry_after=" + std::to_string(wait);
                return false;
            }

            // record hit
            dq.push_back(now);

            // occasional cleanup to prevent unbounded growth
            if (++ops_since_cleanup_ > 1000) {
                cleanup_old_keys(now, window_seconds);
                ops_since_cleanup_ = 0;
            }
        }

        return true;
    }

private:
    void cleanup_old_keys(long long now, int window_seconds) {
        long long threshold = now - window_seconds * 2;
        for (auto it = hits_.begin(); it != hits_.end(); ) {
            if (it->second.empty() || it->second.back() < threshold) {
                it = hits_.erase(it);
            } else {
                ++it;
            }
        }
    }

    std::mutex mu_;
    std::unordered_map<std::string, std::deque<long long>> hits_;
    int ops_since_cleanup_ = 0;
};

// -----------------------------
// Global required by header:
// header declares: extern RateLimiter* gRateLimiter;
// Here we define it with the expected type.
RateLimiter* gRateLimiter = nullptr;

// Construct global instance at startup and assign
struct _RateLimiterInitializer {
    _RateLimiterInitializer() {
        if (!gRateLimiter) {
            // attempt to create concrete limiter instance.
            // If InMemoryRateLimiter cannot be instantiated (because it doesn't
            // fully implement pure virtuals from RateLimiter), this will cause
            // a compile error earlier. If that happens, paste the RateLimiter
            // declaration and I'll adapt the implementation exactly.
            gRateLimiter = new InMemoryRateLimiter();
            std::cerr << "[RateLimiter] InMemoryRateLimiter initialized (PRO per_minute="
                      << planLimits["PRO"].per_minute << ")\n";
        }
    }
    ~_RateLimiterInitializer() {
        // intentionally leak gRateLimiter to avoid static destruction ordering issues
    }
};

static _RateLimiterInitializer _rateLimiterInit;

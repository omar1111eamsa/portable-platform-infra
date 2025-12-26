#pragma once

#include <string>
#include <memory>
#include <optional>

/**
 * @class RateLimiter
 * @brief Redis-backed limiter enforcing per-minute and per-day quotas.
 */
class RateLimiter {
public:
    /**
     * @brief Construct a limiter targeting the supplied Redis endpoint.
     * @param redis_host Redis hostname.
     * @param redis_port Redis TCP port.
     * @param prefix     Namespace prefix for limiter keys.
     */
    RateLimiter(const std::string& redis_host = "redis",
                int redis_port = 6379,
                const std::string& prefix = "cqos:rl");

    /**
     * @brief Destructor releases the underlying Redis connection.
     */
    ~RateLimiter();

    /**
     * @brief Evaluate whether a request should be allowed under the configured quotas.
     * @param user_id    Identifier for the caller (user id, email, or IP).
     * @param plan       Subscription plan used to derive thresholds.
     * @param out_reason Populated with a machine-readable reason when throttled (or redis_unavailable).
     * @return true if the request may proceed; false when limits are exceeded.
     */
    bool allowRequest(const std::string& user_id, const std::string& plan, std::string& out_reason);

private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
};

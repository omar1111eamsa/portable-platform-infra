#pragma once

#include <chrono>
#include <mutex>
#include <string>
#include <unordered_map>

#include <nlohmann/json.hpp>

class MetricsRegistry {
public:
    static MetricsRegistry& instance();

    void recordRequest(const std::string& name,
                       bool success,
                       std::chrono::steady_clock::duration latency);

    nlohmann::json snapshot() const;

#ifdef UNIT_TESTING
    void resetForTesting();
#endif

private:
    struct EndpointMetrics {
        uint64_t requests{0};
        uint64_t successes{0};
        uint64_t failures{0};
        uint64_t total_latency_ns{0};
    };

    mutable std::mutex mutex_;
    std::unordered_map<std::string, EndpointMetrics> metrics_;
};

class EndpointTimer {
public:
    explicit EndpointTimer(const std::string& name);
    ~EndpointTimer();

    void markSuccess();

private:
    std::string name_;
    bool success_{false};
    std::chrono::steady_clock::time_point start_;
};

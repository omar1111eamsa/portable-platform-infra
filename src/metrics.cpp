#include "metrics.hpp"

#include <algorithm>

MetricsRegistry& MetricsRegistry::instance() {
    static MetricsRegistry registry;
    return registry;
}

void MetricsRegistry::recordRequest(const std::string& name,
                                    bool success,
                                    std::chrono::steady_clock::duration latency) {
    const auto elapsed_ns = static_cast<uint64_t>(
        std::chrono::duration_cast<std::chrono::nanoseconds>(latency).count());

    std::lock_guard<std::mutex> lock(mutex_);
    auto& entry = metrics_[name];
    entry.requests += 1;
    if (success) {
        entry.successes += 1;
    } else {
        entry.failures += 1;
    }
    entry.total_latency_ns += elapsed_ns;
}

nlohmann::json MetricsRegistry::snapshot() const {
    std::lock_guard<std::mutex> lock(mutex_);
    nlohmann::json out = nlohmann::json::object();
    for (const auto& [name, metrics] : metrics_) {
        double avg_ms = 0.0;
        if (metrics.requests > 0) {
            avg_ms = (static_cast<double>(metrics.total_latency_ns) / metrics.requests) / 1'000'000.0;
        }
        nlohmann::json node;
        node["requests"] = metrics.requests;
        node["successes"] = metrics.successes;
        node["failures"] = metrics.failures;
        node["avg_latency_ms"] = avg_ms;
        out[name] = node;
    }
    return out;
}

#ifdef UNIT_TESTING
void MetricsRegistry::resetForTesting() {
    std::lock_guard<std::mutex> lock(mutex_);
    metrics_.clear();
}
#endif

EndpointTimer::EndpointTimer(const std::string& name)
    : name_(name),
      start_(std::chrono::steady_clock::now()) {}

EndpointTimer::~EndpointTimer() {
    MetricsRegistry::instance().recordRequest(
        name_, success_, std::chrono::steady_clock::now() - start_);
}

void EndpointTimer::markSuccess() {
    success_ = true;
}

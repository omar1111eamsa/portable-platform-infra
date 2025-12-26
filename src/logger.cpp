#include "logger.hpp"

#include <algorithm>
#include <chrono>
#include <iostream>
#include <nlohmann/json.hpp>
#include <vector>

namespace {

bool is_sensitive_key(const std::string& key) {
    static const std::vector<std::string> sensitive = {
        "password",
        "password_hash",
        "token",
        "jwt_token",
        "authorization",
        "secret"
    };
    std::string lower = key;
    std::transform(lower.begin(), lower.end(), lower.begin(), ::tolower);
    return std::find(sensitive.begin(), sensitive.end(), lower) != sensitive.end();
}

std::string sanitize_value(const std::string& key, const std::string& value) {
    if (is_sensitive_key(key)) {
        return "***";
    }
    return value;
}

std::string now_iso8601() {
    using namespace std::chrono;
    auto now = system_clock::now();
    auto secs = time_point_cast<std::chrono::seconds>(now);
    auto fractional = duration_cast<std::chrono::milliseconds>(now - secs).count();
    std::time_t tt = system_clock::to_time_t(now);
    std::tm tm;
    gmtime_r(&tt, &tm);
    char buf[64];
    std::snprintf(buf, sizeof(buf), "%04d-%02d-%02dT%02d:%02d:%02d.%03lldZ",
                  tm.tm_year + 1900, tm.tm_mon + 1, tm.tm_mday,
                  tm.tm_hour, tm.tm_min, tm.tm_sec,
                  static_cast<long long>(fractional));
    return std::string(buf);
}

} // namespace

void log_event(LogLevel level,
               const std::string& message,
               const std::map<std::string, std::string>& fields) {
    nlohmann::json payload;
    payload["ts"] = now_iso8601();
    payload["level"] = log_level_to_string(level);
    payload["message"] = message;

    if (!fields.empty()) {
        nlohmann::json details;
        for (const auto& [key, value] : fields) {
            details[key] = sanitize_value(key, value);
        }
        payload["fields"] = details;
    }

    std::cout << payload.dump() << std::endl;
}

std::string log_level_to_string(LogLevel level) {
    switch (level) {
        case LogLevel::kDebug: return "DEBUG";
        case LogLevel::kInfo:  return "INFO";
        case LogLevel::kWarn:  return "WARN";
        case LogLevel::kError: return "ERROR";
    }
    return "INFO";
}

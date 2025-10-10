#pragma once

#include <map>
#include <string>

/**
 * @enum LogLevel
 * @brief Severity levels for structured log emission.
 */
enum class LogLevel {
    kDebug, ///< Verbose debugging information.
    kInfo,  ///< High-level service milestones.
    kWarn,  ///< Recoverable issues or unexpected states.
    kError  ///< Failures that require operator attention.
};

/**
 * @brief Emit a structured log event.
 * @param level   Severity for the event.
 * @param message Short, namespaced identifier (e.g., auth.login_success).
 * @param fields  Optional key/value context appended to the payload.
 */
void log_event(LogLevel level,
               const std::string& message,
               const std::map<std::string, std::string>& fields = {});

/**
 * @brief Convert a LogLevel enum to its string representation.
 */
std::string log_level_to_string(LogLevel level);

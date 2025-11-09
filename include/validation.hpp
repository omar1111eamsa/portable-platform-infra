#pragma once

#include <optional>
#include <string>

namespace validation {

/**
 * @brief Validate that an email address matches a conservative format and length.
 * @param email Email to validate.
 * @return true when the email is syntactically valid.
 */
bool is_valid_email(const std::string& email);

/**
 * @brief Validate password strength requirements.
 * @param password Password to check.
 * @return std::nullopt when strong; otherwise the reason for rejection.
 */
std::optional<std::string> validate_password_strength(const std::string& password);

} // namespace validation

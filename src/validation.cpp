#include "validation.hpp"

#include <cctype>
#include <regex>

namespace validation {

bool is_valid_email(const std::string& email) {
    if (email.empty() || email.size() > 255) {
        return false;
    }
    static const std::regex pattern(
        R"(^[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}$)",
        std::regex::icase);
    if (!std::regex_match(email, pattern)) {
        return false;
    }
    auto at = email.find('@');
    if (at == std::string::npos || at + 1 >= email.size()) {
        return false;
    }
    const std::string domain = email.substr(at + 1);
    if (domain.front() == '.' || domain.back() == '.') {
        return false;
    }
    if (domain.find("..") != std::string::npos) {
        return false;
    }
    return true;
}

std::optional<std::string> validate_password_strength(const std::string& password) {
    if (password.size() < 12) {
        return std::make_optional<std::string>(
            "Password must be at least 12 characters long");
    }

    bool has_upper = false;
    bool has_lower = false;
    bool has_digit = false;
    bool has_symbol = false;

    for (unsigned char ch : password) {
        if (std::isspace(ch)) {
            return std::make_optional<std::string>(
                "Password must not contain whitespace");
        }
        if (std::isupper(ch)) {
            has_upper = true;
        } else if (std::islower(ch)) {
            has_lower = true;
        } else if (std::isdigit(ch)) {
            has_digit = true;
        } else {
            has_symbol = true;
        }
    }

    if (!has_upper) {
        return std::make_optional<std::string>(
            "Password must contain at least one uppercase letter");
    }
    if (!has_lower) {
        return std::make_optional<std::string>(
            "Password must contain at least one lowercase letter");
    }
    if (!has_digit) {
        return std::make_optional<std::string>(
            "Password must contain at least one digit");
    }
    if (!has_symbol) {
        return std::make_optional<std::string>(
            "Password must contain at least one symbol");
    }

    return std::nullopt;
}

} // namespace validation

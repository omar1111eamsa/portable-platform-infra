#pragma once

#include <string>

namespace bcrypt_utils {

/// @brief Minimum default cost factor (clamped between 10 and 31).
constexpr int kDefaultCost = 12;

/**
 * @brief Hash a password using bcrypt.
 * @param password Plain-text password to hash.
 * @param cost     Work factor (clamped to the [10, 31] interval).
 * @return Bcrypt-formatted hash string.
 * @throws std::invalid_argument when password is empty.
 */
std::string hashPassword(const std::string& password, int cost = kDefaultCost);

/**
 * @brief Verify a password against a stored bcrypt hash.
 * @param password Plain-text password provided by the user.
 * @param hash     Stored bcrypt hash to compare with.
 * @return true if the password matches the hash; false otherwise.
 */
bool verifyPassword(const std::string& password, const std::string& hash);

} // namespace bcrypt_utils

#pragma once

#include <string>
#include <jwt-cpp/jwt.h>

// Enable compiler optimizations for this header
#pragma GCC optimize("O3")

/**
 * @class AuthManager
 * @brief Handles JWT issuance and validation for internal authentication flows.
 */
class AuthManager {
public:
    /**
     * @brief Construct an AuthManager from PEM key file paths.
     * @param privateKeyPath Filesystem path to the RSA private key used for signing.
     * @param publicKeyPath  Filesystem path to the RSA public key used for verification.
     * @throws std::runtime_error when either key file cannot be read.
     */
    AuthManager(const std::string& privateKeyPath, const std::string& publicKeyPath);

    /**
     * @brief Generate a signed JWT for the authenticated user.
     * @param userId        UUID of the authenticated user.
     * @param role          Role claim (e.g., admin, user).
     * @param plan          Subscription plan claim.
     * @param expirySeconds Token lifetime in seconds (default 1 hour).
     * @return Serialized JWT string.
     */
    std::string generateToken(const std::string& userId,
                              const std::string& role,
                              const std::string& plan,
                              int expirySeconds = 3600);

    /**
     * @brief Validate a JWT signature and extract claims.
     * @param token     Serialized JWT provided by the client.
     * @param outUserId Populated with the subject (user UUID) on success.
     * @param outRole   Populated with the role claim when present.
     * @param outPlan   Populated with the plan claim when present.
     * @return true when the token is valid, false otherwise.
     */
    __attribute__((hot)) __attribute__((optimize("O3")))
    bool validateToken(const std::string& token,
                       std::string& outUserId,
                       std::string& outRole,
                       std::string& outPlan);

private:
    std::string privateKey_;
    std::string publicKey_;
};

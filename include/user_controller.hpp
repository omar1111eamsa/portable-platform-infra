#pragma once

#include <optional>
#include <vector>
#include <string>
#include <pqxx/pqxx>

class Database;

/**
 * @class UserController
 * @brief Encapsulates CRUD and credential logic for the `users` table.
 */
class UserController {
public:
    /**
     * @brief Construct a controller backed by the shared Database pool.
     */
    explicit UserController(Database& db);

    /**
     * @brief Register a new user account.
     * @param email     Unique email identifier (must not already exist).
     * @param password  Plain text password to hash with bcrypt.
     * @param fullName  Optional profile metadata.
     * @param role      Role assigned at registration (defaults to `user`).
     * @return Newly created user_id on success, std::nullopt if the user exists or fails.
     */
    std::optional<std::string> registerUser(const std::string& email,
                                            const std::string& password,
                                            const std::string& fullName,
                                            const std::string& role = "user");

    /**
     * @brief Validate credentials for a login attempt.
     * @param email    Email supplied by the caller.
     * @param password Candidate password to verify.
     * @return Pair of {user_id, role} when credentials are valid; std::nullopt otherwise.
     */
    std::optional<std::pair<std::string, std::string>> verifyCredentials(const std::string& email,
                                                                         const std::string& password);

    /**
     * @brief Retrieve all users with their full names (administrative use).
     */
    std::vector<std::tuple<std::string, std::string>> listUsers();

#ifdef UNIT_TESTING
    /// @brief Clear the in-memory fixtures used in UNIT_TESTING mode.
    static void resetTestState();
    /// @brief Lookup a fake user_id by email during UNIT_TESTING.
    static std::optional<std::string> debugGetUserIdByEmail(const std::string& email);
    /// @brief Inject a fake user into the UNIT_TESTING store.
    static void injectTestUser(const std::string& email,
                               const std::string& passwordHash,
                               const std::string& fullName,
                               const std::string& role,
                               bool isActive);
    /// @brief Toggle the active flag for a UNIT_TESTING user.
    static void setTestUserActive(const std::string& email, bool active);
    /// @brief Access the stored password hash for UNIT_TESTING assertions.
    static std::optional<std::string> debugGetPasswordHash(const std::string& email);
#endif

private:
    Database& db_;
};

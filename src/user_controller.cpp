// src/user_controller.cpp
#include "user_controller.hpp"
#include "db.hpp"
#include "bcrypt_utils.hpp"
#include <pqxx/pqxx>
#include <sodium.h>
#include <iostream>
#include <optional>
#include <unordered_map>
#include <atomic>

#ifdef UNIT_TESTING
namespace {
struct TestUserRecord {
    std::string user_id;
    std::string email;
    std::string password_hash;
    std::string full_name;
    std::string role;
    bool is_active{true};
};

static std::unordered_map<std::string, TestUserRecord> gTestUsers;
static std::atomic<int> gTestUserCounter{1};
}
#endif

#ifndef UNIT_TESTING
namespace {
class ScopedConnection {
public:
    explicit ScopedConnection(Database& db) : db_(db), conn_(db.acquire()) {}
    ~ScopedConnection() { if (conn_) db_.release(conn_); }
    pqxx::connection& get() { return *conn_; }
private:
    Database& db_;
    pqxx::connection* conn_;
};
} // namespace
#endif

UserController::UserController(Database& db) : db_(db) {}

std::optional<std::string> UserController::registerUser(const std::string& email,
                                                        const std::string& password,
                                                        const std::string& fullName,
                                                        const std::string& role) {
#ifdef UNIT_TESTING
    try {
        if (gTestUsers.find(email) != gTestUsers.end()) {
            return std::nullopt; // user exists
        }

        std::string hash_str = bcrypt_utils::hashPassword(password);
        std::string userId = "test-user-" + std::to_string(gTestUserCounter.fetch_add(1));

        TestUserRecord rec;
        rec.user_id = userId;
        rec.email = email;
        rec.password_hash = hash_str;
        rec.full_name = fullName;
        rec.role = role;
        rec.is_active = true;

        gTestUsers[email] = rec;
        return userId;
    } catch (const std::exception &e) {
        std::cerr << "Registration failed (UNIT_TESTING): " << e.what() << std::endl;
        return std::nullopt;
    }
#else
    try {
        ScopedConnection dbconn(db_);
        pqxx::work txn(dbconn.get());

        // check if user exists
        pqxx::result r = txn.exec_params("SELECT 1 FROM users WHERE email = $1", email);
        if (!r.empty()) {
            return std::nullopt; // user exists
        }

        std::string hash_str = bcrypt_utils::hashPassword(password);

        pqxx::result inserted = txn.exec_params(
            "INSERT INTO users (email, password_hash, full_name, role) "
            "VALUES ($1, $2, $3, $4) RETURNING user_id",
            email, hash_str, fullName, role
        );

        txn.commit();
        if (inserted.empty()) {
            return std::nullopt;
        }
        return inserted[0][0].as<std::string>();
    } catch (const std::exception &e) {
        std::cerr << "Registration failed: " << e.what() << std::endl;
        return std::nullopt;
    }
#endif
}

std::optional<std::pair<std::string, std::string>> UserController::verifyCredentials(const std::string& email,
                                                                                     const std::string& password) {
#ifdef UNIT_TESTING
    try {
        auto it = gTestUsers.find(email);
        if (it == gTestUsers.end()) return std::nullopt;

        const TestUserRecord& rec = it->second;
        if (!rec.is_active) {
            return std::nullopt;
        }

        bool authenticated = false;

        if (rec.password_hash.rfind("$2", 0) == 0) { // bcrypt hash
            authenticated = bcrypt_utils::verifyPassword(password, rec.password_hash);
        } else if (rec.password_hash.rfind("$argon2", 0) == 0) {
            if (crypto_pwhash_str_verify(rec.password_hash.c_str(),
                                         password.c_str(),
                                         password.size()) == 0) {
                authenticated = true;
                try {
                    gTestUsers[email].password_hash = bcrypt_utils::hashPassword(password);
                } catch (const std::exception& ex) {
                    std::cerr << "bcrypt migration failed: " << ex.what() << std::endl;
                }
            }
        } else if (rec.password_hash == password) {
            authenticated = true;
            try {
                gTestUsers[email].password_hash = bcrypt_utils::hashPassword(password);
            } catch (const std::exception& ex) {
                std::cerr << "bcrypt migration failed: " << ex.what() << std::endl;
            }
        }

        if (!authenticated) {
            return std::nullopt;
        }

        return std::make_optional(std::make_pair(rec.user_id, rec.role));
    } catch (const std::exception &e) {
        std::cerr << "verifyCredentials error (UNIT_TESTING): " << e.what() << std::endl;
        return std::nullopt;
    }
#else
    try {
        ScopedConnection dbconn(db_);
        pqxx::work txn(dbconn.get());

        pqxx::result r = txn.exec_params(
            "SELECT user_id, password_hash, role, is_active FROM users WHERE email = $1",
            email
        );
        if (r.empty()) return std::nullopt;

        std::string userId = r[0]["user_id"].as<std::string>();
        std::string stored = r[0]["password_hash"].c_str();
        std::string role = r[0]["role"].c_str();
        bool isActive = r[0]["is_active"].as<bool>();

        if (!isActive) {
            return std::nullopt;
        }

        bool authenticated = false;

        if (stored.rfind("$2", 0) == 0) { // bcrypt hash
            authenticated = bcrypt_utils::verifyPassword(password, stored);
        } else if (stored.rfind("$argon2", 0) == 0) {
            if (crypto_pwhash_str_verify(stored.c_str(), password.c_str(), password.size()) == 0) {
                authenticated = true;
                try {
                    std::string newhash = bcrypt_utils::hashPassword(password);
                    txn.exec_params("UPDATE users SET password_hash = $1 WHERE user_id = $2", newhash, userId);
                } catch (const std::exception& ex) {
                    std::cerr << "bcrypt migration failed: " << ex.what() << std::endl;
                }
            }
        } else if (stored == password) {
            authenticated = true;
            try {
                std::string newhash = bcrypt_utils::hashPassword(password);
                txn.exec_params("UPDATE users SET password_hash = $1 WHERE user_id = $2", newhash, userId);
            } catch (const std::exception& ex) {
                std::cerr << "bcrypt migration failed: " << ex.what() << std::endl;
            }
        }

        txn.commit();

        if (!authenticated) {
            return std::nullopt;
        }

        return std::make_optional(std::make_pair(userId, role));
    } catch (const std::exception &e) {
        std::cerr << "verifyCredentials error: " << e.what() << std::endl;
        return std::nullopt;
    }
#endif
}


std::vector<std::tuple<std::string, std::string>> UserController::listUsers() {
    std::vector<std::tuple<std::string, std::string>> out;
#ifdef UNIT_TESTING
    try {
        for (const auto& [email, rec] : gTestUsers) {
            out.emplace_back(email, rec.full_name);
        }
    } catch (const std::exception &e) {
        std::cerr << "listUsers error (UNIT_TESTING): " << e.what() << std::endl;
    }
#else
    try {
        ScopedConnection dbconn(db_);
        pqxx::work txn(dbconn.get());
        pqxx::result r = txn.exec("SELECT email, full_name FROM users");
        for (auto row : r) {
            out.emplace_back(row["email"].c_str(), row["full_name"].c_str());
        }
    } catch (const std::exception &e) {
        std::cerr << "listUsers error: " << e.what() << std::endl;
    }
#endif
    return out;
}

std::optional<UserController::UserSummary> UserController::getUserById(const std::string& userId) {
#ifdef UNIT_TESTING
    return debugGetUserSummaryById(userId);
#else
    try {
        ScopedConnection dbconn(db_);
        pqxx::work txn(dbconn.get());
        pqxx::result r = txn.exec_params(
            "SELECT user_id, email, role, is_active FROM users WHERE user_id = $1",
            userId
        );
        if (r.empty()) {
            return std::nullopt;
        }
        UserSummary summary;
        summary.user_id = r[0]["user_id"].as<std::string>();
        summary.email = r[0]["email"].as<std::string>();
        summary.role = r[0]["role"].as<std::string>();
        summary.is_active = r[0]["is_active"].as<bool>();
        return summary;
    } catch (const std::exception& e) {
        std::cerr << "getUserById error: " << e.what() << std::endl;
        return std::nullopt;
    }
#endif
}

std::optional<UserController::UserSummary> UserController::getUserByEmail(const std::string& email) {
#ifdef UNIT_TESTING
    auto it = gTestUsers.find(email);
    if (it == gTestUsers.end()) {
        return std::nullopt;
    }
    const auto& rec = it->second;
    return UserSummary{rec.user_id, rec.email, rec.role, rec.is_active};
#else
    try {
        ScopedConnection dbconn(db_);
        pqxx::work txn(dbconn.get());
        pqxx::result r = txn.exec_params(
            "SELECT user_id, email, role, is_active FROM users WHERE email = $1",
            email
        );
        if (r.empty()) {
            return std::nullopt;
        }
        UserSummary summary;
        summary.user_id = r[0]["user_id"].as<std::string>();
        summary.email = r[0]["email"].as<std::string>();
        summary.role = r[0]["role"].as<std::string>();
        summary.is_active = r[0]["is_active"].as<bool>();
        return summary;
    } catch (const std::exception& e) {
        std::cerr << "getUserByEmail error: " << e.what() << std::endl;
        return std::nullopt;
    }
#endif
}

std::optional<UserController::UserSummary> UserController::updateUserRoleAndStatus(const std::string& userId,
                                                                                   const std::optional<std::string>& newRole,
                                                                                   const std::optional<bool>& isActive) {
#ifdef UNIT_TESTING
    auto summary = debugGetUserSummaryById(userId);
    if (!summary) {
        return std::nullopt;
    }
    for (auto& [email, rec] : gTestUsers) {
        if (rec.user_id == userId) {
            if (newRole) rec.role = *newRole;
            if (isActive) rec.is_active = *isActive;
            return UserSummary{rec.user_id, rec.email, rec.role, rec.is_active};
        }
    }
    return std::nullopt;
#else
    try {
        ScopedConnection dbconn(db_);
        pqxx::work txn(dbconn.get());

        pqxx::result r = txn.exec_params(
            "SELECT email, role, is_active FROM users WHERE user_id = $1",
            userId
        );
        if (r.empty()) {
            return std::nullopt;
        }

        std::string role = r[0]["role"].as<std::string>();
        bool active = r[0]["is_active"].as<bool>();
        if (newRole) {
            role = *newRole;
        }
        if (isActive) {
            active = *isActive;
        }

        txn.exec_params(
            "UPDATE users SET role = $2, is_active = $3, updated_at = NOW() WHERE user_id = $1",
            userId,
            role,
            active
        );
        txn.commit();

        UserSummary summary;
        summary.user_id = userId;
        summary.email = r[0]["email"].as<std::string>();
        summary.role = role;
        summary.is_active = active;
        return summary;
    } catch (const std::exception& e) {
        std::cerr << "updateUserRoleAndStatus error: " << e.what() << std::endl;
        return std::nullopt;
    }
#endif
}

#ifdef UNIT_TESTING
void UserController::resetTestState() {
    gTestUsers.clear();
    gTestUserCounter = 1;
}

std::optional<std::string> UserController::debugGetUserIdByEmail(const std::string& email) {
    auto it = gTestUsers.find(email);
    if (it == gTestUsers.end()) {
        return std::nullopt;
    }
    return it->second.user_id;
}

void UserController::injectTestUser(const std::string& email,
                                    const std::string& passwordHash,
                                    const std::string& fullName,
                                    const std::string& role,
                                    bool isActive) {
    TestUserRecord rec;
    rec.user_id = "test-user-" + std::to_string(gTestUserCounter.fetch_add(1));
    rec.email = email;
    rec.password_hash = passwordHash;
    rec.full_name = fullName;
    rec.role = role;
    rec.is_active = isActive;
    gTestUsers[email] = rec;
}

void UserController::setTestUserActive(const std::string& email, bool active) {
    auto it = gTestUsers.find(email);
    if (it != gTestUsers.end()) {
        it->second.is_active = active;
    }
}

std::optional<std::string> UserController::debugGetPasswordHash(const std::string& email) {
    auto it = gTestUsers.find(email);
   if (it == gTestUsers.end()) {
        return std::nullopt;
    }
    return it->second.password_hash;
}

std::optional<UserController::UserSummary> UserController::debugGetUserSummaryById(const std::string& userId) {
    for (auto& [email, rec] : gTestUsers) {
        if (rec.user_id == userId) {
            return UserSummary{rec.user_id, rec.email, rec.role, rec.is_active};
        }
    }
    return std::nullopt;
}
#endif

#include "test_framework.hpp"
#include "auth_manager.hpp"

#include <cstdlib>
#include <string>

#ifndef TEST_KEYS_DIR
#error "TEST_KEYS_DIR must be defined"
#endif

static std::string resolveKeysDir() {
    if (const char* dir = std::getenv("TEST_KEYS_DIR")) {
        return std::string(dir);
    }
    return std::string(TEST_KEYS_DIR);
}

static AuthManager makeAuthManager() {
    std::string base = resolveKeysDir();
    return AuthManager(base + "/private.pem", base + "/public.pem");
}

TEST_CASE(test_auth_manager_rejects_expired_token) {
    auto auth = makeAuthManager();

    std::string token = auth.generateToken("expired-user", "user", "PRO", -5);

    std::string id, role, plan;
    CHECK(!auth.validateToken(token, id, role, plan));
}

TEST_CASE(test_auth_manager_detects_tampered_token) {
    auto auth = makeAuthManager();

    std::string token = auth.generateToken("auth-user", "support", "FREE", 60);
    REQUIRE(!token.empty());

    // Tamper with the payload
    if (token.size() > 20) {
        token[20] = (token[20] == 'a') ? 'b' : 'a';
    }

    std::string id, role, plan;
    CHECK(!auth.validateToken(token, id, role, plan));
}

TEST_CASE(test_auth_manager_roundtrip_role_and_plan) {
    auto auth = makeAuthManager();

    std::string token = auth.generateToken("unit-user", "marketing", "ELITE", 120);

    std::string id, role, plan;
    REQUIRE(auth.validateToken(token, id, role, plan));
    CHECK_EQ(id, "unit-user");
    CHECK_EQ(role, "marketing");
    CHECK_EQ(plan, "ELITE");
}

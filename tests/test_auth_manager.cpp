#include "test_framework.hpp"
#include "auth_manager.hpp"

#include <cstdlib>
#include <string>

#ifndef TEST_KEYS_DIR
#error "TEST_KEYS_DIR must be defined"
#endif

static std::string resolveKeysDir() {
    if (const char* fromEnv = std::getenv("TEST_KEYS_DIR")) {
        return std::string(fromEnv);
    }
    return std::string(TEST_KEYS_DIR);
}

TEST_CASE(test_auth_manager_roundtrip) {
    const std::string base = resolveKeysDir();
    const std::string privateKey = base + "/private.pem";
    const std::string publicKey = base + "/public.pem";

    AuthManager auth(privateKey, publicKey);

    const std::string userId = "test-user-42";
    const std::string role = "admin";
    const std::string plan = "PRO";

    std::string token = auth.generateToken(userId, role, plan, 600);

    std::string outUserId;
    std::string outRole;
    std::string outPlan;
    REQUIRE(auth.validateToken(token, outUserId, outRole, outPlan));
    CHECK_EQ(outUserId, userId);
    CHECK_EQ(outRole, role);
    CHECK_EQ(outPlan, plan);
}

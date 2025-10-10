#include "test_framework.hpp"
#include "user_controller.hpp"
#include "db.hpp"

#include <sodium.h>
#include <string>

static UserController makeController() {
    static Database db("test-conninfo-unused");
    return UserController(db);
}

TEST_CASE(test_user_controller_duplicate_registration_rejected) {
    UserController::resetTestState();
    auto controller = makeController();

    auto first = controller.registerUser("dup@example.com", "DupPass123", "Dup User", "user");
    REQUIRE(first.has_value());

    auto second = controller.registerUser("dup@example.com", "DupPass123", "Dup User", "user");
    REQUIRE(!second.has_value());

    auto users = controller.listUsers();
    CHECK_EQ(users.size(), 1u);
    CHECK_EQ(std::get<0>(users.front()), "dup@example.com");
}

TEST_CASE(test_user_controller_inactive_user_cannot_login) {
    UserController::resetTestState();
    auto controller = makeController();

    auto userId = controller.registerUser("inactive@example.com", "Secret123", "Inactive User", "user");
    REQUIRE(userId.has_value());

    UserController::setTestUserActive("inactive@example.com", false);

    auto auth = controller.verifyCredentials("inactive@example.com", "Secret123");
    REQUIRE(!auth.has_value());
}

TEST_CASE(test_user_controller_migrates_plaintext_passwords_to_bcrypt) {
    UserController::resetTestState();
    auto controller = makeController();

    const std::string email = "legacy@example.com";
    const std::string legacyPassword = "legacy123";

    UserController::injectTestUser(email, legacyPassword, "Legacy User", "user", true);

    auto login = controller.verifyCredentials(email, legacyPassword);
    REQUIRE(login.has_value());

    auto stored = UserController::debugGetPasswordHash(email);
    REQUIRE(stored.has_value());
    CHECK(stored.value().rfind("$2", 0) == 0);
    CHECK_NE(stored.value(), legacyPassword);
}

TEST_CASE(test_user_controller_migrates_argon2_hashes) {
    UserController::resetTestState();
    auto controller = makeController();

    const std::string email = "argon@example.com";
    const std::string password = "ArgonPass!";

    char argonHash[crypto_pwhash_STRBYTES];
    REQUIRE(crypto_pwhash_str(argonHash,
                              password.c_str(),
                              password.size(),
                              crypto_pwhash_OPSLIMIT_INTERACTIVE,
                              crypto_pwhash_MEMLIMIT_INTERACTIVE) == 0);

    UserController::injectTestUser(email, argonHash, "Argon User", "support", true);

    auto login = controller.verifyCredentials(email, password);
    REQUIRE(login.has_value());
    CHECK_EQ(login->second, "support");

    auto stored = UserController::debugGetPasswordHash(email);
    REQUIRE(stored.has_value());
    CHECK(stored.value().rfind("$2", 0) == 0);
}

TEST_CASE(test_user_controller_wrong_password_rejected) {
    UserController::resetTestState();
    auto controller = makeController();

    controller.registerUser("wrong@example.com", "CorrectHorseBatteryStaple", "Wrong User", "user");

    auto auth = controller.verifyCredentials("wrong@example.com", "incorrect");
    REQUIRE(!auth.has_value());
}

#include "test_framework.hpp"
#include "user_controller.hpp"
#include "db.hpp"

TEST_CASE(test_user_controller_register_and_authenticate) {
    Database db("test-conninfo-unused");
    UserController::resetTestState();
    UserController controller(db);

    const std::string email = "alice@example.com";
    const std::string password = "SuperSecret123";

    auto userId = controller.registerUser(email, password, "Alice Example", "user");
    REQUIRE(userId.has_value());

    // Duplicate registration should fail
    auto duplicate = controller.registerUser(email, password, "Alice Example", "user");
    REQUIRE(!duplicate.has_value());

    // Successful authentication
    auto auth = controller.verifyCredentials(email, password);
    REQUIRE(auth.has_value());
    CHECK_EQ(auth->first, userId.value());
    CHECK_EQ(auth->second, "user");

    // Wrong password should fail
    auto badAuth = controller.verifyCredentials(email, "WrongPassword");
    REQUIRE(!badAuth.has_value());
}

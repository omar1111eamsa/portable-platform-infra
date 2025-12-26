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

TEST_CASE(test_user_controller_update_role_and_status) {
    Database db("test-conninfo-unused");
    UserController::resetTestState();
    UserController controller(db);

    auto userId = controller.registerUser("role@example.com", "RolePass123", "Role User", "user");
    REQUIRE(userId.has_value());

    auto summary = controller.getUserById(userId.value());
    REQUIRE(summary.has_value());
    CHECK_EQ(summary->role, "user");
    CHECK(summary->is_active);

    auto updated = controller.updateUserRoleAndStatus(userId.value(), std::optional<std::string>("admin"), std::optional<bool>(false));
    REQUIRE(updated.has_value());
    CHECK_EQ(updated->role, "admin");
    CHECK(!updated->is_active);

    // Fetch again to ensure persisted state
    auto refreshed = controller.getUserByEmail("role@example.com");
    REQUIRE(refreshed.has_value());
    CHECK_EQ(refreshed->role, "admin");
    CHECK(!refreshed->is_active);
}

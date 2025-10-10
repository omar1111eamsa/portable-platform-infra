#include "test_framework.hpp"
#include "subscription_manager.hpp"
#include "user_controller.hpp"
#include "db.hpp"

TEST_CASE(test_subscription_manager_plan_resolution) {
    Database db("test-conninfo-unused");
    UserController::resetTestState();
    UserController controller(db);
    SubscriptionManager manager(db);

    const std::string email = "bob@example.com";
    const std::string password = "Password123";

    auto userId = controller.registerUser(email, password, "Bob Example", "user");
    REQUIRE(userId.has_value());

    REQUIRE(manager.updateUserSubscription(email, 199, "PAY-ELITE"));

    auto snapshot = manager.debugGetSubscription(userId.value());
    REQUIRE(snapshot.has_value());
    CHECK_EQ(snapshot->plan_name, "ELITE");
    CHECK_EQ(snapshot->status, "active");
    REQUIRE(snapshot->api_requests_per_hour_limit.has_value());
    CHECK_EQ(snapshot->api_requests_per_hour_limit.value(), 5000);

    // Downgrade plan to PRO (plan code 89)
    REQUIRE(manager.updateUserSubscription(email, 89, "PAY-PRO"));
    snapshot = manager.debugGetSubscription(userId.value());
    REQUIRE(snapshot.has_value());
    CHECK_EQ(snapshot->plan_name, "PRO");
    REQUIRE(snapshot->api_requests_per_hour_limit.has_value());
    CHECK_EQ(snapshot->api_requests_per_hour_limit.value(), 1000);
}

TEST_CASE(test_subscription_manager_free_plan_has_no_api_limit) {
    Database db("test-conninfo-unused");
    UserController::resetTestState();
    UserController controller(db);
    SubscriptionManager manager(db);

    auto userId = controller.registerUser("free@example.com", "FreePass1", "Free User", "user");
    REQUIRE(userId.has_value());

    REQUIRE(manager.updateUserSubscription("free@example.com", 0, "PAY-FREE"));

    auto snapshot = manager.debugGetSubscription(userId.value());
    REQUIRE(snapshot.has_value());
    CHECK_EQ(snapshot->plan_name, "FREE");
    CHECK_EQ(snapshot->backtests_per_day_limit, 5);
    CHECK(!snapshot->api_requests_per_hour_limit.has_value());
}

TEST_CASE(test_subscription_manager_fails_for_unknown_user) {
    Database db("test-conninfo-unused");
    UserController::resetTestState();
    SubscriptionManager manager(db);

    CHECK(!manager.updateUserSubscription("nouser@example.com", 199, "PAY-FAIL"));
}

#include "subscription_manager.hpp"
#include <iostream>
#include <pqxx/pqxx>
#include <optional>
#include <unordered_map>

#ifdef UNIT_TESTING
#include "user_controller.hpp"
#endif

namespace {

struct PlanSettings {
    std::string name;
    int backtestsPerDay;
    std::optional<int> apiRequestsPerHour;
};

#ifdef UNIT_TESTING
struct TestSubscriptionRecord {
    std::string plan_name;
    std::string status;
    int backtests_per_day_limit;
    std::optional<int> api_requests_per_hour_limit;
};

static std::unordered_map<std::string, TestSubscriptionRecord> gTestSubscriptions;
#else
class ScopedConnection {
public:
    explicit ScopedConnection(Database& db) : db_(db), conn_(db.acquire()) {}
    ~ScopedConnection() { if (conn_) db_.release(conn_); }
    pqxx::connection& get() { return *conn_; }
private:
    Database& db_;
    pqxx::connection* conn_;
};
#endif

PlanSettings resolvePlan(int planType) {
    switch (planType) {
        case 199:
            return {"ELITE", 200, 5000};
        case 89:
        case 100:
            return {"PRO", 50, 1000};
        case 0:
        case 1:
        default:
            return {"FREE", 5, std::nullopt};
    }
}

} // namespace

SubscriptionManager::SubscriptionManager(Database& db)
    : db_(db) {}

bool SubscriptionManager::updateUserSubscription(const std::string& userEmail,
                                                 int planType,
                                                 const std::string& paymentRef,
                                                 std::string* outUserId) {
#ifdef UNIT_TESTING
    try {
        (void)paymentRef;
        (void)outUserId;
        auto userIdOpt = UserController::debugGetUserIdByEmail(userEmail);
        if (!userIdOpt) {
            std::cerr << "❌ Cannot update subscription: user not found (UNIT_TESTING).\n";
            return false;
        }

        PlanSettings settings = resolvePlan(planType);
        TestSubscriptionRecord rec;
        rec.plan_name = settings.name;
        rec.status = "active";
        rec.backtests_per_day_limit = settings.backtestsPerDay;
        rec.api_requests_per_hour_limit = settings.apiRequestsPerHour;

        gTestSubscriptions[*userIdOpt] = rec;

        std::cout << "💳 (UNIT_TESTING) Subscription updated for " << userEmail
                  << " (plan: " << settings.name << ")\n";
        return true;
    } catch (const std::exception& e) {
        std::cerr << "Subscription update failed (UNIT_TESTING): " << e.what() << std::endl;
        return false;
    }
#else
    try {
        ScopedConnection dbconn(db_);
        pqxx::work txn(dbconn.get());

        pqxx::result r = txn.exec_params(
            "SELECT user_id FROM users WHERE email = $1", userEmail);
        if (r.empty()) {
            std::cerr << "❌ Cannot update subscription: user not found.\n";
            return false;
        }
        std::string userId = r[0][0].as<std::string>();
        if (outUserId) {
            *outUserId = userId;
        }

        PlanSettings settings = resolvePlan(planType);

        std::optional<int> apiLimit = settings.apiRequestsPerHour;

        txn.exec_params(
            "INSERT INTO subscriptions (user_id, plan_name, status, backtests_per_day_limit, "
            "api_requests_per_hour_limit, backtests_used_today, quota_reset_at, start_date, "
            "provider_subscription_id, updated_at) "
            "VALUES ($1, $2, 'active', $3, $4, 0, NOW(), NOW(), $5, NOW()) "
            "ON CONFLICT (user_id) DO UPDATE SET "
            "plan_name = EXCLUDED.plan_name, "
            "status = EXCLUDED.status, "
            "backtests_per_day_limit = EXCLUDED.backtests_per_day_limit, "
            "api_requests_per_hour_limit = EXCLUDED.api_requests_per_hour_limit, "
            "provider_subscription_id = EXCLUDED.provider_subscription_id, "
            "updated_at = NOW()",
            userId,
            settings.name,
            settings.backtestsPerDay,
            apiLimit,
            paymentRef
        );
        txn.commit();

        std::cout << "💳 Subscription updated for " << userEmail
                  << " (plan: " << settings.name << ")\n";
        return true;
    } catch (const std::exception& e) {
        std::cerr << "Subscription update failed: " << e.what() << std::endl;
        return false;
    }
#endif
}

void SubscriptionManager::listSubscriptions() {
#ifdef UNIT_TESTING
    std::cout << "🗂 Subscriptions (UNIT_TESTING):\n";
    for (const auto& [userId, rec] : gTestSubscriptions) {
        std::cout << " - user " << userId
                  << " → plan " << rec.plan_name
                  << " (" << rec.status << ")\n";
    }
#else
    try {
        ScopedConnection dbconn(db_);
        pqxx::work txn(dbconn.get());
        pqxx::result r = txn.exec(
            "SELECT s.subscription_id, u.email, s.plan_name, s.status "
            "FROM subscriptions s JOIN users u ON u.user_id = s.user_id");
        txn.commit();

        std::cout << "🗂 Subscriptions:\n";
        for (auto row : r) {
            std::cout << " - " << row["email"].c_str()
                      << " → plan " << row["plan_name"].c_str()
                      << " (" << row["status"].c_str() << ")\n";
        }
    } catch (const std::exception& e) {
        std::cerr << "listSubscriptions error: " << e.what() << std::endl;
    }
#endif
}

#ifdef UNIT_TESTING
std::optional<SubscriptionManager::TestSubscriptionSnapshot>
SubscriptionManager::debugGetSubscription(const std::string& userId) const {
    auto it = gTestSubscriptions.find(userId);
    if (it == gTestSubscriptions.end()) {
        return std::nullopt;
    }
    TestSubscriptionSnapshot snap;
    snap.plan_name = it->second.plan_name;
    snap.status = it->second.status;
    snap.backtests_per_day_limit = it->second.backtests_per_day_limit;
    snap.api_requests_per_hour_limit = it->second.api_requests_per_hour_limit;
    return snap;
}
#endif

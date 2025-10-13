#include "subscription_manager.hpp"
#include <iostream>
#include <pqxx/pqxx>
#include <optional>
#include <unordered_map>
#include <algorithm>
#include <cctype>

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
    int backtests_used_today{0};
    std::optional<std::string> provider_reference;
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

bool isSupportedPlanCode(int planType) {
    switch (planType) {
        case 0:
        case 1:
        case 89:
        case 100:
        case 199:
            return true;
        default:
            return false;
    }
}

std::string toUpperCopy(std::string value) {
    std::transform(value.begin(), value.end(), value.begin(), [](unsigned char c) {
        return static_cast<char>(std::toupper(c));
    });
    return value;
}

std::optional<PlanSettings> resolvePlanByName(const std::string& planName) {
    auto upper = toUpperCopy(planName);
    if (upper == "FREE") {
        return PlanSettings{"FREE", 5, std::nullopt};
    }
    if (upper == "PRO") {
        return PlanSettings{"PRO", 50, 1000};
    }
    if (upper == "ELITE") {
        return PlanSettings{"ELITE", 200, 5000};
    }
    return std::nullopt;
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

std::optional<SubscriptionManager::SubscriptionSnapshot>
SubscriptionManager::adminUpdateSubscriptionByUserId(const std::string& userId,
                                                     const SubscriptionAdminUpdate& update) {
#ifdef UNIT_TESTING
    auto userSummary = UserController::debugGetUserSummaryById(userId);
    if (!userSummary) {
        return std::nullopt;
    }

    auto &record = gTestSubscriptions[userId];
    if (record.plan_name.empty()) {
        PlanSettings defaults = resolvePlan(0);
        record.plan_name = defaults.name;
        record.status = "active";
        record.backtests_per_day_limit = defaults.backtestsPerDay;
        record.api_requests_per_hour_limit = defaults.apiRequestsPerHour;
        record.backtests_used_today = 0;
    }

    if (update.planTypeCode.has_value()) {
        if (!isSupportedPlanCode(*update.planTypeCode)) {
            throw std::invalid_argument("invalid_plan_type");
        }
        PlanSettings settings = resolvePlan(*update.planTypeCode);
        record.plan_name = settings.name;
        record.backtests_per_day_limit = settings.backtestsPerDay;
        record.api_requests_per_hour_limit = settings.apiRequestsPerHour;
    }

    if (update.planName.has_value()) {
        auto planSettings = resolvePlanByName(*update.planName);
        if (!planSettings) {
            throw std::invalid_argument("invalid_plan_name");
        }
        record.plan_name = planSettings->name;
        record.backtests_per_day_limit = planSettings->backtestsPerDay;
        record.api_requests_per_hour_limit = planSettings->apiRequestsPerHour;
    }

    if (update.backtestsPerDayLimit.has_value()) {
        record.backtests_per_day_limit = *update.backtestsPerDayLimit;
    }

    if (update.apiRequestsPerHourLimit.has_value()) {
        record.api_requests_per_hour_limit = update.apiRequestsPerHourLimit.value();
    }

    if (update.status.has_value()) {
        record.status = *update.status;
    }

    if (update.resetBacktestsUsedToday.value_or(false)) {
        record.backtests_used_today = 0;
    }

    if (update.providerReference.has_value()) {
        record.provider_reference = update.providerReference.value();
        if (record.provider_reference && record.provider_reference->empty()) {
            record.provider_reference = std::nullopt;
        }
    }

    SubscriptionSnapshot snapshot{
        record.plan_name,
        record.status,
        record.backtests_per_day_limit,
        record.backtests_used_today,
        record.api_requests_per_hour_limit
    };
    return snapshot;
#else
    try {
        ScopedConnection dbconn(db_);
        pqxx::work txn(dbconn.get());

        pqxx::result userRow = txn.exec_params(
            "SELECT 1 FROM users WHERE user_id = $1",
            userId
        );
        if (userRow.empty()) {
            return std::nullopt;
        }

        pqxx::result subRow = txn.exec_params(
            "SELECT plan_name, status, backtests_per_day_limit, api_requests_per_hour_limit, "
            "backtests_used_today, provider_subscription_id "
            "FROM subscriptions WHERE user_id = $1",
            userId
        );

        bool hasExisting = !subRow.empty();
        std::string planName = hasExisting && !subRow[0]["plan_name"].is_null()
                                   ? subRow[0]["plan_name"].as<std::string>()
                                   : std::string("FREE");
        std::string status = hasExisting && !subRow[0]["status"].is_null()
                                 ? subRow[0]["status"].as<std::string>()
                                 : std::string("active");
        int backtestsPerDay = hasExisting
                                  ? subRow[0]["backtests_per_day_limit"].as<int>()
                                  : 5;
        std::optional<int> apiPerHour;
        if (hasExisting && !subRow[0]["api_requests_per_hour_limit"].is_null()) {
            apiPerHour = subRow[0]["api_requests_per_hour_limit"].as<int>();
        }
        int backtestsUsed = hasExisting && !subRow[0]["backtests_used_today"].is_null()
                                ? subRow[0]["backtests_used_today"].as<int>()
                                : 0;
        std::optional<std::string> providerRef;
        if (hasExisting && !subRow[0]["provider_subscription_id"].is_null()) {
            providerRef = subRow[0]["provider_subscription_id"].as<std::string>();
        }

        if (update.planTypeCode.has_value()) {
            if (!isSupportedPlanCode(*update.planTypeCode)) {
                throw std::invalid_argument("invalid_plan_type");
            }
            PlanSettings settings = resolvePlan(*update.planTypeCode);
            planName = settings.name;
            backtestsPerDay = settings.backtestsPerDay;
            apiPerHour = settings.apiRequestsPerHour;
        }

        if (update.planName.has_value()) {
            auto planSettings = resolvePlanByName(*update.planName);
            if (!planSettings) {
                throw std::invalid_argument("invalid_plan_name");
            }
            planName = planSettings->name;
            backtestsPerDay = planSettings->backtestsPerDay;
            apiPerHour = planSettings->apiRequestsPerHour;
        }

        if (update.backtestsPerDayLimit.has_value()) {
            backtestsPerDay = *update.backtestsPerDayLimit;
        }

        if (update.apiRequestsPerHourLimit.has_value()) {
            apiPerHour = update.apiRequestsPerHourLimit.value();
        }

        if (update.status.has_value()) {
            status = *update.status;
        }

        bool resetBacktests = update.resetBacktestsUsedToday.value_or(false);
        if (resetBacktests) {
            backtestsUsed = 0;
        }

        if (update.providerReference.has_value()) {
            providerRef = update.providerReference.value();
        }
        if (providerRef && providerRef->empty()) {
            providerRef = std::nullopt;
        }

        if (!hasExisting) {
            txn.exec_params(
                "INSERT INTO subscriptions (user_id, plan_name, status, backtests_per_day_limit, "
                "api_requests_per_hour_limit, backtests_used_today, quota_reset_at, start_date, "
                "provider_subscription_id, updated_at) "
                "VALUES ($1, $2, $3, $4, $5, $6, NOW(), NOW(), $7, NOW())",
                userId,
                planName,
                status,
                backtestsPerDay,
                apiPerHour,
                backtestsUsed,
                providerRef
            );
        } else {
            txn.exec_params(
                "UPDATE subscriptions SET "
                "plan_name = $2, "
                "status = $3, "
                "backtests_per_day_limit = $4, "
                "api_requests_per_hour_limit = $5, "
                "backtests_used_today = $6, "
                "quota_reset_at = CASE WHEN $7 THEN NOW() ELSE quota_reset_at END, "
                "provider_subscription_id = $8, "
                "updated_at = NOW() "
                "WHERE user_id = $1",
                userId,
                planName,
                status,
                backtestsPerDay,
                apiPerHour,
                backtestsUsed,
                resetBacktests,
                providerRef
            );
        }

        txn.commit();

        SubscriptionSnapshot snapshot{planName, status, backtestsPerDay, backtestsUsed, apiPerHour};
        return snapshot;
    } catch (const std::invalid_argument&) {
        throw;
    } catch (const std::exception& e) {
        std::cerr << "adminUpdateSubscriptionByUserId error: " << e.what() << std::endl;
        return std::nullopt;
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
std::optional<SubscriptionManager::SubscriptionSnapshot>
SubscriptionManager::debugGetSubscription(const std::string& userId) const {
    auto it = gTestSubscriptions.find(userId);
    if (it == gTestSubscriptions.end()) {
        return std::nullopt;
    }
    return SubscriptionSnapshot{
        it->second.plan_name,
        it->second.status,
        it->second.backtests_per_day_limit,
        it->second.backtests_used_today,
        it->second.api_requests_per_hour_limit
    };
}
#else
std::optional<SubscriptionManager::SubscriptionSnapshot>
SubscriptionManager::debugGetSubscription(const std::string&) const {
    return std::nullopt;
}
#endif

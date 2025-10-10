#pragma once

#include "db.hpp"
#include <string>
#include <optional>

/**
 * @class SubscriptionManager
 * @brief Handles CRUD operations for user subscription records.
 */
class SubscriptionManager {
public:
    /**
     * @brief Construct the manager using the shared Database pool.
     */
    explicit SubscriptionManager(Database& db);

    /**
     * @brief Upsert a user's subscription details.
     * @param userEmail   Lookup key for the target user.
     * @param planType    Plan code (0, 89, 199) to convert into plan metadata.
     * @param paymentRef  External payment reference for auditing.
     * @param outUserId   Optional pointer populated with the resolved user_id.
     * @return true on success, false when the user cannot be located or the operation fails.
     */
    bool updateUserSubscription(const std::string& userEmail,
                                int planType,
                                const std::string& paymentRef,
                                std::string* outUserId = nullptr);

    /**
     * @brief Dump subscriptions to stdout (mainly for operational debugging).
     */
    void listSubscriptions();

#ifdef UNIT_TESTING
    /**
     * @brief Lightweight snapshot for assertions in UNIT_TESTING mode.
     */
    struct TestSubscriptionSnapshot {
        std::string plan_name;
        std::string status;
        int backtests_per_day_limit;
        std::optional<int> api_requests_per_hour_limit;
    };

    /// @brief Retrieve a fake snapshot when running under UNIT_TESTING.
    std::optional<TestSubscriptionSnapshot> debugGetSubscription(const std::string& userId) const;
#endif

private:
    Database& db_;
};

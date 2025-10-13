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

    struct SubscriptionSnapshot {
        std::string plan_name;
        std::string status;
        int backtests_per_day_limit;
        int backtests_used_today;
        std::optional<int> api_requests_per_hour_limit;
    };

    struct SubscriptionAdminUpdate {
        std::optional<int> planTypeCode;
        std::optional<std::string> planName;
        std::optional<std::string> status;
        std::optional<int> backtestsPerDayLimit;
        std::optional<std::optional<int>> apiRequestsPerHourLimit;
        std::optional<bool> resetBacktestsUsedToday;
        std::optional<std::optional<std::string>> providerReference;
    };

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
     * @brief Administrative update for a user's subscription using their user_id.
     * @param userId Target user identifier.
     * @param update Mutation payload (plan, status, quotas, etc).
     * @return Snapshot of the persisted subscription, or std::nullopt on failure.
     * @throws std::invalid_argument for unsupported plan codes/names.
     */
    std::optional<SubscriptionSnapshot> adminUpdateSubscriptionByUserId(
        const std::string& userId,
        const SubscriptionAdminUpdate& update);

    /**
     * @brief Dump subscriptions to stdout (mainly for operational debugging).
     */
    void listSubscriptions();

    /// @brief Retrieve a fake snapshot when running under UNIT_TESTING.
    std::optional<SubscriptionSnapshot> debugGetSubscription(const std::string& userId) const;

private:
    Database& db_;
};

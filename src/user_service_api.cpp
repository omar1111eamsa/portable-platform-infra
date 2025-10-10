// src/user_service_api.cpp
#include "user_service_api.hpp"
#include "user_controller.hpp"
#include "subscription_manager.hpp"
#include "auth_manager.hpp"
#include "db.hpp"
#include "ratelimiter_global.hpp"
#include "logger.hpp"

#include <httplib.h>
#include <nlohmann/json.hpp>
#include <pqxx/pqxx>

#include <chrono>
#include <iostream>
#include <mutex>
#include <optional>
#include <string>
#include <unordered_map>
#include <unordered_set>

using json = nlohmann::json;

namespace {

#ifndef UNIT_TESTING
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

struct UserSnapshot {
    std::string user_id;
    std::string email;
    std::string role;
    bool is_active{false};
    std::string plan_name{"FREE"};
    std::string plan_status{"active"};
    int backtests_per_day_limit{0};
    int backtests_used_today{0};
    std::optional<int> api_requests_per_hour_limit{};
    std::optional<std::string> quota_reset_at{};
};

struct CachedSnapshot {
    UserSnapshot snapshot;
    std::chrono::steady_clock::time_point expiry;
};

std::unordered_map<std::string, CachedSnapshot> gSnapshotCache;
std::mutex gSnapshotCacheMutex;
constexpr std::chrono::seconds kSnapshotTTL{5};

#ifndef UNIT_TESTING
static void recordUsage(Database& db,
                        const std::optional<std::string>& userId,
                        const std::string& action,
                        const std::string& endpoint,
                        const json& metadata = json::object()) {
    try {
        ScopedConnection dbconn(db);
        pqxx::work txn(dbconn.get());
        if (userId.has_value()) {
            txn.exec_params(
                "INSERT INTO usage_logs (user_id, action, endpoint, metadata) "
                "VALUES ($1, $2, $3, $4::jsonb)",
                *userId, action, endpoint, metadata.dump()
            );
        } else {
            txn.exec_params(
                "INSERT INTO usage_logs (user_id, action, endpoint, metadata) "
                "VALUES (NULL, $1, $2, $3::jsonb)",
                action, endpoint, metadata.dump()
            );
        }
        txn.commit();
    } catch (const std::exception& ex) {
        log_event(LogLevel::kWarn, "usage_log.failed", {{"action", action}, {"detail", ex.what()}});
    }
}

static std::optional<UserSnapshot> fetchUserSnapshotById(Database& db, const std::string& userId) {
    auto now = std::chrono::steady_clock::now();
    {
        std::lock_guard<std::mutex> lock(gSnapshotCacheMutex);
        auto it = gSnapshotCache.find(userId);
        if (it != gSnapshotCache.end() && it->second.expiry > now) {
            return it->second.snapshot;
        }
    }

    try {
        ScopedConnection dbconn(db);
        pqxx::work txn(dbconn.get());
        const std::string sql = R"SQL(
            SELECT
                u.user_id,
                u.email,
                u.role,
                u.is_active,
                s.plan_name,
                s.status,
                s.backtests_per_day_limit,
                s.backtests_used_today,
                s.api_requests_per_hour_limit,
                s.quota_reset_at
            FROM users u
            LEFT JOIN subscriptions s ON s.user_id = u.user_id
            WHERE u.user_id = $1
        )SQL";
        pqxx::result r = txn.exec_params(sql, userId);
        txn.commit();

        if (r.empty()) {
            return std::nullopt;
        }

        UserSnapshot snap;
        snap.user_id = r[0]["user_id"].as<std::string>();
        snap.email = r[0]["email"].as<std::string>();
        snap.role = r[0]["role"].as<std::string>();
        snap.is_active = r[0]["is_active"].as<bool>();
        if (!r[0]["plan_name"].is_null()) snap.plan_name = r[0]["plan_name"].c_str();
        if (!r[0]["status"].is_null()) snap.plan_status = r[0]["status"].c_str();
        if (!r[0]["backtests_per_day_limit"].is_null()) snap.backtests_per_day_limit = r[0]["backtests_per_day_limit"].as<int>();
        if (!r[0]["backtests_used_today"].is_null()) snap.backtests_used_today = r[0]["backtests_used_today"].as<int>();
        if (!r[0]["api_requests_per_hour_limit"].is_null()) snap.api_requests_per_hour_limit = r[0]["api_requests_per_hour_limit"].as<int>();
        if (!r[0]["quota_reset_at"].is_null()) snap.quota_reset_at = r[0]["quota_reset_at"].c_str();

        {
            std::lock_guard<std::mutex> lock(gSnapshotCacheMutex);
            gSnapshotCache[userId] = {snap, now + kSnapshotTTL};
        }

        return snap;
    } catch (const pqxx::sql_error& e) {
        std::cerr << "[fetchUserSnapshotById] SQL error: " << e.what()
                  << " Query: " << e.query() << "\n";
        return std::nullopt;
    } catch (const std::exception& e) {
        std::cerr << "[fetchUserSnapshotById] exception: " << e.what() << "\n";
        return std::nullopt;
    }
}

static void invalidateSnapshot(const std::string& userId) {
    std::lock_guard<std::mutex> lock(gSnapshotCacheMutex);
    gSnapshotCache.erase(userId);
}

static bool consumeBacktestQuota(Database& db, UserSnapshot& snap) {
    if (snap.backtests_per_day_limit <= 0) {
        return true;
    }
    if (snap.backtests_used_today >= snap.backtests_per_day_limit) {
        return false;
    }

    try {
        ScopedConnection dbconn(db);
        pqxx::work txn(dbconn.get());
        pqxx::result r = txn.exec_params(
            "UPDATE subscriptions "
            "SET backtests_used_today = backtests_used_today + 1, updated_at = NOW() "
            "WHERE user_id = $1 AND backtests_used_today < backtests_per_day_limit "
            "RETURNING backtests_used_today",
            snap.user_id
        );

        if (r.empty()) {
            txn.abort();
            return false;
        }

        snap.backtests_used_today = r[0]["backtests_used_today"].as<int>();
        txn.commit();
        return true;
    } catch (const std::exception& ex) {
        log_event(LogLevel::kWarn, "quota.consume_failed", {{"user_id", snap.user_id}, {"detail", ex.what()}});
        return true; // fail-open to avoid blocking auth path
    }
}
#else
static std::optional<UserSnapshot> fetchUserSnapshotById(Database&, const std::string&) {
    return std::nullopt;
}
static void invalidateSnapshot(const std::string&) {}
static bool consumeBacktestQuota(Database&, UserSnapshot&) { return true; }
static void recordUsage(Database&, const std::optional<std::string>&, const std::string&, const std::string&, const json&) {}
#endif

} // namespace

UserServiceAPI::UserServiceAPI(Database& db, UserController& uc, SubscriptionManager& sm, AuthManager& am)
: db_(db), userCtrl_(uc), subsMgr_(sm), auth_(am) { }

static json buildPermissionsPayload(const UserSnapshot& snap) {
    json permissions;
    permissions["is_admin"] = snap.role == "admin";
    permissions["can_backtest"] = snap.is_active && snap.plan_status == "active" && snap.backtests_per_day_limit > 0;
    permissions["can_use_api"] = snap.is_active && snap.plan_status == "active" &&
                                 snap.api_requests_per_hour_limit.has_value() &&
                                 snap.api_requests_per_hour_limit.value() > 0;

    int remaining = snap.backtests_per_day_limit - snap.backtests_used_today;
    if (remaining < 0) remaining = 0;

    json quotas;
    quotas["backtests_per_day_limit"] = snap.backtests_per_day_limit;
    quotas["backtests_used_today"] = snap.backtests_used_today;
    quotas["backtests_remaining_today"] = remaining;
    if (snap.api_requests_per_hour_limit.has_value()) {
        quotas["api_requests_per_hour_limit"] = snap.api_requests_per_hour_limit.value();
    } else {
        quotas["api_requests_per_hour_limit"] = nullptr;
    }
    if (snap.quota_reset_at.has_value()) {
        quotas["quota_reset_at"] = snap.quota_reset_at.value();
    } else {
        quotas["quota_reset_at"] = nullptr;
    }

    json subscription;
    subscription["plan_name"] = snap.plan_name;
    subscription["status"] = snap.plan_status;
    subscription["backtests_per_day_limit"] = snap.backtests_per_day_limit;
    subscription["backtests_used_today"] = snap.backtests_used_today;
    if (snap.api_requests_per_hour_limit.has_value()) {
        subscription["api_requests_per_hour_limit"] = snap.api_requests_per_hour_limit.value();
    } else {
        subscription["api_requests_per_hour_limit"] = nullptr;
    }
    if (snap.quota_reset_at.has_value()) {
        subscription["quota_reset_at"] = snap.quota_reset_at.value();
    } else {
        subscription["quota_reset_at"] = nullptr;
    }

    json result;
    result["user_id"] = snap.user_id;
    result["email"] = snap.email;
    result["role"] = snap.role;
    result["is_active"] = snap.is_active;
    result["permissions"] = permissions;
    result["quotas"] = quotas;
    result["plan_name"] = snap.plan_name;
    result["plan_status"] = snap.plan_status;
    result["subscription"] = subscription;

    return result;
}

void UserServiceAPI::start(const std::string& host, int port) {
    httplib::Server svr;

    static const std::unordered_set<std::string> kAllowedRoles = {
        "user", "admin", "support", "marketing"
    };

    // --- POST /internal/auth/register
    svr.Post("/internal/auth/register", [this](const httplib::Request& req, httplib::Response& res) {
        std::string caller = req.remote_addr.empty() ? "unknown_ip" : req.remote_addr;
        std::string reason;
        if (gRateLimiter) {
            if (!gRateLimiter->allowRequest(caller, "FREE", reason)) {
                res.status = 429;
                json j; j["error"] = "Too Many Requests"; j["reason"] = reason;
                res.set_content(j.dump(), "application/json");
                return;
            }
        }

        try {
            json body = json::parse(req.body);
            std::string email = body.at("email").get<std::string>();
            std::string password = body.at("password").get<std::string>();
            std::string full_name = body.value("full_name", "");
            std::string role = body.value("role", "user");
            std::string provider_ref = body.value("provider_subscription_id", "");

            if (email.empty() || password.empty()) {
                res.status = 400;
                res.set_content(R"({"error":"email and password are required"})", "application/json");
                return;
            }
            if (!kAllowedRoles.count(role)) {
                res.status = 400;
                json j; j["error"] = "invalid role"; j["allowed_roles"] = kAllowedRoles;
                res.set_content(j.dump(), "application/json");
                return;
            }

            auto userId = userCtrl_.registerUser(email, password, full_name, role);
            if (!userId) {
                res.status = 409;
                res.set_content(R"({"success":false,"error":"User already exists"})", "application/json");
                log_event(LogLevel::kWarn, "auth.register_conflict", {{"email", email}});
                return;
            }

            if (!subsMgr_.updateUserSubscription(email, 0, provider_ref)) {
                res.status = 500;
                res.set_content(R"({"success":false,"error":"Failed to initialize subscription"})", "application/json");
                log_event(LogLevel::kError, "auth.register_subscription_failure", {{"email", email}});
                return;
            }

            json resp;
            resp["success"] = true;
            resp["user_id"] = *userId;
            resp["email"] = email;
            resp["role"] = role;

            log_event(LogLevel::kInfo, "auth.register_success", {{"email", email}, {"user_id", *userId}});
            json metadata = {
                {"email", email},
                {"role", role},
                {"provider_reference", provider_ref}
            };
            recordUsage(db_, std::make_optional(*userId), "auth.register", "/internal/auth/register", metadata);
            res.status = 201;
            res.set_content(resp.dump(), "application/json");
        } catch (const json::exception& e) {
            res.status = 400;
            json j; j["success"] = false; j["error"] = "Invalid request"; j["detail"] = e.what();
            res.set_content(j.dump(), "application/json");
            log_event(LogLevel::kWarn, "auth.register_bad_request", {{"detail", e.what()}});
        } catch (const std::exception& e) {
            res.status = 500;
            json j; j["success"] = false; j["error"] = e.what();
            res.set_content(j.dump(), "application/json");
            log_event(LogLevel::kError, "auth.register_exception", {{"detail", e.what()}});
        }
    });

    // --- POST /internal/auth/login
    svr.Post("/internal/auth/login", [this](const httplib::Request& req, httplib::Response& res) {
        std::string emailForRl = "anonymous";
        try {
            json tmp = json::parse(req.body);
            if (tmp.contains("email")) emailForRl = tmp["email"].get<std::string>();
        } catch (...) {
            // ignore; will be re-parsed later
        }

        std::string reason;
        if (gRateLimiter) {
            if (!gRateLimiter->allowRequest(emailForRl, "FREE", reason)) {
                res.status = 429;
                json j; j["error"] = "Too Many Requests"; j["reason"] = reason;
                res.set_content(j.dump(), "application/json");
                return;
            }
        }

        try {
            json body = json::parse(req.body);
            std::string email = body.at("email").get<std::string>();
            std::string password = body.at("password").get<std::string>();

            auto authResult = userCtrl_.verifyCredentials(email, password);
            if (!authResult) {
                res.status = 401;
                res.set_content(R"({"success":false,"error":"Invalid credentials"})", "application/json");
                log_event(LogLevel::kWarn, "auth.login_invalid", {{"email", email}});
                recordUsage(db_, std::nullopt, "auth.login_failure", "/internal/auth/login", {{"email", email}});
                return;
            }

            const auto& [userId, role] = *authResult;
            auto snapshot = fetchUserSnapshotById(db_, userId);
            if (!snapshot) {
                res.status = 500;
                res.set_content(R"({"success":false,"error":"User profile not found"})", "application/json");
                return;
            }

            std::string planForLimiter = snapshot->plan_name.empty() ? "FREE" : snapshot->plan_name;
            if (gRateLimiter) {
                if (!gRateLimiter->allowRequest(userId, planForLimiter, reason)) {
                    res.status = 429;
                    json j; j["error"] = "Too Many Requests"; j["reason"] = reason;
                    res.set_content(j.dump(), "application/json");
                    return;
                }
            }

            std::string token = auth_.generateToken(userId, role, planForLimiter, 3600);

            json resp;
            resp["success"] = true;
            resp["token"] = token;
            resp["user_id"] = userId;
            resp["role"] = role;
            resp["plan"] = planForLimiter;

            log_event(LogLevel::kInfo, "auth.login_success", {{"email", email}, {"user_id", userId}});
            json metadata = {
                {"email", email},
                {"plan", planForLimiter},
                {"role", role}
            };
            recordUsage(db_, std::make_optional(userId), "auth.login", "/internal/auth/login", metadata);
            res.status = 200;
            res.set_content(resp.dump(), "application/json");
        } catch (const json::exception& e) {
            res.status = 400;
            json j; j["success"] = false; j["error"] = "Invalid request"; j["detail"] = e.what();
            res.set_content(j.dump(), "application/json");
            log_event(LogLevel::kWarn, "auth.login_bad_request", {{"detail", e.what()}});
        } catch (const std::exception& e) {
            res.status = 500;
            json j; j["success"] = false; j["error"] = e.what();
            res.set_content(j.dump(), "application/json");
            log_event(LogLevel::kError, "auth.login_exception", {{"detail", e.what()}});
        }
    });

    // --- POST /internal/auth/validate-token
    svr.Post("/internal/auth/validate-token", [this](const httplib::Request& req, httplib::Response& res) {
        try {
            json body = json::parse(req.body);
            std::string token = body.at("token").get<std::string>();

            std::string userId;
            std::string roleFromToken;
            std::string planFromToken;
            if (!auth_.validateToken(token, userId, roleFromToken, planFromToken)) {
                res.status = 401;
                json j; j["valid"] = false; j["error"] = "invalid token";
                res.set_content(j.dump(), "application/json");
                log_event(LogLevel::kWarn, "auth.validate_token_invalid");
                recordUsage(db_, std::nullopt, "auth.validate_token_failure", "/internal/auth/validate-token", {{"reason", "invalid_token"}});
                return;
            }

            auto snapshot = fetchUserSnapshotById(db_, userId);
            if (!snapshot) {
                res.status = 404;
                json j; j["valid"] = false; j["error"] = "user not found";
                res.set_content(j.dump(), "application/json");
                recordUsage(db_, std::make_optional(userId), "auth.validate_token_missing_user", "/internal/auth/validate-token", {{"reason", "user_not_found"}});
                return;
            }

            std::string reason;
            std::string limiterPlan = snapshot->plan_name.empty() ? planFromToken : snapshot->plan_name;
            if (limiterPlan.empty()) limiterPlan = "FREE";
            if (gRateLimiter) {
                if (!gRateLimiter->allowRequest(userId, limiterPlan, reason)) {
                    res.status = 429;
                    json j; j["error"] = "Too Many Requests"; j["reason"] = reason;
                    res.set_content(j.dump(), "application/json");
                    recordUsage(db_, std::make_optional(userId), "auth.validate_token_rate_limited", "/internal/auth/validate-token", {{"reason", reason}});
                    return;
                }
            }

            if (!consumeBacktestQuota(db_, *snapshot)) {
                res.status = 429;
                json j;
                j["error"] = "quota_exhausted";
                j["backtests_per_day_limit"] = snapshot->backtests_per_day_limit;
                j["backtests_used_today"] = snapshot->backtests_used_today;
                res.set_content(j.dump(), "application/json");
                recordUsage(db_, std::make_optional(userId), "auth.validate_token_quota_exhausted", "/internal/auth/validate-token", {{"limit", snapshot->backtests_per_day_limit}});
                return;
            }

            invalidateSnapshot(userId);

            json payload = buildPermissionsPayload(*snapshot);
            payload["valid"] = true;

            log_event(LogLevel::kInfo, "auth.validate_token_success", {{"user_id", userId}, {"plan", payload["plan_name"].get<std::string>()}});
            json metadata = {
                {"plan", payload["plan_name"].get<std::string>()},
                {"role", payload["role"].get<std::string>()},
                {"is_active", payload["is_active"].get<bool>()},
                {"backtests_used_today", payload["quotas"]["backtests_used_today"].get<int>()}
            };
            recordUsage(db_, std::make_optional(userId), "auth.validate_token", "/internal/auth/validate-token", metadata);
            res.status = 200;
            res.set_content(payload.dump(), "application/json");
        } catch (const json::exception& e) {
            res.status = 400;
            json j; j["valid"] = false; j["error"] = "Invalid request"; j["detail"] = e.what();
            res.set_content(j.dump(), "application/json");
            log_event(LogLevel::kWarn, "auth.validate_token_bad_request", {{"detail", e.what()}});
        } catch (const std::exception& e) {
            res.status = 500;
            json j; j["valid"] = false; j["error"] = e.what();
            res.set_content(j.dump(), "application/json");
            log_event(LogLevel::kError, "auth.validate_token_exception", {{"detail", e.what()}});
        }
    });

    // --- GET /internal/users/{user_id}/permissions
    svr.Get(R"(/internal/users/([0-9a-fA-F-]+)/permissions)", [this](const httplib::Request& req, httplib::Response& res) {
        std::string userId = req.matches[1];

        auto snapshot = fetchUserSnapshotById(db_, userId);
        if (!snapshot) {
            res.status = 404;
            res.set_content(R"({"error":"user not found"})", "application/json");
            log_event(LogLevel::kWarn, "permissions.not_found", {{"user_id", userId}});
            recordUsage(db_, std::make_optional(userId), "permissions.read_missing_user", "/internal/users/:id/permissions", {{"reason", "user_not_found"}});
            return;
        }

        std::string reason;
        std::string limiterPlan = snapshot->plan_name.empty() ? "FREE" : snapshot->plan_name;
        if (gRateLimiter) {
            if (!gRateLimiter->allowRequest(userId, limiterPlan, reason)) {
                res.status = 429;
                json j; j["error"] = "Too Many Requests"; j["reason"] = reason;
                res.set_content(j.dump(), "application/json");
                recordUsage(db_, std::make_optional(userId), "permissions.read_rate_limited", "/internal/users/:id/permissions", {{"reason", reason}});
                return;
            }
        }

        json payload = buildPermissionsPayload(*snapshot);
        payload["valid"] = true;

        log_event(LogLevel::kInfo, "permissions.read", {{"user_id", userId}, {"plan", payload["plan_name"].get<std::string>()}});
        json metadata = {
            {"plan", payload["plan_name"].get<std::string>()},
            {"role", payload["role"].get<std::string>()},
            {"is_active", payload["is_active"].get<bool>()}
        };
        recordUsage(db_, std::make_optional(userId), "permissions.read", "/internal/users/:id/permissions", metadata);
        res.status = 200;
        res.set_content(payload.dump(), "application/json");
    });

    // --- PUT /internal/users/{email}/subscription (legacy helper for ops)
    svr.Put(R"(/internal/users/([^/]+)/subscription)", [this](const httplib::Request& req, httplib::Response& res) {
        std::string email = req.matches[1];
        std::string reason;
        if (gRateLimiter) {
            if (!gRateLimiter->allowRequest(email, "PRO", reason)) {
                res.status = 429;
                json j; j["error"] = "Too Many Requests"; j["reason"] = reason;
                res.set_content(j.dump(), "application/json");
                return;
            }
        }

        try {
            json body = json::parse(req.body);
            int plan_type = body.value("plan_type", -1);
            std::string payment_ref = body.value("payment_reference", std::string());
            if (plan_type < 0) {
                res.status = 400;
                res.set_content(R"({"error":"missing plan_type"})", "application/json");
                log_event(LogLevel::kWarn, "subscription.update_missing_plan", {{"email", email}});
                return;
            }

            std::string updatedUserId;
            if (!subsMgr_.updateUserSubscription(email, plan_type, payment_ref, &updatedUserId)) {
                res.status = 500;
                res.set_content(R"({"error":"failed to update subscription"})", "application/json");
                log_event(LogLevel::kError, "subscription.update_failed", {{"email", email}});
                return;
            }
            invalidateSnapshot(updatedUserId);

            log_event(LogLevel::kInfo, "subscription.update_success", {{"email", email}, {"plan_type", std::to_string(plan_type)}, {"user_id", updatedUserId}});
            json metadata = {
                {"email", email},
                {"plan_type", plan_type},
                {"payment_reference", payment_ref}
            };
            recordUsage(db_, std::make_optional(updatedUserId), "subscription.update", "/internal/users/:email/subscription", metadata);
            res.status = 200;
            res.set_content(R"({"message":"Subscription updated"})", "application/json");
        } catch (const json::exception& e) {
            res.status = 400;
            json j; j["error"] = "Invalid request"; j["detail"] = e.what();
            res.set_content(j.dump(), "application/json");
            log_event(LogLevel::kWarn, "subscription.update_bad_request", {{"detail", e.what()}});
        } catch (const std::exception& e) {
            res.status = 500;
            json j; j["error"] = e.what();
            res.set_content(j.dump(), "application/json");
            log_event(LogLevel::kError, "subscription.update_exception", {{"detail", e.what()}});
        }
    });

    // health endpoint
    svr.Get("/health", [](const httplib::Request&, httplib::Response& res) {
        res.status = 200;
        res.set_content(R"({"status":"ok"})", "application/json");
    });

    log_event(LogLevel::kInfo, "http.listen", {{"host", host}, {"port", std::to_string(port)}});
    svr.listen(host.c_str(), port);
}

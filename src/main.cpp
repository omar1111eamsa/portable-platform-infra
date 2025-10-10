#include <iostream>
#include <cstdlib>
#include <string>
#include <memory>

#include "db.hpp"
#include "user_controller.hpp"
#include "subscription_manager.hpp"
#include "auth_manager.hpp"
#include "user_service_api.hpp"
#include "ratelimiter_global.hpp"
#include "ratelimiter.hpp"
#include "logger.hpp"
#include "config_loader.hpp"

#include <sodium.h>
#include <filesystem>
#include <cstdlib>

int main() {
    log_event(LogLevel::kInfo, "service.start", {});

    if (sodium_init() < 0) {
        log_event(LogLevel::kError, "libsodium.init_failed");
        return 1;
    }

    try {
        // -------------------------------------------------------
        // Load configuration (file first, then env overrides)
        // -------------------------------------------------------
        ServiceConfig cfg;
        std::string configPath = std::getenv("CONFIG_PATH")
            ? std::string(std::getenv("CONFIG_PATH"))
            : "config/service_config.json";

        std::string configErr;
        if (!load_config_from_file(configPath, cfg, configErr)) {
            log_event(LogLevel::kWarn, "config.load_failed", {{"path", configPath}, {"detail", configErr}});
        } else if (!configErr.empty()) {
            log_event(LogLevel::kWarn, "config.load_warning", {{"path", configPath}, {"detail", configErr}});
        }
        apply_env_overrides(cfg);

        if (cfg.rate_limit_testmode) {
            setenv("RATE_LIMIT_TESTMODE", "1", 1);
        }
        if (cfg.rate_limit_pro_per_min > 0) {
            std::string value = std::to_string(cfg.rate_limit_pro_per_min);
            setenv("RATE_LIMIT_PRO_PER_MIN", value.c_str(), 1);
        }
        if (cfg.rate_limit_pro_per_day > 0) {
            std::string value = std::to_string(cfg.rate_limit_pro_per_day);
            setenv("RATE_LIMIT_PRO_PER_DAY", value.c_str(), 1);
        }

        // -------------------------------------------------------
        // Build database connection string from config
        // -------------------------------------------------------
        std::string conninfo =
            "host=" + cfg.db_host +
            " port=" + std::to_string(cfg.db_port) +
            " dbname=" + cfg.db_name +
            " user=" + cfg.db_user +
            " password=" + cfg.db_password;

        // -------------------------------------------------------
        // Initialize Database + Schema
        // -------------------------------------------------------
        Database db(conninfo);
        db.initializeSchema();
        log_event(LogLevel::kInfo, "database.ready");

        // -------------------------------------------------------
        // JWT key paths (env overrides)
        // -------------------------------------------------------
        std::string privPath = cfg.jwt_private_path;
        std::string pubPath  = cfg.jwt_public_path;

        // -------------------------------------------------------
        // Initialize core service modules
        // -------------------------------------------------------
        UserController userCtrl(db);
        SubscriptionManager subsMgr(db);

        // AuthManager will throw if it cannot read the key files
        AuthManager auth(privPath, pubPath);

        // -------------------------------------------------------
        // Initialize RateLimiter (global pointer)
        // -------------------------------------------------------
        gRateLimiter = new RateLimiter(cfg.redis_host, cfg.redis_port, "cqos:rl");

        // -------------------------------------------------------
        // Start HTTP server (UserServiceAPI)
        // -------------------------------------------------------
        UserServiceAPI api(db, userCtrl, subsMgr, auth);
        std::string host = cfg.service_host;
        int port = cfg.service_port;

        log_event(LogLevel::kInfo, "http.start", { {"host", host}, {"port", std::to_string(port)} });
        api.start(host, port);

        // cleanup
        delete gRateLimiter;
        gRateLimiter = nullptr;
    }
    catch (const std::exception& e) {
        log_event(LogLevel::kError, "startup.error", { {"detail", e.what()} });
        return 1;
    }
    return 0;
}

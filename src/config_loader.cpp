/**
 * @file config_loader.cpp
 */

#include "config_loader.hpp"

#include <cstdlib>
#include <cctype>
#include <filesystem>
#include <fstream>
#include <nlohmann/json.hpp>

namespace {

template <typename T>
void assign_if_present(const nlohmann::json& j, const char* key, T& dest) {
    if (j.contains(key) && !j.at(key).is_null()) {
        dest = j.at(key).get<T>();
    }
}

int getenv_int(const char* name, int fallback) {
    if (const char* raw = std::getenv(name)) {
        try {
            return std::stoi(raw);
        } catch (...) {
            return fallback;
        }
    }
    return fallback;
}

bool getenv_bool(const char* name, bool fallback) {
    if (const char* raw = std::getenv(name)) {
        std::string v(raw);
        for (auto& c : v) c = static_cast<char>(std::tolower(c));
        return (v == "1" || v == "true" || v == "yes");
    }
    return fallback;
}

std::string getenv_str(const char* name, const std::string& fallback) {
    if (const char* raw = std::getenv(name)) {
        return std::string(raw);
    }
    return fallback;
}

} // namespace

bool load_config_from_file(const std::string& path, ServiceConfig& cfg, std::string& err) {
    namespace fs = std::filesystem;
    err.clear();

    if (path.empty()) {
        return true;
    }

    if (!fs::exists(path)) {
        return true; // nothing to load; keep defaults/env overrides
    }

    try {
        std::ifstream in(path);
        if (!in.is_open()) {
            err = "failed to open config file";
            return false;
        }

        nlohmann::json j;
        in >> j;

        assign_if_present(j, "service_host", cfg.service_host);
        assign_if_present(j, "service_port", cfg.service_port);

        if (j.contains("database")) {
            const auto& db = j.at("database");
            assign_if_present(db, "host", cfg.db_host);
            assign_if_present(db, "port", cfg.db_port);
            assign_if_present(db, "name", cfg.db_name);
            assign_if_present(db, "user", cfg.db_user);
            assign_if_present(db, "password", cfg.db_password);
        }

        if (j.contains("redis")) {
            const auto& redis = j.at("redis");
            assign_if_present(redis, "host", cfg.redis_host);
            assign_if_present(redis, "port", cfg.redis_port);
        }

        if (j.contains("jwt")) {
            const auto& jwt = j.at("jwt");
            assign_if_present(jwt, "private_key_path", cfg.jwt_private_path);
            assign_if_present(jwt, "public_key_path", cfg.jwt_public_path);
        }

        if (j.contains("rate_limit")) {
            const auto& rl = j.at("rate_limit");
            assign_if_present(rl, "testmode", cfg.rate_limit_testmode);
            assign_if_present(rl, "pro_per_min", cfg.rate_limit_pro_per_min);
            assign_if_present(rl, "pro_per_day", cfg.rate_limit_pro_per_day);
        }

        return true;
    } catch (const std::exception& ex) {
        err = ex.what();
        return false;
    }
}

void apply_env_overrides(ServiceConfig& cfg) {
    cfg.service_host = getenv_str("SERVICE_HOST", cfg.service_host);
    cfg.service_port = getenv_int("SERVICE_PORT", cfg.service_port);

    cfg.db_host = getenv_str("DB_HOST", cfg.db_host);
    cfg.db_port = getenv_int("DB_PORT", cfg.db_port);
    cfg.db_name = getenv_str("DB_NAME", cfg.db_name);
    cfg.db_user = getenv_str("DB_USER", cfg.db_user);
    cfg.db_password = getenv_str("DB_PASSWORD", cfg.db_password);

    cfg.redis_host = getenv_str("REDIS_HOST", cfg.redis_host);
    cfg.redis_port = getenv_int("REDIS_PORT", cfg.redis_port);

    cfg.jwt_private_path = getenv_str("JWT_PRIVATE_PATH", cfg.jwt_private_path);
    cfg.jwt_public_path = getenv_str("JWT_PUBLIC_PATH", cfg.jwt_public_path);

    cfg.rate_limit_testmode = getenv_bool("RATE_LIMIT_TESTMODE", cfg.rate_limit_testmode);
    cfg.rate_limit_pro_per_min = getenv_int("RATE_LIMIT_PRO_PER_MIN", cfg.rate_limit_pro_per_min);
    cfg.rate_limit_pro_per_day = getenv_int("RATE_LIMIT_PRO_PER_DAY", cfg.rate_limit_pro_per_day);
}

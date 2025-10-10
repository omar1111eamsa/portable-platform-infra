/**
 * @file config_loader.hpp
 * @brief Helpers for loading service configuration from JSON files and environment variables.
 */

#pragma once

#include <string>

/**
 * @struct ServiceConfig
 * @brief In-memory representation of runtime configuration values.
 */
struct ServiceConfig {
    std::string service_host{"0.0.0.0"};
    int service_port{8080};

    std::string db_host{"localhost"};
    int db_port{5432};
    std::string db_name{"cqos"};
    std::string db_user{"appuser"};
    std::string db_password{"postgres"};

    std::string redis_host{"redis"};
    int redis_port{6379};

    std::string jwt_private_path{"/usr/local/bin/keys/private.pem"};
    std::string jwt_public_path{"/usr/local/bin/keys/public.pem"};

    bool rate_limit_testmode{false};
    int rate_limit_pro_per_min{0};  // 0 means leave unset
    int rate_limit_pro_per_day{0};
};

/**
 * Load configuration from a JSON file if it exists. Missing fields are ignored.
 *
 * @param path Filesystem path to JSON config.
 * @param cfg  Configuration object to mutate with loaded values.
 * @param err  Populated with error details when parsing fails.
 * @return true if the file was loaded successfully, false on parse/IO errors.
 */
bool load_config_from_file(const std::string& path, ServiceConfig& cfg, std::string& err);

/**
 * Apply environment variable overrides to the configuration.
 *
 * Supported variables mirror the cahier requirements (`SERVICE_HOST`, `DB_HOST`, etc.).
 *
 * @param cfg Configuration instance to mutate.
 */
void apply_env_overrides(ServiceConfig& cfg);

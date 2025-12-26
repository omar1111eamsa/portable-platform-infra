#include "test_framework.hpp"
#include "config_loader.hpp"

#include <fstream>
#include <cstdio>
#include <cstdlib>

TEST_CASE(test_config_loader_parses_json) {
    ServiceConfig cfg;
    std::string err;
    const std::string path = "config_loader_test.json";

    std::ofstream out(path);
    out << R"({
        "service_host": "127.0.0.1",
        "service_port": 9000,
        "database": {
            "host": "db.local",
            "port": 5433,
            "name": "testdb",
            "user": "tester",
            "password": "secret"
        },
        "redis": {
            "host": "redis.local",
            "port": 6380
        },
        "jwt": {
            "private_key_path": "/tmp/priv.pem",
            "public_key_path": "/tmp/pub.pem"
        },
        "rate_limit": {
            "testmode": true,
            "pro_per_min": 123,
            "pro_per_day": 456
        }
    })";
    out.close();

    REQUIRE(load_config_from_file(path, cfg, err));
    CHECK(err.empty());
    CHECK_EQ(cfg.service_host, "127.0.0.1");
    CHECK_EQ(cfg.service_port, 9000);
    CHECK_EQ(cfg.db_host, "db.local");
    CHECK_EQ(cfg.db_port, 5433);
    CHECK_EQ(cfg.db_name, "testdb");
    CHECK_EQ(cfg.db_user, "tester");
    CHECK_EQ(cfg.db_password, "secret");
    CHECK_EQ(cfg.redis_host, "redis.local");
    CHECK_EQ(cfg.redis_port, 6380);
    CHECK_EQ(cfg.jwt_private_path, "/tmp/priv.pem");
    CHECK_EQ(cfg.jwt_public_path, "/tmp/pub.pem");
    CHECK(cfg.rate_limit_testmode);
    CHECK_EQ(cfg.rate_limit_pro_per_min, 123);
    CHECK_EQ(cfg.rate_limit_pro_per_day, 456);

    std::remove(path.c_str());
}

TEST_CASE(test_config_loader_handles_errors_and_env) {
    ServiceConfig cfg;
    std::string err;

    const std::string bad_path = "config_loader_bad.json";
    {
        std::ofstream out(bad_path);
        out << "{ invalid json";
    }
    REQUIRE(!load_config_from_file(bad_path, cfg, err));
    CHECK(!err.empty());
    std::remove(bad_path.c_str());

    // Env overrides
    setenv("SERVICE_HOST", "0.0.0.0", 1);
    setenv("SERVICE_PORT", "7000", 1);
    setenv("DB_HOST", "env-db", 1);
    setenv("DB_PORT", "6000", 1);
    setenv("DB_NAME", "envdb", 1);
    setenv("DB_USER", "envuser", 1);
    setenv("DB_PASSWORD", "envpass", 1);
    setenv("REDIS_HOST", "env-redis", 1);
    setenv("REDIS_PORT", "7373", 1);
    setenv("JWT_PRIVATE_PATH", "/env/priv.pem", 1);
    setenv("JWT_PUBLIC_PATH", "/env/pub.pem", 1);
    setenv("RATE_LIMIT_TESTMODE", "true", 1);
    setenv("RATE_LIMIT_PRO_PER_MIN", "321", 1);
    setenv("RATE_LIMIT_PRO_PER_DAY", "654", 1);

    apply_env_overrides(cfg);
    CHECK_EQ(cfg.service_host, "0.0.0.0");
    CHECK_EQ(cfg.service_port, 7000);
    CHECK_EQ(cfg.db_host, "env-db");
    CHECK_EQ(cfg.db_port, 6000);
    CHECK_EQ(cfg.db_name, "envdb");
    CHECK_EQ(cfg.db_user, "envuser");
    CHECK_EQ(cfg.db_password, "envpass");
    CHECK_EQ(cfg.redis_host, "env-redis");
    CHECK_EQ(cfg.redis_port, 7373);
    CHECK_EQ(cfg.jwt_private_path, "/env/priv.pem");
    CHECK_EQ(cfg.jwt_public_path, "/env/pub.pem");
    CHECK(cfg.rate_limit_testmode);
    CHECK_EQ(cfg.rate_limit_pro_per_min, 321);
    CHECK_EQ(cfg.rate_limit_pro_per_day, 654);

    unsetenv("SERVICE_HOST");
    unsetenv("SERVICE_PORT");
    unsetenv("DB_HOST");
    unsetenv("DB_PORT");
    unsetenv("DB_NAME");
    unsetenv("DB_USER");
    unsetenv("DB_PASSWORD");
    unsetenv("REDIS_HOST");
    unsetenv("REDIS_PORT");
    unsetenv("JWT_PRIVATE_PATH");
    unsetenv("JWT_PUBLIC_PATH");
    unsetenv("RATE_LIMIT_TESTMODE");
    unsetenv("RATE_LIMIT_PRO_PER_MIN");
    unsetenv("RATE_LIMIT_PRO_PER_DAY");
}

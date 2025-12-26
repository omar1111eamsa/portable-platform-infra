#pragma once

#include <pqxx/pqxx>
#include <string>
#include <iostream>
#ifndef UNIT_TESTING
#include <memory>
#include <mutex>
#include <vector>
#endif

/**
 * @class Database
 * @brief Connection pool wrapper for PostgreSQL with schema bootstrap helpers.
 */
class Database {
public:
    /**
     * @brief Create a database pool using the provided libpq connection string.
     * @param conninfo libpq-formatted connection information.
     * @throws std::runtime_error when the initial connection cannot be established.
     */
    explicit Database(const std::string& conninfo);

    /**
     * @brief Access the primary connection (non-pooled) for one-off operations.
     */
    pqxx::connection& get();

    /**
     * @brief Acquire a pooled connection for multi-threaded work.
     * @return Borrowed connection pointer that must be returned with release().
     */
    pqxx::connection* acquire();

    /**
     * @brief Return a previously acquired connection back to the pool.
     * @param conn Connection pointer obtained via acquire().
     */
    void release(pqxx::connection* conn);

    /**
     * @brief Ensure the database schema matches the service expectations.
     *
     * Idempotently creates tables, indexes, and constraints, and migrates legacy columns.
     */
    void initializeSchema();
private:
#ifndef UNIT_TESTING
    pqxx::connection conn_;
    std::string conninfo_;
    std::vector<std::unique_ptr<pqxx::connection>> pool_;
    std::vector<pqxx::connection*> available_;
    std::mutex pool_mutex_;
#endif
};

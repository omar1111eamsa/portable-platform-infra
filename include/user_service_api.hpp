#pragma once

#include "db.hpp"
#include "user_controller.hpp"
#include "auth_manager.hpp"
#include "subscription_manager.hpp"
#include "external_auth_manager.hpp"

/**
 * @class UserServiceAPI
 * @brief Wires controllers and infrastructure into an HTTP server.
 */
class UserServiceAPI {
public:
    /**
     * @brief Construct the API facade using shared service components.
     */
    UserServiceAPI(Database& db,
                   UserController& userCtrl,
                   SubscriptionManager& subsMgr,
                   AuthManager& auth,
                   ExternalAuthManager& externalAuth);

    /**
     * @brief Start listening for HTTP traffic.
     * @param host Interface address to bind.
     * @param port TCP port to bind.
     */
    void start(const std::string& host, int port);

private:
    Database& db_;
    UserController& userCtrl_;
    SubscriptionManager& subsMgr_;
    AuthManager& auth_;
    ExternalAuthManager& externalAuth_;
};

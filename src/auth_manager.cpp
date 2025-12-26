#include "auth_manager.hpp"
#include <fstream>
#include <sstream>
#include <iostream>

AuthManager::AuthManager(const std::string& privateKeyPath, const std::string& publicKeyPath) {
    std::ifstream priv(privateKeyPath);
    std::ifstream pub(publicKeyPath);

    if (!priv.is_open() || !pub.is_open())
        throw std::runtime_error("❌ Cannot read JWT key files.");

    std::stringstream privBuf, pubBuf;
    privBuf << priv.rdbuf();
    pubBuf << pub.rdbuf();

    privateKey_ = privBuf.str();
    publicKey_ = pubBuf.str();
}

std::string AuthManager::generateToken(const std::string& userId,
                                       const std::string& role,
                                       const std::string& plan,
                                       int expirySeconds) {
    using namespace std::chrono;
    auto now = system_clock::now();
    auto token = jwt::create()
        .set_issuer("cqos")
        .set_type("JWS")
        .set_subject(userId)
        .set_audience("cqos-internal")
        .set_issued_at(now)
        .set_expires_at(now + seconds(expirySeconds))
        .set_payload_claim("role", jwt::claim(role))
        .set_payload_claim("plan", jwt::claim(plan))
        .sign(jwt::algorithm::rs256(publicKey_, privateKey_, "", ""));

    return token;
}

#pragma GCC push_options
#pragma GCC optimize("O3", "unroll-loops", "omit-frame-pointer", "inline")
bool AuthManager::validateToken(const std::string& token,
                                std::string& outUserId,
                                std::string& outRole,
                                std::string& outPlan) {
    try {
        // Use __restrict__ to help compiler optimize memory access
        const std::string* __restrict__ tokenPtr = &token;
        std::string* __restrict__ userIdPtr = &outUserId;
        std::string* __restrict__ rolePtr = &outRole;
        std::string* __restrict__ planPtr = &outPlan;
        
        // Pre-allocate memory to avoid reallocations
        userIdPtr->reserve(36);  // UUID length
        rolePtr->reserve(10);    // Typical role length
        planPtr->reserve(10);    // Typical plan length
        
        auto decoded = jwt::decode(*tokenPtr);

        // Cache the verifier to avoid reconstruction
        static thread_local auto verifier = jwt::verify()
            .allow_algorithm(jwt::algorithm::rs256(publicKey_, privateKey_, "", ""))
            .with_issuer("cqos");

        // Prefetch the next memory access
        __builtin_prefetch(&decoded, 0, 3);
        
        verifier.verify(decoded);

        *userIdPtr = decoded.get_subject();
        if (decoded.has_payload_claim("role")) {
            *rolePtr = decoded.get_payload_claim("role").as_string();
        } else {
            rolePtr->clear();
        }
        *planPtr = decoded.get_payload_claim("plan").as_string();
        return true;
    } catch (const std::exception& e) {
        std::cerr << "❌ Token validation failed: " << e.what() << std::endl;
        return false;
    }
}
#pragma GCC pop_options

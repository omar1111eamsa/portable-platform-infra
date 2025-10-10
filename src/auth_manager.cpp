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

bool AuthManager::validateToken(const std::string& token,
                                std::string& outUserId,
                                std::string& outRole,
                                std::string& outPlan) {
    try {
        auto decoded = jwt::decode(token);

        auto verifier = jwt::verify()
            .allow_algorithm(jwt::algorithm::rs256(publicKey_, privateKey_, "", ""))
            .with_issuer("cqos");

        verifier.verify(decoded);

        outUserId = decoded.get_subject();
        if (decoded.has_payload_claim("role")) {
            outRole = decoded.get_payload_claim("role").as_string();
        } else {
            outRole.clear();
        }
        outPlan = decoded.get_payload_claim("plan").as_string();
        return true;
    } catch (const std::exception& e) {
        std::cerr << "❌ Token validation failed: " << e.what() << std::endl;
        return false;
    }
}

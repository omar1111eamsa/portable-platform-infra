#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include "bcrypt_utils.hpp"

#include <crypt.h>
#include <sodium.h>

#include <array>
#include <cstring>
#include <iomanip>
#include <sstream>
#include <stdexcept>
#include <string>

namespace {

constexpr std::size_t kSaltBytes = 16;
constexpr std::size_t kEncodedSaltLength = 22;
constexpr char kBcryptAlphabet[] =
    "./ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";

std::string encodeBcryptBase64(const unsigned char* data, std::size_t len) {
    std::string out;
    out.reserve(((len + 2) / 3) * 4);

    std::size_t i = 0;
    while (i < len) {
        unsigned int c1 = data[i++];
        unsigned int c2 = 0;

        out.push_back(kBcryptAlphabet[(c1 >> 2) & 0x3f]);
        c2 = (c1 & 0x03) << 4;

        if (i >= len) {
            out.push_back(kBcryptAlphabet[c2 & 0x3f]);
            break;
        }

        unsigned int c3 = data[i++];
        c2 |= (c3 >> 4) & 0x0f;
        out.push_back(kBcryptAlphabet[c2 & 0x3f]);

        unsigned int c4 = (c3 & 0x0f) << 2;

        if (i >= len) {
            out.push_back(kBcryptAlphabet[c4 & 0x3f]);
            break;
        }

        unsigned int c5 = data[i++];
        c4 |= (c5 >> 6) & 0x03;
        out.push_back(kBcryptAlphabet[c4 & 0x3f]);
        out.push_back(kBcryptAlphabet[c5 & 0x3f]);
    }

    if (out.size() > kEncodedSaltLength) {
        out.resize(kEncodedSaltLength);
    }
    return out;
}

int clampCost(int cost) {
    if (cost < 10) return 10;
    if (cost > 31) return 31;
    return cost;
}

std::string buildSalt(int cost) {
    std::array<unsigned char, kSaltBytes> saltBytes{};
    randombytes_buf(saltBytes.data(), saltBytes.size());

    std::ostringstream oss;
    oss << "$2b$" << std::setw(2) << std::setfill('0') << clampCost(cost) << "$";
    oss << encodeBcryptBase64(saltBytes.data(), saltBytes.size());
    return oss.str();
}

} // namespace

namespace bcrypt_utils {

std::string hashPassword(const std::string& password, int cost) {
    if (password.empty()) {
        throw std::invalid_argument("Password must not be empty");
    }

    std::string salt = buildSalt(cost);

    struct crypt_data data;
    data.initialized = 0;

    char* result = crypt_r(password.c_str(), salt.c_str(), &data);
    if (!result) {
        throw std::runtime_error("bcrypt hashing failed");
    }

    return std::string(result);
}

bool verifyPassword(const std::string& password, const std::string& hash) {
    if (password.empty() || hash.empty()) {
        return false;
    }

    struct crypt_data data;
    data.initialized = 0;

    char* result = crypt_r(password.c_str(), hash.c_str(), &data);
    if (!result) {
        return false;
    }

    return std::strcmp(result, hash.c_str()) == 0;
}

} // namespace bcrypt_utils

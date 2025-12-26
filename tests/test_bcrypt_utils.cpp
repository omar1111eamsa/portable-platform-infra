#include "test_framework.hpp"
#include "bcrypt_utils.hpp"

#include <string>

TEST_CASE(test_bcrypt_roundtrip_success) {
    const std::string password = "Secur3P@ssw0rd!";
    std::string hash = bcrypt_utils::hashPassword(password, 12);

    REQUIRE(!hash.empty());
    CHECK(hash != password);
    CHECK(hash.rfind("$2", 0) == 0);
    CHECK(bcrypt_utils::verifyPassword(password, hash));
}

TEST_CASE(test_bcrypt_rejects_wrong_password) {
    const std::string password = "original";
    const std::string wrong = "different";

    std::string hash = bcrypt_utils::hashPassword(password, 10);
    CHECK(!bcrypt_utils::verifyPassword(wrong, hash));
}

TEST_CASE(test_bcrypt_cost_lower_bound_enforced) {
    const std::string password = "costcheck";

    std::string low = bcrypt_utils::hashPassword(password, 5);
    CHECK(low.substr(0, 7) == "$2b$10$");

    std::string normal = bcrypt_utils::hashPassword(password, 14);
    CHECK(normal.substr(0, 7) == "$2b$14$");
}

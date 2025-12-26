#include "test_framework.hpp"

#include <sodium.h>

int main() {
    if (sodium_init() < 0) {
        std::cerr << "libsodium initialization failed" << std::endl;
        return 1;
    }

    int failures = 0;
    auto& tests = testfw::registry();
    for (const auto& test : tests) {
        try {
            test.func();
            std::cout << "[PASS] " << test.name << std::endl;
        } catch (const std::exception& e) {
            ++failures;
            std::cerr << "[FAIL] " << test.name << ": " << e.what() << std::endl;
        }
    }

    std::cout << tests.size() << " tests executed, " << failures << " failures" << std::endl;
    return failures == 0 ? 0 : 1;
}

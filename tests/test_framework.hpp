#pragma once

#include <functional>
#include <iostream>
#include <stdexcept>
#include <string>
#include <sstream>
#include <vector>

namespace testfw {

struct TestCase {
    std::string name;
    std::function<void()> func;
};

inline std::vector<TestCase>& registry() {
    static std::vector<TestCase> tests;
    return tests;
}

inline bool registerTest(const std::string& name, std::function<void()> func) {
    registry().push_back(TestCase{name, std::move(func)});
    return true;
}

class AssertionFailure : public std::runtime_error {
public:
    explicit AssertionFailure(const std::string& msg) : std::runtime_error(msg) {}
};

namespace detail {
    template <typename T>
    std::string toString(const T& value) {
        std::ostringstream oss;
        oss << value;
        return oss.str();
    }
}

} // namespace testfw

#define TEST_CASE(NAME)                                                        \
    static void NAME();                                                        \
    static bool NAME##_registered = testfw::registerTest(#NAME, NAME);         \
    static void NAME()

#define REQUIRE(COND)                                                          \
    do {                                                                       \
        if (!(COND)) {                                                         \
            throw testfw::AssertionFailure(                                    \
                std::string("Requirement failed: ") + #COND +                  \
                " at " + __FILE__ + ":" + std::to_string(__LINE__));           \
        }                                                                      \
    } while (0)

#define CHECK_EQ(A, B)                                                         \
    do {                                                                       \
        auto _a = (A);                                                         \
        auto _b = (B);                                                         \
        if (!(_a == _b)) {                                                     \
            throw testfw::AssertionFailure(                                    \
                std::string("CHECK_EQ failed: ") + #A " == " #B +              \
                " (" + testfw::detail::toString(_a) + " vs " +                \
                testfw::detail::toString(_b) + ") at " + __FILE__ +            \
                ":" + std::to_string(__LINE__));                              \
        }                                                                      \
    } while (0)

#define CHECK_NE(A, B)                                                         \
    do {                                                                       \
        auto _a = (A);                                                         \
        auto _b = (B);                                                         \
        if (_a == _b) {                                                        \
            throw testfw::AssertionFailure(                                    \
                std::string("CHECK_NE failed: ") + #A " != " #B +              \
                " (" + testfw::detail::toString(_a) + " vs " +                \
                testfw::detail::toString(_b) + ") at " + __FILE__ +            \
                ":" + std::to_string(__LINE__));                              \
        }                                                                      \
    } while (0)

#define CHECK(COND)                                                            \
    do {                                                                       \
        if (!(COND)) {                                                         \
            throw testfw::AssertionFailure(                                    \
                std::string("Check failed: ") + #COND +                        \
                " at " + __FILE__ + ":" + std::to_string(__LINE__));           \
        }                                                                      \
    } while (0)

#include "test_framework.hpp"
#include "logger.hpp"

#include <iostream>
#include <sstream>

namespace {

class CoutRedirect {
public:
    explicit CoutRedirect(std::ostream& stream)
        : stream_(stream), old_buf_(stream.rdbuf(buffer_.rdbuf())) {}

    ~CoutRedirect() {
        stream_.rdbuf(old_buf_);
    }

    std::string str() const { return buffer_.str(); }

private:
    std::ostream& stream_;
    std::ostringstream buffer_;
    std::streambuf* old_buf_;
};

} // namespace

TEST_CASE(test_logger_basic_output) {
    CoutRedirect redirect(std::cout);
    log_event(LogLevel::kInfo, "test message", { {"component", "unit"} });
    auto out = redirect.str();
    CHECK(out.find("test message") != std::string::npos);
    CHECK(out.find("\"component\":\"unit\"") != std::string::npos);
}

TEST_CASE(test_logger_masks_sensitive_fields) {
    CoutRedirect redirect(std::cout);
    log_event(LogLevel::kWarn, "mask test", {
        {"password", "SuperSecret"},
        {"token", "abc123"},
        {"status", "ok"}
    });

    auto out = redirect.str();
    CHECK(out.find("SuperSecret") == std::string::npos);
    CHECK(out.find("abc123") == std::string::npos);
    CHECK(out.find("\"password\":\"***\"") != std::string::npos);
    CHECK(out.find("\"token\":\"***\"") != std::string::npos);
    CHECK(out.find("\"status\":\"ok\"") != std::string::npos);
}

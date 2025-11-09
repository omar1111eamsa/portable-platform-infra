#include "test_framework.hpp"
#include "validation.hpp"

TEST_CASE(test_validation_accepts_well_formed_emails) {
    CHECK(validation::is_valid_email("user@example.com"));
    CHECK(validation::is_valid_email("cap.quant+alerts@sub.domain.io"));
}

TEST_CASE(test_validation_rejects_bad_emails) {
    CHECK(!validation::is_valid_email("no-at-symbol"));
    CHECK(!validation::is_valid_email("user@localhost"));
    CHECK(!validation::is_valid_email("user@domain"));
    CHECK(!validation::is_valid_email("user@domain..com"));
}

TEST_CASE(test_password_strength_rules) {
    auto ok = validation::validate_password_strength("StrongPass123!");
    CHECK(!ok.has_value());

    CHECK(validation::validate_password_strength("short1A!").has_value());
    CHECK(validation::validate_password_strength("alllowercasepassword!1").has_value());
    CHECK(validation::validate_password_strength("ALLUPPERCASE123!").has_value());
    CHECK(validation::validate_password_strength("NoDigitsHere!").has_value());
    CHECK(validation::validate_password_strength("Nospecials12345").has_value());
    CHECK(validation::validate_password_strength("Space InPassword1!").has_value());
}

#include "test_framework.hpp"
#include "metrics.hpp"

TEST_CASE(test_metrics_registry_records_success_and_failure) {
    auto& registry = MetricsRegistry::instance();
    registry.resetForTesting();

    {
        EndpointTimer timer("metrics.success");
        timer.markSuccess();
    }

    {
        EndpointTimer timer("metrics.failure");
        // no markSuccess -> failure recorded
    }

    auto snapshot = registry.snapshot();
    REQUIRE(snapshot.contains("metrics.success"));
    REQUIRE(snapshot.contains("metrics.failure"));

    const auto& success = snapshot.at("metrics.success");
    CHECK_EQ(success.at("requests").get<uint64_t>(), static_cast<uint64_t>(1));
    CHECK_EQ(success.at("successes").get<uint64_t>(), static_cast<uint64_t>(1));
    CHECK_EQ(success.at("failures").get<uint64_t>(), static_cast<uint64_t>(0));

    const auto& failure = snapshot.at("metrics.failure");
    CHECK_EQ(failure.at("requests").get<uint64_t>(), static_cast<uint64_t>(1));
    CHECK_EQ(failure.at("successes").get<uint64_t>(), static_cast<uint64_t>(0));
    CHECK_EQ(failure.at("failures").get<uint64_t>(), static_cast<uint64_t>(1));
    CHECK(failure.at("avg_latency_ms").get<double>() >= 0.0);
}

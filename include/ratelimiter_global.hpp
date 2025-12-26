#pragma once

#include "ratelimiter.hpp"

/**
 * @brief Global RateLimiter pointer initialised during service startup.
 *
 * The pointer is populated in main() and consumed by request handlers. It remains
 * a raw pointer to avoid static destruction ordering issues.
 */
extern RateLimiter* gRateLimiter;

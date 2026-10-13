#include "core/core_info.h"

#include <doctest.h>

#include <cstdint>
#include <limits>
#include <regex>

TEST_CASE("version is <semver>+<7-char sha or nogit>") {
	const std::string version = lb::core::version_string();
	CHECK(std::regex_match(version, std::regex(R"(\d+\.\d+\.\d+(-[0-9A-Za-z.]+)?\+([0-9a-f]{7}|nogit))")));
}

TEST_CASE("build type matches LB_DEBUG_TOOLS") {
#ifdef LB_DEBUG_TOOLS
	CHECK(std::string(lb::core::build_type()) == "debug");
	CHECK(lb::core::has_debug_tools());
#else
	CHECK(std::string(lb::core::build_type()) == "release");
	CHECK_FALSE(lb::core::has_debug_tools());
#endif
}

TEST_CASE("add_i64 wraps like two's complement") {
	constexpr int64_t max = std::numeric_limits<int64_t>::max();
	constexpr int64_t min = std::numeric_limits<int64_t>::min();
	CHECK(lb::core::add_i64_wrapping(2, 3) == 5);
	CHECK(lb::core::add_i64_wrapping(max, 1) == min);
	CHECK(lb::core::add_i64_wrapping(min, -1) == max);
	CHECK(lb::core::add_i64_wrapping(-1, 1) == 0);
	CHECK(lb::core::add_i64_wrapping(max, max) == -2);
}

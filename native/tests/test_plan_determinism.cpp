// GEN-08: the run header is a pure function of the seed and the list, serialised canonically: the
// same inputs give the same bytes (golden digests, checked on Linux and Windows alike), and the
// bytes round-trip exactly; anything but one whole header is refused.

#include "plan_fixture.h"

#include <doctest.h>

#include <cstdio>

using namespace plan_fixture;

namespace {

RunHeader full_header(uint64_t seed, int32_t kind) {
	RunHeader h = planned(seed, kind);
	h.draw = {"dry_stores"};
	h.staging = "new_brigade";
	h.hard_variant = "";
	h.template_version = "86cf2dd14de96ec0";
	h.data_version = "tuning:abc";
	h.homes["roosts"] = {1, 2, 3};
	return h;
}

} // namespace

TEST_CASE("GEN-08 the header round-trips byte for byte") {
	for (int32_t kind = 0; kind < 3; kind++) {
		const RunHeader h = full_header(9001 + static_cast<uint64_t>(kind), kind);
		REQUIRE(h.plan.error.empty());
		const std::vector<uint8_t> bytes = serialise_header(h);
		const std::optional<RunHeader> back = parse_header(bytes);
		REQUIRE(back.has_value());
		CHECK(serialise_header(*back) == bytes);
		CHECK(back->seed == h.seed);
		CHECK(back->jobs == h.jobs);
		CHECK(back->plan.sites.size() == h.plan.sites.size());
		CHECK(back->plan.spines.size() == h.plan.spines.size());
		CHECK(back->homes == h.homes);
		CHECK(back->generator_version == GENERATOR_VERSION);
		CHECK(back->hash_version == lb::core::HASH_VERSION);
		std::vector<uint8_t> longer = bytes;
		longer.push_back(0);
		CHECK_FALSE(parse_header(longer).has_value());
		std::vector<uint8_t> shorter(bytes.begin(), bytes.end() - 1);
		CHECK_FALSE(parse_header(shorter).has_value());
		std::vector<uint8_t> wrong = bytes;
		wrong[0] = 'X';
		CHECK_FALSE(parse_header(wrong).has_value());
	}
}

TEST_CASE("GEN-08 the same seed and list give the same header, and other seeds other plans") {
	const std::vector<uint8_t> a = serialise_header(full_header(77, 1));
	const std::vector<uint8_t> b = serialise_header(full_header(77, 1));
	CHECK(a == b);
	CHECK(serialise_header(full_header(78, 1)) != a);
}

TEST_CASE("GEN-08 golden headers, identical on every platform") {
	// Recorded on Linux (generator 3, GEN-10); the round's Windows run must match them bit for bit.
	const uint64_t golden[3][4] = {
			{0x65C23CFD939D0E75ULL, 0x8DF4A37ED48E1AD3ULL, 0x2A8F576519DAE1C1ULL, 0x8AC3523F05963CE0ULL},
			{0xF55DC5BA349A1242ULL, 0x975673B79138F29EULL, 0x17B9EFCAD2D0A0F4ULL, 0x37C82693C2ECC46BULL},
			{0xF1A0FDF9F34B24FDULL, 0x180DF914B69B976DULL, 0x19FBC675580B008EULL, 0x967E7EF4DB48272EULL},
	};
	for (int32_t kind = 0; kind < 3; kind++) {
		for (uint64_t s = 0; s < 4; s++) {
			const RunHeader h = full_header(1000 + s, kind);
			REQUIRE(h.plan.error.empty());
			const uint64_t d = header_digest(h);
			char text[24];
			std::snprintf(text, sizeof(text), "0x%016llX", static_cast<unsigned long long>(d));
			MESSAGE("list ", kind, " seed ", 1000 + s, ": ", text);
			CHECK(d == golden[kind][s]);
		}
	}
}

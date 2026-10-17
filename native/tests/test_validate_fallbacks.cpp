// GEN-12: every biome's plain fallback passes phase 1 for every socket set (each edge shut or open
// at 5, 10 or 15) at every width, and a fallback with a gap fails, naming the socket set.

#include "validate_fixture.h"

#include <doctest.h>

using namespace validate_fixture;

TEST_CASE("GEN-12 every biome's plain fallback passes phase 1 for every socket set and width") {
	const std::shared_ptr<TemplateSet> set = main_road_fixture::road_set();
	const SocketParams sockets;
	const ValidatorParams vp;
	for (const char *biome : {"pit_bottom", "seam", "old_workings", "black_seam", "old_mens"}) {
		size_t checked = 0;
		const std::vector<CoverageFailure> failures = fallback_coverage(*set, biome, {1, 2, 3}, sockets, vp, &checked);
		CHECK(checked == 10000); // (1 + 3 offsets x 3 widths) ^ 4 edges
		CHECK_MESSAGE(failures.empty(), biome << ": " << (failures.empty() ? std::string() : describe(failures.front().verdict)));
	}
}

TEST_CASE("GEN-12 a fallback with a gap, or none, fails its coverage") {
	Spec gap = fallback_spec();
	gap.id = "seam_gappy_fallback";
	// The road along 15 stops short of the east edge, and no stub opens there.
	gap.stubs.erase(std::remove_if(gap.stubs.begin(), gap.stubs.end(), [](const Stub &s) { return s.edge == Edge::EAST && s.offset == 15; }),
			gap.stubs.end());
	for (int y = 14; y <= 16; y++) {
		gap.rows[static_cast<size_t>(y)][18] = '#';
		gap.rows[static_cast<size_t>(y)][19] = '#';
	}
	auto set = std::make_shared<TemplateSet>();
	REQUIRE(set->load(encode_pack("gappy", {make(gap)})));
	size_t checked = 0;
	const std::vector<CoverageFailure> failures = fallback_coverage(*set, "seam", {1, 2, 3}, SocketParams{}, ValidatorParams{}, &checked);
	CHECK(checked == 10000);
	// Every set with the east open at 15: 3 widths x 10^3 other edges.
	CHECK(failures.size() == 3000);
	for (const CoverageFailure &f : failures) {
		const Socket &east = f.sockets[static_cast<size_t>(Edge::EAST)];
		CHECK(east.open);
		CHECK(east.offset == 15);
		CHECK(f.verdict.check == Check::THROATS);
	}
	const std::vector<CoverageFailure> none = fallback_coverage(*set, "old_mens", {1}, SocketParams{}, ValidatorParams{});
	REQUIRE(none.size() == 1);
	CHECK(none.front().verdict.detail.find("no plain fallback") != std::string::npos);
}

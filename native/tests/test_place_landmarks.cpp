// GEN-10's landmarks (Gameplay §12.7): every cell has exactly one, at its landmark site; no two
// cells within 2 (Chebyshev) share one, and they recur farther off.

#include "place_fixture.h"

#include <doctest.h>

#include <map>

using namespace place_fixture;

TEST_CASE("GEN-10 one landmark a cell, never twice within 2 cells") {
	const PlacementParams p;
	World w;
	int64_t recurring = 0;
	for (uint64_t s = 0; s < 100; s++) {
		reset(w, lb::core::mix64(s + 0x1A4D), p);
		std::map<Coord, int32_t> variant;
		for (int64_t y = -7; y <= 7; y++) {
			for (int64_t x = -7; x <= 7; x++) {
				if (x == 0 && y == 0) {
					continue;
				}
				const std::vector<Placement> marks = of_kind(place_cell(w, p, {x, y}), PlacedKind::LANDMARK);
				REQUIRE(marks.size() == 1);
				CHECK(marks[0].thing == "broken_tub");
				CHECK(marks[0].variant >= 0);
				CHECK(marks[0].variant < p.landmark_palette);
				variant[{x, y}] = marks[0].variant;
			}
		}
		for (const auto &[a, va] : variant) {
			for (const auto &[b, vb] : variant) {
				if (a == b) {
					continue;
				}
				const int64_t cheb = std::max(std::abs(a.x - b.x), std::abs(a.y - b.y));
				if (cheb <= 2) {
					CHECK(va != vb);
				} else if (va == vb) {
					recurring++;
				}
			}
		}
		// The same cell, the same landmark, call after call.
		CHECK(landmark_variant(w.head.seed, {3, 4}, 25) == variant[{3, 4}]);
	}
	CHECK(recurring > 0);
}

TEST_CASE("GEN-10 the landmark palette is permuted per run") {
	int64_t differ = 0;
	for (uint64_t s = 0; s < 50; s++) {
		differ += landmark_variant(s, {1, 1}, 25) != landmark_variant(s + 1, {1, 1}, 25) ? 1 : 0;
	}
	CHECK(differ > 25);
}

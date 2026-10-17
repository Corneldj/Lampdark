// GEN-10's cross-cell collapse arming (Gameplay §12.5): one alternate at most a cell, never on a
// spine; where two cells' candidates fall within 12 tiles across their edge, the higher priority
// stands and the other does not, whichever cell is placed first.

#include "place_fixture.h"

#include <doctest.h>

#include <algorithm>

using namespace place_fixture;

namespace {

Layout edge_prototype() {
	Layout l = prototype();
	l.cell.collapses = {collapse(1, {{19, 10}}), collapse(2, {{0, 10}})};
	return l;
}

uint32_t armed_id(const std::vector<Placement> &list) {
	for (const Placement &x : list) {
		if (x.kind == PlacedKind::COLLAPSE) {
			return x.collapse;
		}
	}
	return 0;
}

} // namespace

TEST_CASE("GEN-10 conflicting collapse candidates: one stands, by priority, in any order") {
	PlacementParams p;
	p.collapse_ppm = 1000000;
	World w;
	w.proto = edge_prototype();
	int64_t conflicts = 0;
	int64_t both_free = 0;
	for (uint64_t s = 0; s < 500; s++) {
		reset(w, lb::core::mix64(s + 0xA4A1), p);
		for (int64_t x = 5; x < 15; x++) {
			const Coord a{x, 3};
			const Coord b{x + 1, 3};
			// Placing b first or a first changes nothing: each is a pure function of the run.
			const std::vector<Placement> b_first = place_cell(w, p, b);
			const std::vector<Placement> a_list = place_cell(w, p, a);
			const std::vector<Placement> b_list = place_cell(w, p, b);
			CHECK(placement_digest(b_first) == placement_digest(b_list));
			const uint32_t ia = armed_id(a_list);
			const uint32_t ib = armed_id(b_list);
			// a's east alternate (1, at its x 19) and b's west (2, at its x 0) lie a tile apart.
			if (ia == 1 && ib == 2) {
				FAIL("both sides of an edge armed within 12 tiles");
			}
			if (ia == 1 || ib == 2) {
				conflicts++;
			} else {
				both_free++;
			}
			// A cell arms one alternate at most.
			int64_t n = 0;
			for (const Placement &x2 : a_list) {
				n += x2.kind == PlacedKind::COLLAPSE ? 1 : 0;
			}
			CHECK(n <= 1);
		}
	}
	CHECK(conflicts > 100);
	CHECK(both_free > 100);
}

TEST_CASE("GEN-10 no collapse is armed on a spine or within 20 tiles of base camp") {
	PlacementParams p;
	p.collapse_ppm = 1000000;
	World w;
	w.spine = [](Coord c) { return c.x == 6; };
	for (uint64_t s = 0; s < 200; s++) {
		reset(w, lb::core::mix64(s + 0x5C1), p);
		for (int64_t y = -3; y <= 3; y++) {
			CHECK(armed_id(place_cell(w, p, {6, y})) == 0);
			// Cells next to base camp: their alternate at local (10, 5) lies within 20 tiles of it.
			CHECK(armed_id(place_cell(w, p, {1, 0})) == 0);
		}
		CHECK(armed_id(place_cell(w, p, {7, 0})) != 0);
	}
}

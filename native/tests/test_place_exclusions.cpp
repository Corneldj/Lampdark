// GEN-10: the exclusions hold in every cell (Gameplay §12.5, §12.3): nothing in base camp or on
// an armed collapse's tiles; no gas or trap in ring 0; no gas on a spine; no remains in blackdamp;
// collapse points 20 or more tiles from base camp, 12 or more apart and 7 or more from every pit
// phone, across cell edges too.

#include "place_fixture.h"

#include <doctest.h>

#include <algorithm>

using namespace place_fixture;

namespace {

std::vector<Coord> tiles_of(const Placement &x) {
	std::vector<Coord> out;
	for (int32_t j = 0; j < x.h; j++) {
		for (int32_t i = 0; i < x.w; i++) {
			out.push_back({x.tile.x + i, x.tile.y + j});
		}
	}
	return out;
}

int64_t d2(Coord a, Coord b) { return (a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y); }

// The fixture with two collapse alternates on the west-east road, one at each edge ((0, 10) and
// (19, 10)): a cell arming its east one and its east neighbour its west one meet across the edge.
Layout edge_prototype() {
	Layout l = prototype();
	l.cell.collapses = {collapse(1, {{19, 10}}), collapse(2, {{0, 10}})};
	return l;
}

} // namespace

TEST_CASE("GEN-10 exclusions hold in every cell") {
	const PlacementParams p;
	World w;
	w.spine = [](Coord c) { return c.y == 2 && c.x % 3 == 0; };
	int64_t collapses = 0;
	int64_t blackdamp = 0;
	for (uint64_t s = 0; s < 400; s++) {
		reset(w, lb::core::mix64(s + 0xE7C1), p);
		for (int64_t y = -4; y <= 4; y++) {
			for (int64_t x = -6; x <= 14; x++) {
				const Coord c{x, y};
				const CellFacts f = w.facts(c);
				const std::vector<Placement> list = place_cell(w, p, c);
				if (c == Coord{0, 0}) {
					CHECK(list.empty());
					continue;
				}
				std::vector<Coord> armed;
				std::vector<Placement> damp;
				for (const Placement &x2 : list) {
					if (x2.kind == PlacedKind::COLLAPSE) {
						armed = tiles_of(x2);
						collapses++;
						CHECK_FALSE(f.spine);
					}
					if (x2.kind == PlacedKind::BLACKDAMP) {
						damp.push_back(x2);
						blackdamp++;
					}
				}
				for (const Placement &x2 : list) {
					const bool gas = x2.kind == PlacedKind::FIREDAMP || x2.kind == PlacedKind::BLACKDAMP;
					const bool trap = x2.kind == PlacedKind::MAN_TRAP || x2.kind == PlacedKind::STAPLE_PIT || x2.kind == PlacedKind::SUMP_MUD;
					if (gas || trap) {
						CHECK(f.ring >= 1);
					}
					if (gas) {
						CHECK_FALSE(f.spine);
					}
					if (x2.kind != PlacedKind::COLLAPSE) {
						for (const Coord &t : armed) {
							CHECK_FALSE(x2.covers(t));
						}
					}
					if (x2.kind == PlacedKind::REMAINS) {
						for (const Placement &g : damp) {
							CHECK_FALSE(g.covers(x2.tile));
						}
					}
					// Base camp is cell (0, 0): nothing of a neighbour reaches into it.
					for (const Coord &t : tiles_of(x2)) {
						CHECK_FALSE(lb::core::world::cell_of(t) == Coord{0, 0});
					}
				}
			}
		}
	}
	CHECK(collapses > 1000);
	CHECK(blackdamp > 100);
}

TEST_CASE("GEN-10 collapse points keep their distances across cell edges") {
	PlacementParams p;
	p.collapse_ppm = 1000000; // every candidate rolls: only the rules thin them
	World w;
	w.proto = edge_prototype();
	// The wall fixture right beside the west edge's road, where the neighbour's collapse lies.
	for (Anchor &a : w.proto.cell.anchors) {
		if (a.type == AnchorType::WALL_FIXTURE) {
			a.x = 1;
			a.y = 9;
		}
	}
	int64_t armed_total = 0;
	for (uint64_t s = 0; s < 200; s++) {
		reset(w, lb::core::mix64(s * 3 + 0xC011), p);
		std::vector<std::pair<Coord, std::vector<Coord>>> armed;
		std::vector<Coord> phones;
		for (int64_t y = -3; y <= 3; y++) {
			for (int64_t x = -3; x <= 12; x++) {
				for (const Placement &x2 : place_cell(w, p, {x, y})) {
					if (x2.kind == PlacedKind::COLLAPSE) {
						armed.push_back({{x, y}, tiles_of(x2)});
					}
					if (x2.kind == PlacedKind::PHONE) {
						phones.push_back(x2.tile);
					}
				}
			}
		}
		armed_total += static_cast<int64_t>(armed.size());
		for (size_t i = 0; i < armed.size(); i++) {
			for (const Coord &t : armed[i].second) {
				// 20 or more from base camp's cell, 7 or more from every phone.
				const int64_t nx = std::clamp<int64_t>(t.x, 0, 19);
				const int64_t ny = std::clamp<int64_t>(t.y, 0, 19);
				CHECK(d2(t, {nx, ny}) >= 20 * 20);
				for (const Coord &ph : phones) {
					CHECK(d2(t, ph) >= 7 * 7);
				}
				for (size_t j = i + 1; j < armed.size(); j++) {
					for (const Coord &u : armed[j].second) {
						CHECK(d2(t, u) >= 12 * 12);
					}
				}
			}
		}
	}
	CHECK(armed_total > 200);
}

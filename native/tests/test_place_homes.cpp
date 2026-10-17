// GEN-10's run-start homes (Gameplay §8.1, §7.2, §6.6, §4.4, §10.10): 2-4 roosts within 60 tiles
// of the hoard (fewer only when fewer candidates exist, reported), the start a roost or the hoard,
// a staged run 1's roosts 100+ tiles from the shaft; at most one electric lamp a run, in ring 2
// or the next, about half the runs; the near-gate phones on gate roads; the homes round-trip
// through the header. The revolver and its boxes lie on their planned cells.

#include "place_fixture.h"

#include <doctest.h>

using namespace place_fixture;

namespace {

int64_t d2(int64_t ax, int64_t ay, int64_t bx, int64_t by) { return (ax - bx) * (ax - bx) + (ay - by) * (ay - by); }

} // namespace

TEST_CASE("GEN-10 roosts near the hoard, the start among them") {
	const PlacementParams p;
	World w;
	int64_t lamps = 0;
	const int64_t runs = 2000;
	for (int64_t s = 0; s < runs; s++) {
		reset(w, lb::core::mix64(static_cast<uint64_t>(s) * 5 + 0x4005), p);
		const Homes h = make_homes(w, p);
		REQUIRE(h.hoard.has_value());
		CHECK(h.roosts.size() >= 2);
		CHECK(h.roosts.size() <= 4);
		CHECK_FALSE(h.roosts_short);
		for (const TileBox &b : h.roosts) {
			// Centre to centre, doubled.
			CHECK(d2(2 * b.x + b.w, 2 * b.y + b.h, 2 * h.hoard->x + 1, 2 * h.hoard->y + 1) <= 4 * 60 * 60);
			CHECK(lb::core::world::cell_of({b.x, b.y}) != Coord{8, 0});
		}
		CHECK(h.start_roost >= -1);
		CHECK(h.start_roost < static_cast<int32_t>(h.roosts.size()));
		CHECK(h.gate_phones.size() <= 2);
		for (const Coord &t : h.gate_phones) {
			CHECK(lb::core::world::cell_chebyshev(lb::core::world::cell_of(t), {0, 0}) <= 2);
			CHECK(lb::core::world::cell_of(t) != Coord{0, 0});
		}
		if (h.electric_lamp) {
			lamps++;
			const int64_t ring = ring_of_cell(*h.electric_lamp, w.bounds);
			CHECK(ring >= 2);
			CHECK(ring <= 3);
		}
		// Through the header and back.
		RunHeader copy = w.head;
		write_homes(h, copy);
		const Homes back = read_homes(copy);
		CHECK(back.roosts == h.roosts);
		CHECK(back.start_roost == h.start_roost);
		CHECK(back.gate_phones == h.gate_phones);
		CHECK(back.electric_lamp == h.electric_lamp);
		const std::optional<RunHeader> parsed = parse_header(serialise_header(copy));
		REQUIRE(parsed.has_value());
		CHECK(read_homes(*parsed).roosts == h.roosts);
	}
	INFO(lamps << " electric lamps in " << runs << " runs");
	CHECK(lamps >= runs * 45 / 100);
	CHECK(lamps <= runs * 55 / 100);
}

TEST_CASE("GEN-10 staged run 1's roosts lie 100+ tiles from the shaft") {
	PlacementParams p;
	p.roost_min_from_shaft = 100;
	World w;
	for (int64_t s = 0; s < 500; s++) {
		reset(w, lb::core::mix64(static_cast<uint64_t>(s) + 0x57A6), p);
		const Homes h = make_homes(w, p);
		for (const TileBox &b : h.roosts) {
			CHECK(d2(2 * b.x + b.w, 2 * b.y + b.h, lb::core::world::SHAFT_CENTRE_X2, lb::core::world::SHAFT_CENTRE_Y2) >= 4 * 100 * 100);
		}
	}
}

TEST_CASE("GEN-10 too few candidates: fewer roosts, reported") {
	PlacementParams p;
	p.roost_max_from_hoard = 15; // only the hoard's own neighbours' chambers could count, and few do
	World w;
	int64_t short_runs = 0;
	for (int64_t s = 0; s < 200; s++) {
		reset(w, lb::core::mix64(static_cast<uint64_t>(s) + 0x5407), p);
		const Homes h = make_homes(w, p);
		if (h.roosts_short) {
			short_runs++;
			CHECK(static_cast<int64_t>(h.roosts.size()) < p.roosts_min);
		}
	}
	CHECK(short_runs > 0);
}

TEST_CASE("GEN-10 the revolver and its boxes lie on their planned cells") {
	const PlacementParams p;
	World w;
	for (int64_t s = 0; s < 200; s++) {
		reset(w, lb::core::mix64(static_cast<uint64_t>(s) + 0x6E5), p);
		w.head.plan.revolver = true;
		w.head.plan.revolver_cell = {6, 2};
		w.head.plan.box_cells = {{7, 2}, {7, 2}, {5, -1}};
		const std::vector<Placement> gun_cell = place_cell(w, p, {6, 2});
		CHECK(count(gun_cell, PlacedKind::ITEM, "revolver") == 1);
		int64_t deputies = 0;
		for (const Placement &x : gun_cell) {
			if (x.kind == PlacedKind::ITEM && x.thing == "revolver") {
				REQUIRE(x.with >= 0);
				CHECK(gun_cell[static_cast<size_t>(x.with)].kind == PlacedKind::REMAINS);
				CHECK(gun_cell[static_cast<size_t>(x.with)].thing == "deputy");
				CHECK(x.count == 6);
				deputies++;
			}
		}
		CHECK(deputies == 1);
		CHECK(count(place_cell(w, p, {7, 2}), PlacedKind::ITEM, "rounds") == 2);
		CHECK(count(place_cell(w, p, {5, -1}), PlacedKind::ITEM, "rounds") == 1);
		CHECK(count(place_cell(w, p, {8, 2}), PlacedKind::ITEM, "revolver") == 0);
		CHECK(count(place_cell(w, p, {8, 2}), PlacedKind::ITEM, "rounds") == 0);
	}
}

// GEN-10's run modifiers (Gameplay §13.6, §10.10, §8.4): One Lamp places no lamp of any kind,
// Dead Lines no phone, a staged run 1 no trap (sump mud included) in rings 0-1; GEN-09's contents
// (Dry Stores' half cans among them) go into their slots as GEN-09 gives them.

#include "place_fixture.h"

#include <doctest.h>

using namespace place_fixture;

namespace {

// The fixture's world with one point of interest at (5, 1): two slots in its cell, the contents
// given.
class ContentsWorld final : public PlacementWorld {
public:
	World base;
	std::shared_ptr<RegionLayout> region_layout = std::make_shared<RegionLayout>();
	PoiShape shape;
	std::vector<Content> lines;

	ContentsWorld() {
		shape.slots = {TileRect{3, 10, 1, 1}, TileRect{16, 10, 2, 1}};
		Poi poi;
		poi.kind = PoiKind::FUEL_STORE;
		poi.shape = &shape;
		poi.origin = {5, 1};
		poi.door = {5, 1};
		region_layout->pois.push_back(poi);
	}
	const RunHeader &header() const override { return base.head; }
	std::optional<Layout> layout(Coord c) const override { return base.layout(c); }
	CellFacts facts(Coord c) const override { return base.facts(c); }
	const std::vector<int64_t> &ring_bounds() const override { return base.bounds; }
	PoiRef poi_at(Coord c) const override {
		PoiRef ref;
		if (c == Coord{5, 1}) {
			ref.layout = region_layout;
			ref.poi = &region_layout->pois[0];
		}
		return ref;
	}
	std::vector<Content> contents(const Poi &) const override { return lines; }
};

int64_t lamps(const std::vector<Placement> &list) {
	return count(list, PlacedKind::ITEM, "gauze_lamp") + count(list, PlacedKind::ITEM, "electric_lamp");
}

} // namespace

TEST_CASE("GEN-10 One Lamp places no lamp, Dead Lines no phone") {
	const PlacementParams p;
	World w;
	int64_t lamps_normally = 0;
	int64_t phones_normally = 0;
	for (uint64_t s = 0; s < 300; s++) {
		for (const char *variant : {"", "one_lamp", "dead_lines"}) {
			reset(w, lb::core::mix64(s + 0x0E1A), p);
			w.head.hard_variant = variant;
			write_homes(make_homes(w, p), w.head);
			const Homes h = read_homes(w.head);
			int64_t l = 0;
			int64_t ph = 0;
			for (int64_t y = -3; y <= 3; y++) {
				for (int64_t x = -3; x <= 20; x++) {
					const std::vector<Placement> list = place_cell(w, p, {x, y});
					l += lamps(list);
					ph += count(list, PlacedKind::PHONE);
				}
			}
			if (std::string(variant) == "one_lamp") {
				CHECK(l == 0);
				CHECK_FALSE(h.electric_lamp.has_value());
			} else if (std::string(variant) == "dead_lines") {
				CHECK(ph == 0);
				CHECK(h.gate_phones.empty());
			} else {
				lamps_normally += l;
				phones_normally += ph;
			}
		}
	}
	CHECK(lamps_normally > 100);
	CHECK(phones_normally > 100);
}

TEST_CASE("GEN-10 a staged run 1 places no trap in rings 0-1") {
	PlacementParams p;
	p.traps_min_ring = 2;
	World w;
	int64_t deeper = 0;
	for (uint64_t s = 0; s < 400; s++) {
		reset(w, lb::core::mix64(s + 0x5746), p);
		for (int64_t x = 1; x < 22; x++) {
			const Coord c{x, 3};
			const std::vector<Placement> list = place_cell(w, p, c);
			const int64_t traps = count(list, PlacedKind::MAN_TRAP) + count(list, PlacedKind::STAPLE_PIT) + count(list, PlacedKind::SUMP_MUD);
			if (w.facts(c).ring <= 1) {
				CHECK(traps == 0);
			} else {
				deeper += traps;
			}
		}
	}
	CHECK(deeper > 100);
}

TEST_CASE("GEN-10 a point of interest's contents go into its slots as GEN-09 gives them") {
	const PlacementParams p;
	ContentsWorld w;
	reset(w.base, 0xD57, p);
	w.base.head.draw = {"dry_stores"};
	// GEN-09's fuel store under Dry Stores: half cans, a lamp with its oil, and a phone.
	Content can;
	can.line = 0;
	can.thing = "paraffin_can";
	can.oil_milli = 500;
	Content lamp;
	lamp.line = 1;
	lamp.thing = "gauze_lamp";
	lamp.oil_milli = 300;
	lamp.notches = 2;
	Content lamp2 = lamp;
	lamp2.oil_milli = 400;
	w.lines = {can, lamp, lamp2};
	const std::vector<Placement> list = place_cell(w, p, {5, 1});
	std::vector<Placement> items = of_kind(list, PlacedKind::ITEM);
	REQUIRE(items.size() == 3);
	CHECK(items[0].thing == "paraffin_can");
	CHECK(items[0].oil_milli == 500);
	CHECK(items[0].tile == Coord{103, 30}); // its slot: footprint tiles from the origin cell
	CHECK(items[0].source == "poi");
	CHECK(items[1].tile == Coord{116, 30});
	CHECK(items[2].tile == Coord{117, 30}); // the next tile of a 2-wide slot
	CHECK(items[1].notches == 2);
	// A point of interest's cell takes no loose finds, remains or heaps of its own.
	CHECK(count(list, PlacedKind::REMAINS) == 0);
	CHECK(count(list, PlacedKind::COAT_HEAP) == 0);
	for (const Placement &x : list) {
		CHECK(x.kind != PlacedKind::FIREDAMP);
		CHECK(x.kind != PlacedKind::BLACKDAMP);
	}
}

TEST_CASE("GEN-10 the staged rules follow the header's stage (DIR-06's tables)") {
	const PlacementParams p;
	World w;
	int64_t run1_shallow = 0;
	int64_t run2_shallow = 0;
	for (uint64_t s = 0; s < 400; s++) {
		for (const char *stage : {"1", "2"}) {
			reset(w, lb::core::mix64(s + 0x57A9), p);
			w.head.staging = stage;
			for (int64_t x = 4; x < 10; x++) {
				const Coord c{x, 3};
				if (w.facts(c).ring != 1) {
					continue;
				}
				const int64_t mud = count(place_cell(w, p, c), PlacedKind::SUMP_MUD);
				(std::string(stage) == "1" ? run1_shallow : run2_shallow) += mud;
			}
		}
	}
	CHECK(run1_shallow == 0);
	CHECK(run2_shallow > 50);
	// The roosts: a staged run 1's at least 100 tiles from the shaft, by the table.
	reset(w, 0x5174, p);
	w.head.staging = "1";
	for (const TileBox &b : make_homes(w, p).roosts) {
		const int64_t dx = 2 * b.x + b.w - lb::core::world::SHAFT_CENTRE_X2;
		const int64_t dy = 2 * b.y + b.h - lb::core::world::SHAFT_CENTRE_Y2;
		CHECK(dx * dx + dy * dy >= 4 * 100 * 100);
	}
	CHECK(staged_value(w.head, p.staged_roost_min_from_shaft, 0) == 100);
	w.head.staging = "3";
	CHECK(staged_value(w.head, p.staged_roost_min_from_shaft, 0) == 0);
	w.head.staging = "";
	CHECK(staged_value(w.head, p.staged_traps_min_ring, 0) == 0);
	CHECK(staged_value(w.head, p.staged_traps_min_ring, 3) == 3);
}

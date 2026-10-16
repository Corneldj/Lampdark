// GEN-09: over 10,000 seeds (the three lists in turn), across the 8 x 8 regions round the shaft:
// every region with a cell that may hold a point of interest holds one or two, its planned ones
// included, fewer only where no footprint fits (the rate reported, under 1%); none lies in ring 0,
// on a main road, a spine, base camp or beside an old fall, outside its region or its kind's rings
// (at its door cell), and none overlaps another; the plan's own kinds are never drawn; lamp cabins
// and first-aid stations each lie in 1 region in 3 (within 10% relative) of the regions their rings
// reach. Templates take only orientations whose stubs lie on socket offsets, turning a door to
// every side.

#include "poi_fixture.h"

#include <doctest.h>

#include <chrono>

using namespace poi_fixture;
using lb::core::world::region_of_cell;

namespace {

int64_t ring(Coord c) {
	return ring_of_cell(c, plan_fixture::bounds());
}

// Whether a region has a cell in rings [lo, hi] (and 1 and over) that is no main road.
bool reaches(Coord region, int64_t lo, int64_t hi) {
	for (int64_t y = 0; y < lb::core::world::REGION_CELLS; y++) {
		for (int64_t x = 0; x < lb::core::world::REGION_CELLS; x++) {
			const Coord c{region.x * lb::core::world::REGION_CELLS + x, region.y * lb::core::world::REGION_CELLS + y};
			if (ring(c) >= std::max<int64_t>(lo, 1) && ring(c) <= hi && !plan_fixture::roads().is_main_road_cell(c)) {
				return true;
			}
		}
	}
	return false;
}

bool beside_old_fall(const MainRoads &roads, Coord c) {
	for (int e = 0; e < 4; e++) {
		if (roads.old_fall(neighbour(c, static_cast<Edge>(e)))) {
			return true;
		}
	}
	return false;
}

} // namespace

TEST_CASE("GEN-09 every region holds one or two points of interest over 10,000 seeds") {
	const PoiParams params;
	int64_t eligible = 0;
	int64_t short_regions = 0;
	int64_t empty = 0;
	int64_t over = 0;
	int64_t bad = 0;
	int64_t lamp_reach = 0;
	int64_t lamp_held = 0;
	int64_t aid_reach = 0;
	int64_t aid_held = 0;
	int64_t planned_seen = 0;
	int64_t planned_templated = 0;
	std::map<PoiKind, int64_t> kinds;
	std::map<Coord, int64_t> short_at;
	const auto t0 = std::chrono::steady_clock::now();
	for (uint64_t s = 0; s < 10000; s++) {
		const int32_t list = static_cast<int32_t>(s % 3);
		const uint64_t seed = lb::core::mix64(s * 7 + 0x90109);
		const auto r = run(seed, list);
		REQUIRE_MESSAGE(r->head.plan.error.empty(), "seed ", seed, ": ", r->head.plan.error);
		std::set<Coord> taken;
		for (const Coord &region : regions()) {
			const RegionLayout layout = r->pois->derive(region);
			const bool can = reaches(region, 1, 4);
			const int64_t n = static_cast<int64_t>(layout.pois.size());
			int64_t planned = 0;
			bool lamp = false;
			bool aid = false;
			for (const Poi &p : layout.pois) {
				kinds[p.kind]++;
				lamp = lamp || p.kind == PoiKind::LAMP_CABIN;
				aid = aid || p.kind == PoiKind::FIRST_AID_STATION;
				if (p.planned >= 0) {
					planned++;
					planned_seen++;
					planned_templated += p.shape != nullptr ? 1 : 0;
				} else if (p.kind == PoiKind::SUBSTATION || p.kind == PoiKind::HOARD || p.kind == PoiKind::LAIR) {
					bad++;
					MESSAGE("seed ", seed, ": a drawn ", poi_kind_name(p.kind));
				}
				const auto [lo, hi] = params.rings[static_cast<size_t>(p.kind)];
				if (ring(p.door) < lo || ring(p.door) > hi) {
					bad++;
					MESSAGE("seed ", seed, ": ", poi_kind_name(p.kind), " with its door in ring ", ring(p.door));
				}
				if (p.planned < 0 && region_of_cell(p.approach()) != region) {
					bad++;
					MESSAGE("seed ", seed, ": a drawn door opens out of its region");
				}
				for (const Coord &c : p.cells()) {
					const bool wrong = ring(c) < 1 || region_of_cell(c) != region || (c.x == 0 && c.y == 0) ||
							r->roads->is_main_road_cell(c) || r->spines.count(c) != 0 || (p.planned < 0 && beside_old_fall(*r->roads, c)) ||
							!taken.insert(c).second;
					if (wrong) {
						bad++;
						MESSAGE("seed ", seed, ": ", poi_kind_name(p.kind), " at cell (", c.x, ", ", c.y, ") breaks a rule");
					}
				}
			}
			if (n > params.per_region_max || n < planned || layout.wanted < planned) {
				over++;
			}
			if (can) {
				eligible++;
				if (n < layout.wanted) {
					short_at[region]++;
				}
				short_regions += n < layout.wanted ? 1 : 0;
				empty += n == 0 ? 1 : 0;
			}
			const auto lamp_rings = params.rings[static_cast<size_t>(PoiKind::LAMP_CABIN)];
			const auto aid_rings = params.rings[static_cast<size_t>(PoiKind::FIRST_AID_STATION)];
			if (reaches(region, lamp_rings.first, lamp_rings.second)) {
				lamp_reach++;
				lamp_held += lamp ? 1 : 0;
			}
			if (reaches(region, aid_rings.first, aid_rings.second)) {
				aid_reach++;
				aid_held += aid ? 1 : 0;
			}
		}
	}
	const double ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
	const double short_rate = static_cast<double>(short_regions) / static_cast<double>(eligible);
	const double lamp_rate = static_cast<double>(lamp_held) / static_cast<double>(lamp_reach);
	const double aid_rate = static_cast<double>(aid_held) / static_cast<double>(aid_reach);
	MESSAGE(eligible, " regions that may hold one: ", short_regions, " short of their count (", short_rate * 100.0, "%), ", empty,
			" empty; lamp cabins in ", lamp_rate * 100.0, "% of ", lamp_reach, ", first-aid stations in ", aid_rate * 100.0, "% of ",
			aid_reach, "; ", planned_seen, " planned (", planned_templated, " templated); ", ms, " ms");
	for (const auto &[c, count] : short_at) {
		if (count > 1000) {
			MESSAGE("short region (", c.x, ", ", c.y, "): ", count);
		}
	}
	for (const auto &[k, count] : kinds) {
		MESSAGE(std::string(poi_kind_name(k)), ": ", count);
	}
	CHECK(bad == 0);
	CHECK(over == 0);
	CHECK(short_rate < 0.01);
	CHECK(lamp_rate == doctest::Approx(1.0 / 3.0).epsilon(0.10));
	CHECK(aid_rate == doctest::Approx(1.0 / 3.0).epsilon(0.10));
	CHECK(planned_templated == planned_seen);
}

TEST_CASE("GEN-09 templates turn only where their doors stay on socket offsets") {
	const PoiShapes shapes(*shared_set(), {5, 10, 15});
	for (size_t k = 0; k < static_cast<size_t>(PoiKind::COUNT); k++) {
		const PoiKind kind = static_cast<PoiKind>(k);
		const std::vector<const PoiShape *> &of = shapes.of(kind);
		// A 2-wide door at 10 keeps its offset under all eight; a 2x1 kind has two templates.
		const size_t templates = footprint_of(kind).first != footprint_of(kind).second ? 2 : 1;
		REQUIRE(of.size() == 8 * templates);
		for (const PoiShape *s : of) {
			for (const Stub &st : s->oriented.stubs) {
				CHECK((st.offset == 5 || st.offset == 10 || st.offset == 15));
			}
			CHECK(s->slots.size() == static_cast<size_t>(lines_of(kind)));
		}
		// A door on every side of the footprint, turned either way, at every cell on that side: so
		// a planned site finds one wherever its door must be.
		auto covers = [&](int32_t w, int32_t h, Edge side, Coord cell) {
			for (const PoiShape *s : of) {
				for (const Stub &st : s->oriented.stubs) {
					if (s->oriented.footprint_w == w && s->oriented.footprint_h == h && st.door && st.edge == side && st.cell == cell) {
						return true;
					}
				}
			}
			return false;
		};
		const auto [fw, fh] = footprint_of(kind);
		for (const auto &[w, h] : {std::pair<int32_t, int32_t>{fw, fh}, std::pair<int32_t, int32_t>{fh, fw}}) {
			for (int32_t x = 0; x < w; x++) {
				CHECK(covers(w, h, Edge::NORTH, Coord{x, 0}));
				CHECK(covers(w, h, Edge::SOUTH, Coord{x, h - 1}));
			}
			for (int32_t y = 0; y < h; y++) {
				CHECK(covers(w, h, Edge::WEST, Coord{0, y}));
				CHECK(covers(w, h, Edge::EAST, Coord{w - 1, y}));
			}
		}
	}
	// A 3-wide door keeps its offset under only four: one to each side.
	{
		std::vector<Template> list{poi_template(PoiKind::STORES, false, 3)};
		TemplateSet set;
		REQUIRE(set.load(encode_pack("three", list)));
		const PoiShapes three(set, {5, 10, 15});
		REQUIRE(three.of(PoiKind::STORES).size() == 4);
		std::set<Edge> sides;
		for (const PoiShape *s : three.of(PoiKind::STORES)) {
			sides.insert(s->oriented.stubs.front().edge);
			CHECK(s->oriented.stubs.front().offset == 10);
		}
		CHECK(sides.size() == 4);
	}
	// Turning a quarter clockwise and three more brings a template back; a transpose is GEN-07's.
	const Template t = poi_template(PoiKind::SUBSTATION, false, 3);
	const Template back = orient(orient(t, 1), 3);
	REQUIRE(back.cells.size() == t.cells.size());
	for (size_t i = 0; i < t.cells.size(); i++) {
		CHECK(back.cells[i].coord == t.cells[i].coord);
		CHECK(lb::core::world::content_digest(back.cells[i]) == lb::core::world::content_digest(t.cells[i]));
	}
	REQUIRE(back.stubs.size() == t.stubs.size());
	for (size_t i = 0; i < t.stubs.size(); i++) {
		CHECK(back.stubs[i].cell == t.stubs[i].cell);
		CHECK(back.stubs[i].edge == t.stubs[i].edge);
		CHECK(back.stubs[i].offset == t.stubs[i].offset);
	}
	const Template one = template_fixture::make(template_fixture::Spec{});
	CHECK(lb::core::world::content_digest(orient(one, 4).cells.front()) == lb::core::world::content_digest(transpose(one).cells.front()));
	// A 2x1 footprint turned a quarter is 1x2, its east stub now south of its lower cell.
	const Template turned = orient(t, 1);
	CHECK(turned.footprint_w == 1);
	CHECK(turned.footprint_h == 2);
	CHECK(turned.stubs[0].edge == Edge::EAST);
	CHECK(turned.stubs[0].cell == Coord{0, 0});
	CHECK(turned.stubs[1].edge == Edge::SOUTH);
	CHECK(turned.stubs[1].cell == Coord{0, 1});
	CHECK(turned.stubs[1].offset == 10);
}

TEST_CASE("GEN-09 a kind with no template is never drawn, and a region holds fewer") {
	const auto set = template_set({PoiKind::LAMP_CABIN});
	int64_t lamps = 0;
	for (uint64_t s = 0; s < 50; s++) {
		const auto r = run(lb::core::mix64(s + 0x90155), 1, set);
		for (const Coord &region : regions()) {
			for (const Poi &p : r->pois->derive(region).pois) {
				lamps += p.kind == PoiKind::LAMP_CABIN ? 1 : 0;
			}
		}
	}
	CHECK(lamps == 0);
}

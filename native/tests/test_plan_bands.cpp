// GEN-08: over 10,000 seeds and each list, every planned site lies in its band (the substation,
// hoard and lair by tiles to their door edge's middle; parts, tools, paraffin by rings at their door
// cell), the lair at least 90 degrees from the hoard, the drum gear in ring 3, every tool in ring 1,
// paraffin twice the list's cans within ring 2; no site in ring 0 or the Deep or on a main road, no
// two overlapping, never a third in a region; the revolver in 50% of runs, boxes uniform over 0-2
// and spares in 50% of rolls; and the retries never run out.

#include "plan_fixture.h"

#include <doctest.h>

#include <map>

using namespace plan_fixture;

namespace {

int64_t d2_of(const PlannedSite &s) {
	const auto [x, y] = door_point2(s);
	return x * x + y * y;
}

bool in_tiles(const PlannedSite &s, const std::pair<int64_t, int64_t> &band) {
	const int64_t d2 = d2_of(s);
	return d2 >= 4 * band.first * band.first && d2 <= 4 * band.second * band.second;
}

// A spine site holding `item` whose door ring lies in [lo, hi].
bool held_in(const RunPlan &plan, const std::string &item, int64_t lo, int64_t hi) {
	for (const PlannedSite &s : plan.sites) {
		const int64_t r = ring(s.door);
		if (s.spine && s.count_of(item) > 0 && r >= lo && r <= hi) {
			return true;
		}
	}
	return false;
}

} // namespace

TEST_CASE("GEN-08 every site lies in its band over 10,000 seeds and each list") {
	const PlanParams p;
	const char *part_items[][2] = {{"magneto", "magneto"}, {"drive_belt", "drive_belt"}, {"brake_shoes", "brake_shoe"},
			{"rope_clamps", "rope_clamp"}};
	int64_t runs = 0;
	int64_t revolvers = 0;
	int64_t boxes[3] = {0, 0, 0};
	int64_t spare_rolls = 0;
	int64_t spares = 0;
	int32_t worst_attempt = 0;
	int64_t bad = 0;
	for (int32_t kind = 0; kind < 3; kind++) {
		for (uint64_t s = 0; s < 10000; s++) {
			const uint64_t seed = lb::core::mix64(s * 3 + static_cast<uint64_t>(kind) + 0x6E0E8);
			const RunHeader h = planned(seed, kind);
			const RunPlan &plan = h.plan;
			runs++;
			if (!plan.error.empty()) {
				bad++;
				MESSAGE("seed ", seed, " list ", kind, ": ", plan.error);
				continue;
			}
			std::set<Coord> cells;
			std::map<Coord, int32_t> regions;
			const PlannedSite *hoard = nullptr;
			const PlannedSite *lair = nullptr;
			int64_t paraffin = 0;
			for (const PlannedSite &site : plan.sites) {
				worst_attempt = std::max(worst_attempt, site.attempt);
				const Coord region = lb::core::world::region_of_cell(site.door);
				regions[region]++;
				for (const Coord &c : site.cells) {
					const bool clash = !cells.insert(c).second;
					if (clash || ring(c) < 1 || ring(c) >= DEEP_RING || roads().is_main_road_cell(c) || lb::core::world::region_of_cell(c) != region) {
						bad++;
					}
				}
				switch (site.kind) {
					case PoiKind::SUBSTATION:
						bad += in_tiles(site, p.substation[static_cast<size_t>(kind)]) ? 0 : 1;
						break;
					case PoiKind::HOARD:
						bad += in_tiles(site, p.hoard[static_cast<size_t>(kind)]) ? 0 : 1;
						hoard = &site;
						break;
					case PoiKind::LAIR:
						bad += in_tiles(site, p.lair[static_cast<size_t>(kind)]) ? 0 : 1;
						lair = &site;
						break;
					case PoiKind::FUEL_STORE:
						paraffin += site.count_of("paraffin_can");
						bad += ring(site.door) <= p.paraffin_max_ring ? 0 : 1;
						break;
					default:
						break;
				}
				if (site.count_of("drum_gear") > 0) {
					bad += ring(site.door) == p.drum_gear_ring ? 0 : 1;
				}
			}
			for (const auto &[region, n] : regions) {
				bad += n <= p.max_per_region ? 0 : 1;
			}
			REQUIRE(hoard != nullptr);
			REQUIRE(lair != nullptr);
			const auto [hx, hy] = door_point2(*hoard);
			const auto [lx, ly] = door_point2(*lair);
			bad += hx * lx + hy * ly <= 0 ? 0 : 1; // at least 90 degrees apart
			bad += paraffin == p.paraffin_factor * h.cans ? 0 : 1;
			for (const char *tool : {"spanner", "crowbar", "hammer", "wire_cutters"}) {
				bad += held_in(plan, tool, p.tools_ring, p.tools_ring) ? 0 : 1;
			}
			const auto parts = p.parts_rings[static_cast<size_t>(kind)];
			for (const auto &pi : part_items) {
				if (h.has_job(pi[0])) {
					bad += held_in(plan, pi[1], parts.first, parts.second) ? 0 : 1;
				}
			}
			if (h.has_job("drum_gear")) {
				bad += held_in(plan, "drum_gear", p.drum_gear_ring, p.drum_gear_ring) ? 0 : 1;
			}
			// Power's three fuses: the substation's spare and the cabin's two.
			int32_t fuses = 0;
			for (const PlannedSite &site : plan.sites) {
				fuses += site.spine ? site.count_of("fuse") : 0;
			}
			bad += fuses == 3 ? 0 : 1;
			revolvers += plan.revolver ? 1 : 0;
			boxes[std::min<size_t>(plan.box_cells.size(), 2)]++;
			const std::set<Coord> spine = spine_cells(plan);
			if (plan.revolver) {
				bad += spine.count(plan.revolver_cell) != 0 ? 0 : 1;
				const int64_t r = ring(plan.revolver_cell);
				bad += r >= parts.first && r <= parts.second ? 0 : 1;
			}
			for (const Coord &c : plan.box_cells) {
				bad += spine.count(c) != 0 && (!plan.revolver || c != plan.revolver_cell) ? 0 : 1;
			}
			spare_rolls++; // Power always rolls
			for (const char *job : {"magneto", "drive_belt", "brake_shoes", "drum_gear", "rope_clamps"}) {
				spare_rolls += h.has_job(job) ? 1 : 0;
			}
			for (const PlannedSite &site : plan.sites) {
				spares += site.need.rfind("spare:", 0) == 0 ? 1 : 0;
			}
		}
	}
	MESSAGE(runs, " plans; most retries for one site: ", worst_attempt);
	CHECK(bad == 0);
	const double revolver = static_cast<double>(revolvers) / static_cast<double>(runs);
	MESSAGE("revolver in ", revolver * 100.0, "% of runs; boxes 0/1/2: ", boxes[0], " ", boxes[1], " ", boxes[2]);
	CHECK(std::abs(revolver - 0.5) <= 0.01);
	for (int64_t b : boxes) {
		CHECK(std::abs(static_cast<double>(b) / static_cast<double>(runs) - 1.0 / 3.0) <= 0.01);
	}
	const double spare = static_cast<double>(spares) / static_cast<double>(spare_rolls);
	MESSAGE("spares in ", spare * 100.0, "% of ", spare_rolls, " rolls");
	CHECK(std::abs(spare - 0.5) <= 0.01);
}

TEST_CASE("GEN-08 a solo list never plans the drum gear, and Short plans only Power, Fuel and the rest") {
	for (uint64_t s = 0; s < 500; s++) {
		const RunHeader h = planned(lb::core::mix64(s + 77), 2, true);
		REQUIRE(h.plan.error.empty());
		for (const PlannedSite &site : h.plan.sites) {
			CHECK(site.count_of("drum_gear") == 0);
		}
		const RunHeader short_list = planned(lb::core::mix64(s + 78), 0);
		REQUIRE(short_list.plan.error.empty());
		for (const PlannedSite &site : short_list.plan.sites) {
			for (const char *part : {"magneto", "drive_belt", "brake_shoe", "rope_clamp", "drum_gear"}) {
				CHECK(site.count_of(part) == 0); // undrawn parts are never planned
			}
		}
	}
}

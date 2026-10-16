#pragma once
// GEN-08's fixtures: main roads (their cells do not depend on the seed), base camp with a blind
// side, and repair lists drawn like LFT-03's (Power, Fuel, 0, 2 or 4 of the pool of six, Start;
// a solo list never draws the drum gear).

#include "core/gen/main_roads.h"
#include "core/gen/plan.h"
#include "core/rng/rng.h"

#include <algorithm>

namespace plan_fixture {

using namespace lb::core::gen;
using lb::core::world::Coord;

inline const std::vector<int64_t> &bounds() {
	static const std::vector<int64_t> b{80, 200, 400, 700};
	return b;
}

inline const MainRoads &roads() {
	static const MainRoads r(0, MainRoadParams{}, bounds(), {});
	return r;
}

inline PlanWorld world(int blind) {
	PlanWorld w;
	w.is_main_road_cell = [](Coord c) { return roads().is_main_road_cell(c); };
	for (int e = 0; e < 4; e++) {
		if (e != blind) {
			w.gates.push_back(static_cast<Edge>(e));
		}
	}
	return w;
}

inline int blind_of(uint64_t seed) {
	return static_cast<int>(lb::core::mix64(seed ^ 0xB1D) % 4);
}

inline const std::vector<std::string> &company_order() {
	static const std::vector<std::string> o{"power", "fuel", "magneto", "drive_belt", "brake_shoes", "drum_gear", "free_cage",
			"rope_clamps", "start"};
	return o;
}

inline RunHeader header(uint64_t seed, int32_t kind, bool solo = false) {
	RunHeader h;
	h.seed = seed;
	h.list_kind = kind;
	h.solo = solo;
	h.cans = kind == 0 ? 2 : (kind == 1 ? 4 : 6);
	std::vector<std::string> pool{"magneto", "drive_belt", "brake_shoes", "drum_gear", "free_cage", "rope_clamps"};
	if (solo) {
		pool.erase(std::find(pool.begin(), pool.end(), "drum_gear"));
	}
	lb::core::Rng r(lb::core::mix64(seed + 0x11570));
	r.shuffle(pool);
	pool.resize(static_cast<size_t>(kind == 0 ? 0 : (kind == 1 ? 2 : 4)));
	for (const std::string &job : company_order()) {
		if (job == "power" || job == "fuel" || job == "start" || std::find(pool.begin(), pool.end(), job) != pool.end()) {
			h.jobs.push_back(job);
		}
	}
	return h;
}

inline RunHeader planned(uint64_t seed, int32_t kind, bool solo = false, const PlanParams &params = PlanParams{}) {
	RunHeader h = header(seed, kind, solo);
	h.plan = make_plan(h, params, world(blind_of(seed)));
	return h;
}

inline int64_t ring(Coord c) {
	return ring_of_cell(c, bounds());
}

} // namespace plan_fixture

#pragma once
// GEN-08: the run's plan (Gameplay §3.3, §4.6, §4.7, §8.1, §12.3, §12.5; GDD §15.9). Before the
// cold open ends the server fixes it from the seed and the repair list alone:
// - a site for every required point of interest, each in its band: the District Substation (its
//   spare fuse); an electricians' cabin (2 fuses and the wire cutters: Power's 3 fuses with the
//   substation's); the Moth's hoard; the Stythe's lair, at least mine.lair_min_bearing_from_hoard_deg
//   from the hoard; each drawn part's guaranteed instance (the magneto in a fitters' shop, the
//   drive belt in a haulage engine house, brake shoes and rope clamps in stores, the drum gear in
//   a deep workshop in ring 3); one of each tool in ring 1, in a planned site of its kind there
//   when there is one (one site serves every need whose band it lies in), else a new one; and fuel
//   stores of 2-4 cans holding twice the list's cans, within ring 2;
// - each drawn part's 50% spare: a second site of its kind in its band, with no spine;
// - a spine to every site but the spares (spines.h);
// - the revolver (50% of runs) and 0-2 boxes of rounds, each on a spine cell in their band.
// Each site takes a hashed bearing and distance (or ring) in its band, and snaps to its kind's
// footprint: the door on its cell's side facing the shaft, the cells extending away, all in one
// 5x5-cell region. A try that breaks a rule (ring 0 or the Deep, a main road, another site, its
// spine cells or door approach, a region's third planned site, its band, the lair's bearing, an
// unroutable spine) retries from its next sub-seed of gen.plan, up to mine.plan_max_retries. Bands
// are measured to the door edge's middle; rings are judged at the door cell (Proposed). Pure: the
// same header in gives the same plan out, on every platform.

#include "core/gen/spines.h"

#include <array>
#include <functional>

namespace lb::core::gen {

// The numbers the plan reads (mine.* tuning); the defaults are the design's starting values.
struct PlanParams {
	std::vector<int64_t> ring_bounds{80, 200, 400, 700};
	// Tile bands from the shaft by list kind (Short, Standard, Full).
	std::array<std::pair<int64_t, int64_t>, 3> substation{{{120, 200}, {200, 300}, {200, 300}}};
	std::array<std::pair<int64_t, int64_t>, 3> hoard{{{100, 180}, {120, 260}, {120, 260}}};
	std::array<std::pair<int64_t, int64_t>, 3> lair{{{150, 250}, {220, 380}, {220, 380}}};
	// The parts' (and the revolver's) rings by list kind.
	std::array<std::pair<int64_t, int64_t>, 3> parts_rings{{{1, 1}, {1, 2}, {1, 3}}};
	double lair_min_bearing_deg = 90.0;
	int64_t drum_gear_ring = 3;
	int64_t tools_ring = 1;
	int64_t paraffin_factor = 2;
	int64_t paraffin_max_ring = 2;
	int64_t fuel_cans_min = 2;
	int64_t fuel_cans_max = 4;
	uint32_t spare_ppm = 500000;
	uint32_t revolver_ppm = 500000;
	int64_t boxes_min = 0;
	int64_t boxes_max = 2;
	int32_t max_retries = 100;
	int32_t max_per_region = 2;
	// By kind: the footprint (cells wide, deep; turned freely) and the rings it lies in.
	std::array<std::pair<int32_t, int32_t>, static_cast<size_t>(PoiKind::COUNT)> footprint;
	std::array<std::pair<int64_t, int64_t>, static_cast<size_t>(PoiKind::COUNT)> rings;

	PlanParams();
};

// What the plan reads of the world besides its header: GEN-07's main-road cells and base camp's
// open gates (GEN-02).
struct PlanWorld {
	std::function<bool(lb::core::world::Coord)> is_main_road_cell;
	std::vector<Edge> gates;
};

// The plan for `header`'s seed and list (its plan field is ignored).
RunPlan make_plan(const RunHeader &header, const PlanParams &params, const PlanWorld &world);

// The cells every spine runs through.
std::set<lb::core::world::Coord> spine_cells(const RunPlan &plan);

} // namespace lb::core::gen

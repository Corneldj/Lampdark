#pragma once
// GEN-14: the seed harness (Gameplay §12.3, §12.5, §4.5, §A.11; GDD §15.9, §C.11). It guards the
// generator over thousands of planned runs. Each run (a seed and a list) is checked for:
// - its plan (GEN-08): no need's retries ran out;
// - spine reach: every spine walked from its gate to its target's door with every collapse point
//   its cells arm fallen (GEN-12's walk_spine, after the run start's replans);
// - order-independence: the cells nearest the shaft generated fully (layout, placement and the
//   validator's outcome) in seeded random orders, each into a fresh world, every cell's digest
//   the same in each;
// - the validator: no final cell among them breaks a rule (phase 1 or phase 2), and nothing is
//   placed in base camp;
// - fairness: each planned site's road from base camp against the straight line, and the share of
//   ring 0-2 cells joined to base camp by sockets;
// - finds over what a typical run touches (the exploration model, Proposed), against the
//   typical-run targets;
// - its banded sites (each kind's distance, the hoard-lair bearing), the validator's counts and
//   template usage;
// - timing: each cell's generation, by biome.
// A Report gathers runs in any order and gives the same bytes (timing aside), so threads change
// nothing. Gates fail the build; the rest warn. Every failure names its seed, list, check, cell and
// rule, and the command that repeats it. Server-side tooling only: compiled into debug libraries
// and the doctests, never a release; it never reads Godot, tuning files or loaded state.

#include "core/gen/derive.h"
#include "core/gen/placement.h"
#include "core/gen/poi.h"
#include "core/gen/run_header.h"
#include "core/gen/validator.h"

#include <array>
#include <cstdint>
#include <functional>
#include <map>
#include <memory>
#include <mutex>
#include <optional>
#include <set>
#include <string>
#include <tuple>
#include <vector>

namespace lb::harness {

namespace gen = lb::core::gen;
using lb::core::world::Coord;

// One planned run as its owner built it (the server's LbLayouts, or a test fixture): configured
// for its seed and list, planned, its spines validated at run start (GEN-12) and its homes made.
// Its world's layout() is each cell's final layout (GEN-12's derive_final).
class Run {
public:
	virtual ~Run() = default;
	virtual const gen::RunHeader &header() const = 0;
	virtual const gen::PlacementWorld &world() const = 0;
	virtual const gen::PlacementParams &placement_params() const = 0;
	virtual const gen::ValidatorParams &validator_params() const = 0;
	// A cell's sockets and class, as its derive reads them.
	virtual gen::CellSockets sockets(Coord cell) const = 0;
	virtual gen::CellClass cell_class(Coord cell) const = 0;
	// The validator's counts since the run's last rebuild (ValidatorCounters::totals).
	virtual std::map<std::string, int64_t> counter_totals() const = 0;
	// What its derive reads (null for a hand-made world): repro's phase-1 trace.
	virtual const gen::DeriveInputs *derive_inputs() const { return nullptr; }
};

// The same run built again from nothing, its plan and homes as fixed: an order check's fresh world.
using RunFactory = std::function<std::unique_ptr<Run>()>;

// The harness's numbers: mine.harness_* tuning (MineLayouts.harness_params), the defaults the
// ticket's starting values.
struct Params {
	int32_t order_cells = 400; // mine.harness_order_cells
	int32_t orders = 3; // mine.harness_orders
	double spine_reach_min = 1.0; // mine.harness_spine_reach_min
	double road_ratio_max = 2.5; // mine.harness_road_ratio_max
	double road_ratio_share_max = 0.01; // mine.harness_road_ratio_share_max (Proposed)
	double joined_min = 0.85; // mine.harness_joined_min
	int64_t joined_max_ring = 2; // ring 0-2 (Gameplay §12.3)
	double fallback_rate_max = 0.01; // mine.harness_fallback_rate_max (Proposed)
	// The exploration model (Proposed): the spine cells, their 8-neighbours, the planned sites'
	// cells, and every cell of ring explore_max_ring or less within explore_radius cells of a spine.
	int32_t explore_radius = 3;
	int64_t explore_max_ring = 1;
	// The typical-run targets, [lo, hi] (Gameplay §12.5, §4.5): Standard runs, the ring-2 counts
	// within ring 2, and one of each tool within ring 1.
	std::pair<int64_t, int64_t> lamps{3, 6}; // mine.harness_target_lamps_standard
	std::pair<int64_t, int64_t> kits{4, 6}; // mine.harness_target_kits_standard
	std::pair<int64_t, int64_t> flares_ring2{3, 6}; // mine.harness_target_flares_ring2
	std::pair<int64_t, int64_t> tools_ring2{1, 2}; // mine.harness_target_tools_ring2
	int64_t cupboard_kits = 1; // basecamp.medbay_cupboard_kits
	// A finds count outside its band in more than this share of a list's seeds warns.
	double finds_warn_share = 0.2;
	// Timing: the machine's p99 budget (mine.harness_budget_fleet_ms; the Deck's
	// mine.harness_budget_deck_ms), gated only on the reference machine.
	double budget_ms = 1.0;
	bool timing_gate = false;
	std::string machine = "local";
	double lair_min_bearing_deg = 90.0; // mine.lair_min_bearing_from_hoard_deg
	int64_t route_max_explored = 400000;
	int32_t failures_kept_per_check = 40;
};

// One failure: what broke, where, and the command that repeats it.
struct Failure {
	uint64_t seed = 0;
	int32_t list = 0;
	std::string check; // plan, spine_reach, order, validator, base_camp, road_ratio
	Coord cell;
	int32_t rule = 0; // GEN-12's check number (0: none)
	Coord tile;
	std::string detail;

	std::string repro() const;
	std::tuple<std::string, uint64_t, int32_t, int64_t, int64_t, std::string> key() const {
		return {check, seed, list, cell.y, cell.x, detail};
	}
};

// A run's outcome: counts and samples only (the Report gathers them).
struct RunResult {
	uint64_t seed = 0;
	int32_t list = 0;
	bool planned = false;
	int32_t spines = 0;
	int32_t spines_reached = 0;
	int32_t order_cells = 0;
	int32_t order_differing = 0;
	int32_t cells_checked = 0;
	int32_t cells_invalid = 0;
	// Fairness: each planned site's road over the straight line (ppm; -1 when no road reached it).
	std::vector<int64_t> road_ratio_ppm;
	int32_t joined_cells = 0;
	int32_t ring_cells = 0;
	// Finds over the explored cells: lamps (besides the hoard), kits (the cupboard's included),
	// flares_ring2, tools_ring2.<tool>, tools_ring1.<tool>; and explored_cells.
	std::map<std::string, int64_t> finds;
	// Over the order cells (the first order's world): cells, fallbacks and rerolls by biome,
	// template usage, the validator's counts.
	std::map<std::string, int64_t> cells_by_biome;
	std::map<std::string, int64_t> fallbacks_by_biome;
	std::map<std::string, int64_t> rerolled_by_biome;
	std::map<std::string, int64_t> templates;
	std::map<std::string, int64_t> counters;
	// Banded sites: each planned site's kind and its door's distance from the shaft (tiles); the
	// hoard-lair bearing seen from the shaft (degrees, -1 without both).
	std::vector<std::pair<std::string, int64_t>> sites;
	int64_t hoard_lair_bearing = -1;
	// The Moth's roosts the homes pass found (GEN-10), when the plan has a hoard (-1 without one).
	int32_t roosts = -1;
	int32_t roosts_min = 2; // mine.roosts_min
	// Timing, machine-dependent: each order cell's derive and placement (microseconds), by biome.
	std::map<std::string, std::vector<int64_t>> cell_us;
	// The failures, at most Params::failures_kept_per_check of each check, and how many there were.
	std::vector<Failure> failures;
	std::map<std::string, int64_t> failure_counts;
};

// Checks one run. `fresh` builds each order check's world; `list` names the run's list.
RunResult check_run(const Run &run, const RunFactory &fresh, const Params &p);

// ---- Metrics (unit-tested on hand-made worlds) ----

// The `n` cells nearest the shaft, base camp's cell excluded: by squared distance from (0, 0),
// then y, then x.
std::vector<Coord> nearest_cells(int32_t n);
// The k-th seeded random order of `cells` for a seed.
std::vector<Coord> shuffled(std::vector<Coord> cells, uint64_t seed, int32_t k);
// A cell's whole outcome: its final layout (sockets, template, fitted content, reroll, fallback),
// its validated placements and how the validator reached them.
uint64_t cell_digest(const std::optional<gen::Layout> &layout, const gen::PlacedCell &placed);

// What the joined share walks: each cell's sockets, its ring, and the point of interest it lies in
// (its footprint's cells; none outside one).
struct SocketGraph {
	std::function<gen::CellSockets(Coord)> sockets;
	std::function<int64_t(Coord)> ring;
	std::function<std::vector<Coord>(Coord)> footprint;
};
SocketGraph socket_graph(const Run &run);
// The cells of ring `max_ring` or less within `reach` cells (Chebyshev) of base camp, base camp's
// own excepted, and how many of them are joined to it through open sockets (a point of interest's
// footprint one piece), the walk staying in those rings.
struct Joined {
	int32_t joined = 0;
	int32_t cells = 0;
};
Joined joined_cells(const SocketGraph &g, int64_t max_ring, int64_t reach);
// The reach that holds every cell of ring `max_ring` or less.
int64_t ring_reach(const std::vector<int64_t> &ring_bounds, int64_t max_ring);

// A road's length in tiles (4-connected steps) between two tiles, and the tiles it joins; -1
// tiles when none was found.
struct Road {
	int64_t tiles = -1;
	Coord from;
	Coord to;
	double straight() const;
};
// A spine's road from its gate's opening to its site's door through its own cells and the door
// cell (collapses standing, doors open): an upper bound on the shortest road.
Road spine_road(const gen::PlacementWorld &world, const gen::RunPlan &plan, size_t spine);
// The shortest road from a site's door home to any of base camp's gates (gen::route_home).
Road home_road(const gen::PlacementWorld &world, const gen::PlannedSite &site, int64_t max_explored);

// The exploration model's cells (see Params), sorted.
std::vector<Coord> explored_cells(const gen::RunPlan &plan, const gen::PlacementWorld &world, int32_t radius, int64_t max_ring);
// The finds a list of cells' validated placements hold (RunResult::finds' keys).
std::map<std::string, int64_t> count_finds(const gen::PlacementWorld &world, const gen::PlacementParams &pp, const gen::ValidatorParams &vp,
		const std::vector<Coord> &cells, int64_t cupboard_kits);

// ---- The report ----

// A fixed-bin histogram: its counts in bins of `step` from 0, the last bin holding everything over.
struct Histogram {
	int64_t step = 1;
	std::vector<int64_t> bins;
	int64_t count = 0;
	int64_t sum = 0;
	int64_t min = INT64_MAX;
	int64_t max = INT64_MIN;

	Histogram() = default;
	Histogram(int64_t bin_step, size_t bin_count) : step(bin_step), bins(bin_count, 0) {}
	void add(int64_t v);
	void merge(const Histogram &o);
	// The q-quantile's bin upper edge (the max for the last bin).
	int64_t quantile(double q) const;
};

// Everything the runs gave, gathered in any order: every part adds commutatively (integers,
// histograms and a bounded, sorted set of failures), so threads change nothing.
class Report {
public:
	explicit Report(Params p = Params()) : p_(std::move(p)) {}
	void add(const RunResult &r);
	void set_pack(std::string set_version) { pack_ = std::move(set_version); }
	void set_range(uint64_t first_seed, uint64_t last_seed, std::vector<int32_t> lists);

	struct Gate {
		std::string name;
		bool failed = false;
		std::string detail;
	};
	std::vector<Gate> gates() const;
	bool failed() const;
	// Canonical JSON: identical for the same seeds and binaries; `timing` adds the machine's timing.
	std::string json(bool timing) const;
	std::string markdown() const;
	const Params &params() const { return p_; }
	int64_t runs() const { return runs_; }
	int64_t failure_count(const std::string &check) const;
	const std::vector<Failure> &failures() const { return kept_; }

private:
	struct ListStats {
		int64_t runs = 0;
		int64_t plans_failed = 0;
		int64_t spines = 0;
		int64_t spines_reached = 0;
		Histogram road_ratio{50000, 201}; // ppm in 0.05 steps up to 10
		int64_t roads = 0;
		int64_t roads_over = 0;
		int64_t roads_missing = 0;
		int64_t joined = 0;
		int64_t ring_cells = 0;
		Histogram joined_share{10000, 101}; // ppm in 1% steps
		int64_t runs_joined_under = 0;
		std::map<std::string, Histogram> finds;
		std::map<std::string, Histogram> sites;
		Histogram hoard_lair{5, 37};
		int64_t hoard_lair_under = 0;
		Histogram roosts{1, 21};
		int64_t roosts_short = 0;
	};
	Params p_;
	std::string pack_;
	uint64_t first_seed_ = 0;
	uint64_t last_seed_ = 0;
	std::vector<int32_t> lists_;
	int64_t runs_ = 0;
	int64_t order_cells_ = 0;
	int64_t order_differing_ = 0;
	int64_t cells_checked_ = 0;
	int64_t cells_invalid_ = 0;
	std::map<int32_t, ListStats> by_list_;
	std::map<std::string, int64_t> cells_by_biome_;
	std::map<std::string, int64_t> fallbacks_by_biome_;
	std::map<std::string, int64_t> rerolled_by_biome_;
	std::map<std::string, int64_t> templates_;
	std::map<std::string, int64_t> counters_;
	std::map<std::string, Histogram> timing_;
	std::map<std::string, int64_t> failures_by_check_;
	std::vector<Failure> kept_;
	void keep(const Failure &f);
	std::vector<std::string> warnings() const;
	// Timing's warnings, machine-dependent: in the timing section alone.
	std::vector<std::string> timing_warnings() const;
};

// The list's name for reports and repro commands (0 short, 1 standard, 2 full).
const char *list_name(int32_t list);

// ---- GEN-16's coverage report ----

// A biome's cell templates against every socket set a cell of it can meet: each edge shut, or open
// at each socket offset and each width the biome allows, weighted by the socket rates (GEN-05's
// hashes: open at open_ppm, then an offset and a width uniformly). A template covers a set when it
// has a stub at every open socket at least as wide (GEN-05's covers); a covered cell takes one of
// its covering templates by weight, its unused stubs filling as blind headings.
struct Coverage {
	std::string biome;
	int32_t templates = 0; // the biome's cell templates (its fallback aside)
	int64_t sets = 0;
	int64_t covered_ppm = 0; // the weighted share a template (not the fallback) covers
	int64_t fallback_ppm = 0; // the share only the plain fallback covers
	int64_t uncovered_ppm = 0; // the share nothing covers
	int64_t blind_milli = 0; // the expected blind headings a cell, in thousandths
	// The sets only the fallback or nothing covers, likeliest first (at most 40), as "N5w3 E- S10w2 W-".
	std::vector<std::string> uncovered;
	// How many templates cover a set -> how many sets.
	std::map<int32_t, int64_t> templates_per_set;
};
Coverage coverage(const gen::TemplateSet &set, const std::string &biome, uint32_t open_ppm, const std::vector<int32_t> &offsets,
		const std::vector<int32_t> &widths);

// The repro dump for one run: its failures for `check` (every check for ""), and for `cell` its
// final layout as rows of tiles, its anchors, phase 1's tries, phase 2's tries and, for the order
// check, its digest in each order.
std::string repro(const Run &run, const RunFactory &fresh, const Params &p, const std::string &check, std::optional<Coord> cell);

} // namespace lb::harness

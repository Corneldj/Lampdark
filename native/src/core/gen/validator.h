#pragma once
// GEN-12: the validator (Gameplay §12.3, §12.4, §12.5, §7.3, §A.11; GDD §15.9). Every cell and every
// spine is checked as it is built, so no cell ships breaking a design rule:
// - Phase 1, layout (validate_layout): a fitted cell against its own sockets and class. It never
//   sees a neighbour's layout, and sockets are edge-level and never depend on rerolls, so no cycle
//   can form between neighbours. A failing cell rerolls from the next sub-seed of GEN-05's choice;
//   at the reroll limit (mine.validator_max_rerolls) it takes its biome's plain fallback, which
//   covers every socket set (fallback_coverage proves it).
// - Phase 2, placement (validate_placement): GEN-10's placements against the rules, reading only
//   the neighbours' final phase-1 layouts and the pure passes over them (their phones, doors and
//   armed collapse points), never loaded state. A failing cell's placement retries from the next
//   sub-seed of its own passes, up to mine.placement_max_retries or until a try fails for the
//   reason the one before it did; then strict mode drops each placement that would break a rule,
//   and never adds one.
// - Run start: base camp's gates (check_gates), and every spine walked from its gate to its
//   target's door with every collapse point its cells arm fallen (walk_spine); a failing spine
//   replans from its next sub-seed (GEN-08's route_spine).
// Every outcome (the reroll, the template, the tries, the drops) is a pure function of the seed,
// the header and the coordinates, the same in any order and on any thread. The numbers are
// GEN-04's and GEN-10's tuning, so content, generator and harness agree. ValidatorCounters keeps
// the run's counts by rule, biome and template (GEN-14, FND-08). Server-only: no verdict or count
// reaches a client (NET-08).

#include "core/gen/main_roads.h"
#include "core/gen/placement.h"
#include "core/gen/spines.h"

#include <array>
#include <functional>
#include <map>
#include <mutex>
#include <set>
#include <string>
#include <vector>

namespace lb::core::gen {

// The checks by number: 1-6 the design's six rules (§12.3), 7-14 the supporting checks (Proposed),
// each enforcing a rule stated elsewhere in the design.
enum class Check : uint8_t {
	NONE = 0,
	NEAR_HOME = 1, // no gas or trap in ring 0; no collapse point within 7 tiles by path of base camp, a point of interest's door or a pit phone
	GAS = 2, // no required item in gas, no gas on a spine, no remains in blackdamp
	GATES = 3, // base camp's three gates open onto three roads in different directions
	WIDTHS = 4, // chambers 5-8 tiles across, never exactly 4; roads 1-3 wide
	POI_SOCKETS = 5, // every point of interest joins a socket, and the lair exactly one
	SPINE_REACH = 6, // every spine reaches its target
	CONNECTED = 7, // the floor one piece after stub fill (§12.3: reachability by sockets alone)
	THROATS = 8, // every open socket's throat as wide as the socket, no floor at a shut one (§12.3)
	TAPPER_REACH = 9, // every road tile within the Tapper's reach of a face, except on brick (§7.3)
	LANDMARK = 10, // exactly one landmark site (§12.7)
	ARCHES = 11, // base camp's arches intact: no door on the arch past a gate (§3.2, GEN-02)
	COLLAPSE_SPACING = 12, // collapse points 12 or more tiles apart and beyond 20 of base camp (§12.5)
	SPINE_COLLAPSE = 13, // no collapse point armed on a spine cell (§12.3)
	CLEAR_GROUND = 14, // nothing on an armed collapse point's tiles or in base camp (§12.5)
	COUNT
};

const char *check_name(Check check);

// A check's outcome: ok, or the check broken and the world tile that broke it.
struct Verdict {
	Check check = Check::NONE;
	lb::core::world::Coord tile;
	std::string detail;

	bool ok() const { return check == Check::NONE; }
	int32_t number() const { return static_cast<int32_t>(check); }
	// The same reason: the same check at the same tile.
	bool same(const Verdict &o) const { return check == o.check && tile == o.tile; }
};

// "rule 4 (widths) at (x, y): <detail>"; "ok" for none.
std::string describe(const Verdict &v);

// The validator's numbers besides GEN-10's PlacementParams.
struct ValidatorParams {
	// GEN-04's: road widths, chamber sizes, the Tapper's reach and the lair's kind.
	ValidateParams rules;
	int32_t max_retries = 20; // mine.placement_max_retries
	int32_t max_replans = 20; // a spine's replans (mine.validator_max_rerolls)
	// GEN-02: how many tiles of each gate's arch run on into the cell beyond it, by base camp's side
	// (north, east, south, west; basecamp.arch_length_tiles less the path inside base camp's cell).
	std::array<int32_t, 4> arch_reach{0, 0, 0, 0};
};

// ---- Phase 1: layout ----

// The first check a fitted cell breaks, or ok. Its only inputs are its own layout (tiles,
// anchors, collapses, sockets) and its class: no neighbour's layout can reach it. A point of
// interest's cell is checked for its sockets (rules 5 and 8); its floor and widths are GEN-04's,
// over its whole template.
Verdict validate_layout(const Layout &layout, const CellClass &cls, const ValidatorParams &p);
// GEN-02's arch tiles in a gate cell (the flood over floor from the gate's opening, its tiles the
// first of arch_reach steps) and, in `door`, the first door tile the flood would have gone on
// through; empty for any other cell.
std::vector<lb::core::world::Coord> gate_arch_tiles(const Layout &layout, const ValidatorParams &p,
		std::optional<lb::core::world::Coord> *door = nullptr);

// One failing phase-1 try: its reroll, the template tried and the check it broke.
struct LayoutTry {
	int32_t reroll = 0;
	std::string template_id;
	Verdict verdict;
};

// A cell's final layout: the first reroll whose fitted template passes phase 1; at the reroll
// limit, the biome's plain fallback (kept even if it fails, which `tried` records). A point of
// interest's cell and base camp are their own whatever the reroll. With no validator in `in`,
// reroll 0. `derive_at` derives one reroll (derive_layout without it).
std::optional<Layout> derive_final(const DeriveInputs &in, lb::core::world::Coord cell, std::vector<LayoutTry> *tried = nullptr,
		const std::function<std::optional<Layout>(int32_t)> &derive_at = nullptr);

// Every socket set a cell can meet (each edge shut or open at each offset, at each width in
// `widths`) fitted to `biome`'s plain fallback and checked by phase 1. The failures, or one
// verdict naming the missing fallback; `checked` gets the sets tried.
struct CoverageFailure {
	CellSockets sockets{};
	Verdict verdict;
};
std::vector<CoverageFailure> fallback_coverage(const TemplateSet &set, const std::string &biome, const std::vector<int32_t> &widths,
		const SocketParams &sockets, const ValidatorParams &p, size_t *checked = nullptr);

// ---- Phase 2: placement ----

// What phase 2 reads round a cell, built once: its facts, its and its neighbours' final layouts
// (3x3 cells), a walk of their floor (doors open), and from GEN-10's pure passes the pit phones
// and point-of-interest doors in those cells and the collapse points the neighbours arm; and, in
// a gate cell, its arch tiles.
struct PlacementContext {
	lb::core::world::Coord cell;
	CellFacts facts;
	std::optional<Layout> layout;
	std::vector<lb::core::world::Coord> phones;
	std::vector<lb::core::world::Coord> doors;
	std::vector<std::vector<lb::core::world::Coord>> neighbour_collapses;
	std::set<lb::core::world::Coord> arch;
	// The 3x3 cells' walkable tiles, from (cell - 1) * 20, 60 a row.
	std::vector<uint8_t> walk;
	int64_t collapse_min_from_sites = 7;
	int64_t collapse_min_spacing = 12;
	int64_t collapse_min_from_basecamp = 20;
};

PlacementContext placement_context(const PlacementWorld &world, const PlacementParams &pp, const ValidatorParams &vp,
		lb::core::world::Coord cell);
// The first check a cell's placements break, or ok.
Verdict validate_placement(const PlacementContext &ctx, const std::vector<Placement> &list);
// Strict mode: `list` with each placement dropped that would break a check against the context
// and the placements kept before it, and with it whatever a dropped man carried. Never adds one;
// what it keeps always passes validate_placement. `dropped` gets how many went.
std::vector<Placement> strict_placement(const PlacementContext &ctx, const std::vector<Placement> &list, int32_t *dropped = nullptr);

struct PlacedCell {
	std::vector<Placement> list;
	int32_t retry = 0; // the try that passed (0: the first)
	bool strict = false;
	int32_t dropped = 0; // strict mode's drops
	std::vector<Verdict> failures; // each failed try's first verdict, in order
};

// GEN-10's place_cell under phase 2: its tries, then strict mode over the first try's list.
PlacedCell place_validated(const PlacementWorld &world, const PlacementParams &pp, const ValidatorParams &vp, lb::core::world::Coord cell);

// ---- Run start ----

// Rule 3: base camp's gates. Three of its four sides open, each onto a road: the cell beyond holds
// floor at the gate's opening that joins another of its open sockets.
Verdict check_gates(const PlacementWorld &world);

// Rule 6: a spine walked from its gate's opening to its target's door through its own cells and
// the door cell alone, with every collapse point their validated placements arm fallen (every
// alternate when `all_alternates`, for tests). Ok, or the walk's nearest tile to the door.
Verdict walk_spine(const PlacementWorld &world, const PlacementParams &pp, const ValidatorParams &vp, const RunPlan &plan, size_t spine,
		bool all_alternates = false);

// Rule 6 over a plan at run start: every spine walked (`walk`); a failing one replanned from its
// next sub-seed (route_spine, avoiding every site's cells) until its route moves or it has had
// `max_replans`. After a round with any move, `rebuild` derives the mine again and every spine
// still standing a chance is walked again. The plan's spines are replaced in place.
struct SpineCheck {
	std::vector<Verdict> verdicts; // by spine
	std::vector<int32_t> replans; // by spine
	int64_t total = 0;
	int32_t rebuilds = 0;
};
SpineCheck validate_spines(RunPlan &plan, uint64_t seed, const std::vector<Edge> &gates, const std::vector<int64_t> &ring_bounds, int32_t max_replans,
		const std::function<Verdict(size_t)> &walk, const std::function<void()> &rebuild);

// ---- Counts ----

// The run's counts (GEN-14's rates, FND-08's debug view), each cell's layout and placement counted
// once however often it is derived. Keys: cells, cells.<biome>, rerolled, rerolled.<biome>,
// rerolls, fallbacks, fallbacks.<biome>, failed.<n>, failed.<n>.<biome>, failed.<n>.<template>,
// shipped_invalid, no_layout, placed, retried, retries, strict, dropped, placement_failed.<n>,
// spines, spine_replans, spines_unreached, gates_failed, sites_untemplated. Thread-safe.
class ValidatorCounters {
public:
	void count_layout(lb::core::world::Coord cell, const std::string &biome, const std::optional<Layout> &final_layout,
			const std::vector<LayoutTry> &tried);
	void count_placement(lb::core::world::Coord cell, const PlacedCell &placed);
	void count_spine(int32_t replans, const Verdict &final_verdict);
	void count_gates(const Verdict &v);
	// Any other count, with a note when `text` is given (a planned site no template fits...).
	void count(const std::string &key, const std::string &text = "");
	std::map<std::string, int64_t> totals() const;
	// The first failures described ("cell (x, y) reroll k <template>: rule 4 (widths) at ..."), at most 64.
	std::vector<std::string> notes() const;
	void clear();

private:
	mutable std::mutex mutex_;
	std::set<lb::core::world::Coord> laid_;
	std::set<lb::core::world::Coord> placed_;
	std::map<std::string, int64_t> n_;
	std::vector<std::string> notes_;
	void add(const std::string &key, int64_t by = 1) { n_[key] += by; }
	void note(const std::string &text);
};

// GEN-10's view of a derived run: the deriver's final layouts, the base classifier's biome under
// any main road (a templated point of interest's own), GEN-07's roads, GEN-08's spines and
// GEN-09's points of interest. Pure, as PlacementWorld requires.
class DerivedWorld final : public PlacementWorld {
public:
	DerivedWorld(const RunHeader &header, const Deriver &deriver, const CellClassifier &base, const MainRoads *roads, const SpineSockets *spines,
			const PointsOfInterest *pois, const PoiContentsParams *contents, std::vector<int64_t> bounds);

	const RunHeader &header() const override { return header_; }
	std::optional<Layout> layout(lb::core::world::Coord cell) const override { return deriver_.derive_final(cell); }
	CellFacts facts(lb::core::world::Coord cell) const override;
	const std::vector<int64_t> &ring_bounds() const override { return bounds_; }
	PoiRef poi_at(lb::core::world::Coord cell) const override;
	std::vector<Content> contents(const Poi &poi) const override;
	std::shared_ptr<const RegionLayout> region(lb::core::world::Coord region) const override;

private:
	const RunHeader &header_;
	const Deriver &deriver_;
	const CellClassifier &base_;
	const MainRoads *roads_;
	const SpineSockets *spines_;
	const PointsOfInterest *pois_;
	const PoiContentsParams *contents_;
	std::vector<int64_t> bounds_;
};

} // namespace lb::core::gen

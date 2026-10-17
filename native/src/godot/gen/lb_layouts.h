#pragma once
// GDScript face of GEN-05's layout stage (core/gen/derive.h): the run's template pack, its
// sockets and its derived cell layouts. Set it up first (load_pack, configure, force_socket);
// after that socket() and derive() are pure and thread-safe, for GEN-11's workers. Server-only:
// no socket, layout or seed reaches a client (NET-08).

#include "core/gen/gen_pool.h"
#include "core/gen/main_roads.h"
#include "core/gen/placement.h"
#include "core/gen/plan.h"
#include "core/gen/poi.h"
#include "core/gen/validator.h"

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/vector2i.hpp>

#include <memory>
#include <set>

namespace lb::godot {

class LbMine;
class LbCellData;

class LbLayouts : public ::godot::RefCounted {
	GDCLASS(LbLayouts, ::godot::RefCounted)

protected:
	static void _bind_methods();

public:
	LbLayouts();

	// GEN-04's pack. False for bytes that are not a whole pack.
	bool load_pack(const ::godot::PackedByteArray &bytes);
	::godot::String set_version() const;
	// params: open_probability, offsets, widths, reroll_limit, and either biomes (GEN-06's table:
	// {rings: [[[biome, weight], ...], ...], widths: {biome: [min, max]}, ring_bounds: [...]}) or
	// biome (one biome for every cell, for tests); main_roads (GEN-07: {spacing, width, offset,
	// run_min, run_max, max_ring, old_fall_probability}) to lay main roads over the biomes; and poi
	// (GEN-09: {per_region_min, per_region_max, two_probability, lamp_cabin_regions_per,
	// first_aid_regions_per, fit_tries, canary_max_per_run, min_ring, ring_min: {kind: ring}, ring_max: {kind: ring},
	// weights: [{kind: weight} per ring from 0], lair_biome, contents: {kind: {name: number}},
	// fuel_cans_min, fuel_cans_max, found_oil: [lo, hi], found_notches: [lo, hi], remains_chances:
	// {lamp, flare, kit, tool, note}, remains_items_max, dry_stores_factor}) to place points of
	// interest (with the plan's own once plan() has run).
	void configure(int64_t seed, const ::godot::Dictionary &params);
	// A socket forced up front (base camp's): socket {open, offset, width}. side: north, east, south, west.
	bool force_socket(::godot::Vector2i cell, const ::godot::String &side, const ::godot::Dictionary &socket);
	// {open, offset, width, forced}
	::godot::Dictionary socket(::godot::Vector2i cell, const ::godot::String &side) const;
	// The cell's biome (GEN-06; a templated point of interest's, GEN-09), "" for base camp;
	// server-only, never sent.
	::godot::String biome_of(::godot::Vector2i cell) const;
	// GEN-07: {main_road, crossing, shape, old_fall, transpose, dress} of a cell.
	::godot::Dictionary road_of(::godot::Vector2i cell) const;
	// {ok, base_camp, fallback, template, sockets: {side: {...}}, cell: LbCellData (none for base camp), digest, reroll}
	::godot::Dictionary derive(::godot::Vector2i cell, int64_t reroll) const;
	// GEN-12: the cell's final layout, the one generation commits: with the validator (configure's
	// validate), the first reroll phase 1 accepts or the plain fallback; without it, reroll 0.
	// derive()'s dictionary plus tries: [{reroll, template, rule, check, tile, detail}], each failed try.
	::godot::Dictionary derive_final(::godot::Vector2i cell) const;
	void set_caching(bool on);
	void clear_caches();
	void set_verify(bool on);
	int64_t verify_failures() const;

	// GEN-08's plan for the configured seed (configure and force_socket first): params {list_kind,
	// jobs, cans, solo, draw, staging, hard_variant, data_version, tuning: {...}}. The template
	// version is the loaded pack's. Spine sockets and spine cells then join every derive. Returns
	// plan_dict().
	::godot::Dictionary plan(const ::godot::Dictionary &params);
	// A saved header's bytes (NET-09's resume): false, changing nothing, unless they are one whole
	// header for the configured seed.
	bool load_plan(const ::godot::PackedByteArray &bytes);
	// The header, serialised canonically (what a save keeps).
	::godot::PackedByteArray plan_bytes() const;
	// {ok, error, list_kind, jobs, cans, solo, draw, staging, hard_variant, generator_version,
	// hash_version, template_version, data_version, sites: [{kind, need, door, door_side, cells,
	// holds: {item: count}, spine, attempt}], spines: [{site, gate, cells, replan}], revolver,
	// revolver_cell, boxes, homes: [names], bytes}; server-only, never sent.
	::godot::Dictionary plan_dict() const;
	bool is_spine_cell(::godot::Vector2i cell) const;
	// GEN-10's and HAZ-01's sections of the header.
	void set_home(const ::godot::String &name, const ::godot::PackedByteArray &bytes);
	::godot::PackedByteArray home(const ::godot::String &name) const;

	// GEN-09 (configure with poi first; none otherwise). A point of interest as {region, index,
	// kind, planned (the plan's site index, -1 if drawn), template (its template's id, "" for a
	// planned site no template fits), orientation, origin, size, door, door_side, cells, biome,
	// slots: [Rect2i world tiles, its contents lines' slots in order]}.
	// The point of interest a cell lies in, or {}.
	::godot::Dictionary poi_at(::godot::Vector2i cell) const;
	// A region's layout: {region, wanted, pois: [...]}.
	::godot::Dictionary poi_region(::godot::Vector2i region) const;
	// What a point of interest holds, its lines in order: [{line (-1: the phone's wall fixture),
	// thing, oil_milli, notches, with}]; [] for none.
	::godot::Array poi_contents(::godot::Vector2i region, int64_t index) const;
	// The header's "canary" home (GEN-10 names the canary region): its bytes for set_home.
	static ::godot::PackedByteArray canary_home(::godot::Vector2i region);

	// GEN-10 (configure with place: {remains_probability, remains_rings, remains_items: {name:
	// probability}, remains_items_max, found_oil: [lo, hi], found_notches: [lo, hi],
	// paraffin_probability, paraffin_rings, electric_lamp_probability, electric_lamp_max,
	// electric_lamp_min_ring, revolver_rounds, box_rounds, phone_ring12_probability,
	// phone_beyond_probability, phones_near_gates, phones_near_gates_path: [lo, hi],
	// air_door_probability, collapse_probability, collapse_min_from_basecamp, collapse_min_spacing,
	// collapse_min_from_sites, firedamp_ring2_probability, firedamp_beyond_probability,
	// firedamp_black_seam_probability, blackdamp_probability, man_trap_probability,
	// man_trap_min_ring, staple_pit_probability, staple_pit_min_ring, sump_mud_probability,
	// sump_mud_min_ring, staged_traps_min_ring and staged_roost_min_from_shaft (by stage),
	// traps_min_ring, roost_min_from_shaft, roosts: [min, max],
	// roost_max_from_hoard, coat_heap_near_hoard, coat_heap_near_probability,
	// coat_heap_far_probability, coat_heaps: [min, max], rich_rock_per_region,
	// rich_rock_min_thickness, landmark_no_repeat_cells, landmark_palette, canary_max}).
	// The run-start homes pass, after plan(): the roosts, the start roost, the near-gate phones,
	// the electric lamp's cell and the canary region, into the header's homes. Returns homes_dict().
	::godot::Dictionary make_homes();
	// {roosts: [Rect2i world tiles], start_roost (-1: the hoard), hoard (Vector2i tile, or null),
	// gate_phones: [Vector2i], electric_lamp (cell, or null), canary (region, or null)}.
	::godot::Dictionary homes_dict() const;
	// What a cell holds as it generates, in pass order: [{kind, thing, source, anchor, tile, size,
	// count, oil_milli, notches, variant, collapse, with, id (GEN-13's "p" and 16 hex digits)}];
	// [] for base camp. With the validator, the list phase 2 passed (a retry's, or strict mode's).
	// Server-only, never sent.
	::godot::Array place(::godot::Vector2i cell) const;
	// Before commit: the cell's air doors (wooden door tiles) and sump mud (the mud bit) into its
	// data, its zones cut again when a door went in. The tiles changed.
	int64_t dress(::godot::Vector2i cell, const ::godot::Ref<LbCellData> &data) const;
	// GEN-14: what the cells hold, {"item:gauze_lamp": n, "remains": n, ...}.
	::godot::Dictionary find_counts(const ::godot::TypedArray<::godot::Vector2i> &cells) const;
	// CRT-08: a region's Tapper-rich rock masses (Rect2i world tiles).
	::godot::Array rich_rock_masses(::godot::Vector2i region) const;

	// GEN-12's validator (configure with validate: {rules: {road_width_min, road_width_max,
	// chamber_min, chamber_max, chamber_forbidden_width, tapper_reach_milli, lair_kind}, max_retries,
	// max_replans, arch_reach: {side: tiles}}). Server-only: nothing here is ever sent.
	// Phase 2's account of a cell: {retry, strict, dropped, failures: [{rule, check, tile, detail}]}.
	::godot::Dictionary placement_report(::godot::Vector2i cell) const;
	// Run start, after plan() and before make_homes(): every spine walked from its gate to its
	// target's door with the collapse points its cells arm fallen (a failing one replanned from its
	// next sub-seed, at most max_replans times, into the header), then base camp's gates.
	// {ok, replans, spines: [{site, reached, replans, rule, check, tile, detail}], gates: {ok, rule, check, tile, detail}}.
	::godot::Dictionary validate_run_start();
	// The run's counts since the last rebuild: {totals: {key: n}, notes: [text]} (ValidatorCounters).
	::godot::Dictionary validator_stats() const;
	// Every socket set (each edge shut or open at each offset and width in `widths`) fitted to
	// `biome`'s plain fallback and checked by phase 1: {checked, failures: [{sockets, rule, check, tile, detail}]}.
	::godot::Dictionary fallback_coverage(const ::godot::String &biome, const ::godot::PackedInt32Array &widths) const;

	// GEN-11's worker pool: `threads` workers derive wanted cells (0: synchronous, in take()),
	// below normal priority if `background` (a server on a player's machine). Set the deriver up
	// first; reconfiguring restarts the pool and forgets every job.
	void start_pool(int64_t threads, bool background = false);
	void stop_pool();
	// Ask for a cell (lower priority first; asking again re-prioritises), or stop asking.
	void want(::godot::Vector2i cell, int64_t priority);
	void unwant(::godot::Vector2i cell);
	// Up to `max` finished cells, nearest first: derive()'s dictionaries with "ms" added.
	::godot::Array take(int64_t max);
	// {threads, queued, running, finished, derived, p50_ms, p99_ms}
	::godot::Dictionary pool_stats() const;

	// The window sets (GEN-11): every cell within `radius` (Chebyshev) of a holder's cell; and the
	// loaded cells to drop (beyond `evict` of every holder, then the farthest spare ones over
	// `max_live`), never a pinned one.
	static ::godot::Array required_cells(const ::godot::Array &holders, int64_t radius);
	static ::godot::Array evictions(const ::godot::Array &loaded, const ::godot::Array &holders, const ::godot::Array &pinned,
			int64_t generate, int64_t evict, int64_t max_live);

	// GEN-11's window manager over the pool: the required radius and the prefetch radius beyond it.
	// Starting the pool (or reconfiguring) forgets the window, so the next update asks afresh.
	void set_window(int64_t radius, int64_t prefetch_radius);
	// The window holders' cells this tick. When they moved: cells new to the prefetch set that
	// `mine` lacks are asked of the pool (the nearest first), cells gone from it are dropped, and
	// cells still asked for are re-prioritised. {moved, entered: cells new to the required set
	// that are not loaded, entered_loaded: how many new ones were, left: cells gone from it}
	::godot::Dictionary update_window(const ::godot::TypedArray<::godot::Vector2i> &holders, const ::godot::Ref<LbMine> &mine);
	// The loaded cells of `mine` to drop now, in order: beyond `evict` of every holder, then over
	// `max_live` the farthest beyond the prefetch ring; never a pinned one.
	::godot::TypedArray<::godot::Vector2i> evictions_now(const ::godot::Ref<LbMine> &mine, const ::godot::TypedArray<::godot::Vector2i> &pinned,
			int64_t evict, int64_t max_live) const;

private:
	std::shared_ptr<lb::core::gen::TemplateSet> set_;
	lb::core::gen::RunHeader header_;
	std::unique_ptr<lb::core::gen::CellClassifier> cells_;
	bool has_roads_ = false;
	lb::core::gen::MainRoadParams road_params_;
	std::vector<int64_t> ring_bounds_{80, 200, 400, 700};
	std::unique_ptr<lb::core::gen::MainRoads> roads_;
	std::unique_ptr<lb::core::gen::MainRoadCells> road_cells_;
	std::unique_ptr<lb::core::gen::MainRoadSockets> road_sockets_;
	std::unique_ptr<lb::core::gen::SpineSockets> spine_sockets_;
	bool has_poi_ = false;
	lb::core::gen::PoiParams poi_params_;
	lb::core::gen::PoiContentsParams contents_params_;
	std::unique_ptr<lb::core::gen::PointsOfInterest> pois_;
	// The template set's point-of-interest shapes, made again only for a new set or socket offsets.
	std::shared_ptr<const lb::core::gen::PoiShapes> poi_shapes_;
	std::shared_ptr<lb::core::gen::TemplateSet> poi_shapes_set_;
	std::vector<int32_t> poi_shapes_offsets_;
	std::unique_ptr<lb::core::gen::PoiCells> poi_cells_;
	std::unique_ptr<lb::core::gen::PoiSockets> poi_sockets_;
	std::unique_ptr<lb::core::gen::Deriver> deriver_;
	// GEN-10: placement over this deriver, its classes and points of interest.
	bool has_place_ = false;
	lb::core::gen::PlacementParams place_params_;
	std::unique_ptr<lb::core::gen::PlacementWorld> place_world_;
	// GEN-12: the validator and its counts (cleared at every rebuild).
	bool has_validator_ = false;
	lb::core::gen::ValidatorParams validator_params_;
	std::shared_ptr<lb::core::gen::ValidatorCounters> counters_ = std::make_shared<lb::core::gen::ValidatorCounters>();
	std::vector<lb::core::gen::Placement> placed(lb::core::world::Coord cell) const;
	std::unique_ptr<lb::core::gen::GenPool> pool_;
	int64_t pool_threads_ = -1; // -1: no pool
	bool pool_background_ = false;
	int32_t window_radius_ = 4;
	int32_t window_prefetch_ = 5;
	std::unique_ptr<lb::core::gen::Window> window_;
	std::set<lb::core::world::Coord> asked_; // handed to the pool and not yet taken
	void reset_window();
	bool caching_ = true;
	bool verify_ = false;
	void rebuild();
};

} // namespace lb::godot

#pragma once
// GDScript face of GEN-05's layout stage (core/gen/derive.h): the run's template pack, its
// sockets and its derived cell layouts. Set it up first (load_pack, configure, force_socket);
// after that socket() and derive() are pure and thread-safe, for GEN-11's workers. Server-only:
// no socket, layout or seed reaches a client (NET-08).

#include "core/gen/gen_pool.h"
#include "core/gen/main_roads.h"

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/vector2i.hpp>

#include <memory>
#include <set>

namespace lb::godot {

class LbMine;

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
	// biome (one biome for every cell, for tests); and main_roads (GEN-07: {spacing, width, offset,
	// run_min, run_max, max_ring, old_fall_probability}) to lay main roads over the biomes.
	void configure(int64_t seed, const ::godot::Dictionary &params);
	// A socket forced up front (base camp's): socket {open, offset, width}. side: north, east, south, west.
	bool force_socket(::godot::Vector2i cell, const ::godot::String &side, const ::godot::Dictionary &socket);
	// {open, offset, width, forced}
	::godot::Dictionary socket(::godot::Vector2i cell, const ::godot::String &side) const;
	// The cell's biome (GEN-06), "" for base camp; server-only, never sent.
	::godot::String biome_of(::godot::Vector2i cell) const;
	// GEN-07: {main_road, crossing, shape, old_fall, transpose, dress} of a cell.
	::godot::Dictionary road_of(::godot::Vector2i cell) const;
	// {ok, base_camp, fallback, template, sockets: {side: {...}}, cell: LbCellData (none for base camp), digest}
	::godot::Dictionary derive(::godot::Vector2i cell, int64_t reroll) const;
	void set_caching(bool on);
	void clear_caches();
	void set_verify(bool on);
	int64_t verify_failures() const;

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
	std::unique_ptr<lb::core::gen::Deriver> deriver_;
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

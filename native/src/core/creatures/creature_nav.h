#pragma once
// CRT-02's creature navigation over GEN-01's mine and VIS-02's light grid. Four modes:
//  - WALKER (the Moth hunting or fleeing): walkable floor and closed air doors (the follower
//    holds it 3 s at one); shut gates block.
//  - CRAWLER (the Moth prowling and homing): as WALKER, but an open tile costs crawl_open_cost
//    times a wall-adjacent one, so it hugs the ribs.
//  - DARK (the Stythe): walkable floor lit below the threshold; closed doors and gates block.
//  - ROCK (the Tapper): rock and coal; open floor beneath which it may pass unless within
//    brick_clearance of brick; never brick, timber, steel or doors.
// Unloaded tiles are solid and unknown. 8-connected, no corner cutting; every tie breaks by
// tile order (y, then x), so paths are identical on every platform. Tick thread only.

#include "core/light/light_grid.h"
#include "core/world/mine_map.h"

#include <cstdint>
#include <optional>
#include <vector>

namespace lb::core::creatures {

using world::Coord;

enum class NavMode : uint8_t { WALKER = 0, CRAWLER = 1, DARK = 2, ROCK = 3 };

struct NavParams {
	int64_t dark_threshold_milli = 300; // DARK: lit to this or more is a wall
	int64_t max_cost_milli = -1;        // stop beyond this path cost (-1: none)
	int64_t max_expansions = -1;        // stop after this many nodes (-1: none)
	int64_t crawl_open_cost = 3;        // CRAWLER: an open tile's cost multiple
	bool rock_crosses_floor = true;     // ROCK: may pass beneath open floor
	int64_t brick_clearance = 2;        // ROCK: never beneath floor within this of brick
};

struct NavPath {
	std::vector<Coord> tiles; // start to goal, both included; empty when not found
	int64_t cost_milli = -1;
	bool found = false;
	bool hit_limit = false;        // stopped by max_cost_milli or max_expansions
	bool touched_unloaded = false; // the search met ungenerated ground
	size_t expansions = 0;
};

class CreatureNav {
public:
	CreatureNav(const world::MineMap &mine, const light::LightGrid *light) : mine_(mine), light_(light) {}

	bool loaded(Coord t) const;
	bool passable(NavMode mode, Coord t, const NavParams &p) const;
	int64_t light_milli(Coord t) const;
	bool wall_adjacent(Coord t) const;
	bool near_brick(Coord t, int64_t clearance) const;

	NavPath path(NavMode mode, Coord from, Coord to, const NavParams &p) const;
	// To whichever goal is cheapest to reach (ties by goal order of reaching, then tile order).
	NavPath path_to_any(NavMode mode, Coord from, const std::vector<Coord> &goals, const NavParams &p) const;
	// Every tile of the path is still passable in this mode now.
	bool still_valid(NavMode mode, const std::vector<Coord> &tiles, const NavParams &p) const;

	// The walkable tile below the threshold whose centre is nearest (x, y), within max_radius.
	std::optional<Coord> nearest_dark_tile(double x, double y, int64_t threshold_milli, int64_t max_radius) const;
	// Of the tiles DARK can reach from `from`, the one nearest `target` in a straight line.
	std::optional<Coord> reachable_dark_tile_nearest(Coord target, Coord from, const NavParams &p) const;
	// The dark walkable tiles bordering the lit walkable area that contains `seed`.
	std::vector<Coord> light_edge_ring(Coord seed, int64_t threshold_milli, int64_t max_tiles) const;

	// Usable wall faces (GEN-01: rock or coal touching open floor) whose square lies within r
	// of (x, y), ascending tile order.
	std::vector<Coord> usable_faces_within(double x, double y, double r) const;
	std::optional<Coord> nearest_usable_face(double x, double y, int64_t max_radius) const;
	// A usable face is the rock the Tapper stands in; for an open tile, the face beside it.
	std::optional<Coord> rock_tile_behind(Coord tile) const;

	// The guard queries (Gameplay §7.1), each bounded by its length and by max_expansions.
	NavPath moth_path_within(Coord from, double mx, double my, double max_tiles, int64_t max_expansions) const;
	NavPath tapper_rock_path_within(Coord from, double mx, double my, double max_tiles, double reach, const NavParams &p) const;
	NavPath stythe_dark_path_within(Coord from, double mx, double my, double max_tiles, double within, const NavParams &p) const;

private:
	const world::MineMap &mine_;
	const light::LightGrid *light_;

	int64_t step_multiple(NavMode mode, Coord t, const NavParams &p) const;
	NavPath search(NavMode mode, Coord from, const std::vector<Coord> &goals, const NavParams &p) const;
};

} // namespace lb::core::creatures

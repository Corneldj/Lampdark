#pragma once
// NET-08's reference reach, for the stream audit's audio and voice rules. Independent of SND-01's
// Road Graph: a search over the mine's tiles, from the design's definitions (GDD §15.4, §15.5).
//   - Sound: -1 np a tile walked, -12 at a closed air door or shut gate. The search steps to all
//     eight neighbours at a cost of 1, so it never finds a path longer than the Road Graph's: a
//     delivery the reference cannot reach is a leak, never a disagreement over route shape.
//     Portals are free (SND-01's rule, so a 14 np strike at a shut gate's inner face reaches the far
//     side at exactly 2): a step onto or off a portal tile (an opening, a door, a gate) costs nothing.
//   - Voice by road: the same, but a closed door or shut gate stops it.
//   - Voice through rock: the tiles a straight line from centre to centre touches (corners count
//     both ways); never brick, never a door or gate, and only so many solid tiles.

#include "audit/reference_vis.h"

#include <functional>
#include <vector>

namespace lb::audit {

enum TileKind : uint8_t {
	OPEN = 0,
	SOLID = 1,
	PORTAL_CLOSED = 2,
	PORTAL_OPEN = 3,
};

// The cheapest cost from any origin to `to`, or a negative number when nothing reaches it within
// `max_cost`. `kind(tile)` classifies a tile; `voice` makes closed portals impassable.
double reach_cost(const std::vector<Pos> &origins, Pos to, double max_cost, bool voice, double closed_cost,
		const std::function<uint8_t(Pos)> &kind);

struct Line {
	int64_t solid = 0;
	bool brick = false;
	bool door = false;
	double distance = 0.0;
};

// The straight line between two tile centres: every tile it touches but the two ends.
// `solid(tile)`, `brick(tile)` and `door(tile)` read the mine.
Line straight_line(Pos from, Pos to, const std::function<bool(Pos)> &solid, const std::function<bool(Pos)> &brick,
		const std::function<bool(Pos)> &door);

} // namespace lb::audit

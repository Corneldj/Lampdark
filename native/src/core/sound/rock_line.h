#pragma once
// The rock-line query (SND-01): the tiles a straight line between two tile centres crosses
// (a supercover, so corner-touching tiles count), for voice through thin rock (SND-07) and
// rock taps (SND-12). Pure; reads the mine's materials.

#include "core/world/mine_map.h"

#include <vector>

namespace lb::core::sound {

using lb::core::world::Coord;

struct RockLine {
	std::vector<Coord> tiles;    // crossed tiles, endpoints excluded, from `from` towards `to`
	int64_t solid_tiles = 0;     // how many of them are solid
	bool brick = false;          // a brick tile on the line
	bool door = false;           // a gate or air door tile on the line
	double distance = 0.0;       // centre to centre, in tiles
	bool has_face = false;
	Coord listener_face;         // the last solid tile before `to`: the listener's side
};

RockLine rock_line(const lb::core::world::MineMap &mine, Coord from, Coord to);

} // namespace lb::core::sound

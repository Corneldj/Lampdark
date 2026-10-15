#pragma once
// VIS-10: the Stythe's bite (Gameplay §5.8, GDD §15.3). While its tell plays (Hunt, WindUp, Drag,
// Collect: CRT-14 decides), the floor tiles within `range` of its tile (the Chebyshev block) lit
// below `below` thousandths (0.30, the Thin 0.50) leave every seen set and margin, with anything
// standing on them (Vision::set_bite_tiles). Nothing names or flags them: a client only finds the
// tiles missing, a hard black notch out of the pool's edge. Engine-free.

#include "core/light/light_grid.h"
#include "core/world/mine_map.h"

#include <cstdint>
#include <set>

namespace lb::core::vision {

std::set<world::Coord> bite_tiles(const world::MineMap &map, const light::LightGrid &light, double x, double y,
		int64_t range, int64_t below);

} // namespace lb::core::vision

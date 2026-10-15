#include "core/vision/bite.h"

#include <cmath>

namespace lb::core::vision {

std::set<world::Coord> bite_tiles(const world::MineMap &map, const light::LightGrid &light, double x, double y,
		int64_t range, int64_t below) {
	std::set<world::Coord> out;
	const int64_t cx = static_cast<int64_t>(std::floor(x));
	const int64_t cy = static_cast<int64_t>(std::floor(y));
	for (int64_t dy = -range; dy <= range; dy++) {
		for (int64_t dx = -range; dx <= range; dx++) {
			const world::Coord t{cx + dx, cy + dy};
			if (!map.is_walkable(t, true)) {
				continue; // floor only: rock is never bitten (a door or gate counts as floor)
			}
			if (light.tile_light(t).value < below) {
				out.insert(t);
			}
		}
	}
	return out;
}

} // namespace lb::core::vision

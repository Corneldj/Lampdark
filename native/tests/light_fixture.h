#pragma once
// Helpers for VIS-02's tests: an open floor room and point sources.

#include "core/light/light_grid.h"
#include "mine_fixture.h"

namespace light_fixture {

using namespace lb::core::light;
using lb::core::world::Coord;

inline std::vector<std::string> open_floor() {
	std::vector<std::string> rows(lb::core::world::CELL_TILES, std::string(lb::core::world::CELL_TILES, '.'));
	return rows;
}

inline SourceDesc lamp(double x, double y, double radius, uint32_t owner = 0) {
	SourceDesc d;
	d.shape = Shape::POINT;
	d.kind = "gauze_lamp";
	d.colour = ColourClass::AMBER;
	d.flags = flag::FLAME | flag::CARRIED;
	d.owner = owner;
	d.radius = radius;
	d.peak = 1.0;
	d.x = x;
	d.y = y;
	return d;
}

// A 3x3 block of open-floor cells centred on (0, 0).
inline void load_open(MineMap &mine, LightGrid *grid = nullptr) {
	for (int64_t cy = -1; cy <= 1; cy++) {
		for (int64_t cx = -1; cx <= 1; cx++) {
			mine.commit(mine_fixture::cell_from({cx, cy}, open_floor()));
			if (grid != nullptr) {
				grid->on_cell_loaded({cx, cy});
			}
		}
	}
}

} // namespace light_fixture

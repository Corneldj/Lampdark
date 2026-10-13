#include "core/world/coords.h"

namespace lb::core::world {

namespace {

int64_t abs64(int64_t v) {
	return v < 0 ? -v : v;
}

} // namespace

int64_t cell_chebyshev(Coord a, Coord b) {
	const int64_t dx = abs64(a.x - b.x);
	const int64_t dy = abs64(a.y - b.y);
	return dx > dy ? dx : dy;
}

int64_t cell_manhattan(Coord a, Coord b) {
	return abs64(a.x - b.x) + abs64(a.y - b.y);
}

int64_t ring_of_tile(Coord tile, const std::vector<int64_t> &bounds) {
	const int64_t dx = 2 * tile.x + 1 - SHAFT_CENTRE_X2;
	const int64_t dy = 2 * tile.y + 1 - SHAFT_CENTRE_Y2;
	const int64_t d2 = dx * dx + dy * dy;
	int64_t ring = 0;
	for (int64_t bound : bounds) {
		if (d2 >= (2 * bound) * (2 * bound)) {
			ring++;
		}
	}
	return ring;
}

int64_t ring_of_point(double x, double y, const std::vector<int64_t> &bounds) {
	const double dx = x - static_cast<double>(SHAFT_CENTRE_X2) / 2.0;
	const double dy = y - static_cast<double>(SHAFT_CENTRE_Y2) / 2.0;
	const double d2 = dx * dx + dy * dy;
	int64_t ring = 0;
	for (int64_t bound : bounds) {
		const double b = static_cast<double>(bound);
		if (d2 >= b * b) {
			ring++;
		}
	}
	return ring;
}

} // namespace lb::core::world

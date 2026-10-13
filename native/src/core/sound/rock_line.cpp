#include "core/sound/rock_line.h"

#include <cmath>
#include <cstdlib>

namespace lb::core::sound {

using lb::core::world::TileMaterial;

RockLine rock_line(const lb::core::world::MineMap &mine, Coord from, Coord to) {
	RockLine out;
	const int64_t dx = to.x - from.x;
	const int64_t dy = to.y - from.y;
	out.distance = std::sqrt(static_cast<double>(dx * dx + dy * dy));
	// Supercover walk (integer): step in x, y, or both at an exact corner crossing.
	const int64_t nx = std::llabs(dx);
	const int64_t ny = std::llabs(dy);
	const int64_t sx = dx > 0 ? 1 : -1;
	const int64_t sy = dy > 0 ? 1 : -1;
	Coord p = from;
	auto add = [&](Coord t) {
		if (t == from || t == to) {
			return;
		}
		out.tiles.push_back(t);
		const TileMaterial m = static_cast<TileMaterial>(mine.tile_at(t) ? mine.tile_at(t)->material : static_cast<uint8_t>(TileMaterial::ROCK));
		if (mine.is_solid(t)) {
			out.solid_tiles++;
			out.has_face = true;
			out.listener_face = t;
		}
		if (m == TileMaterial::BRICK) {
			out.brick = true;
		}
		if (m == TileMaterial::STEEL || m == TileMaterial::WOODEN_DOOR) {
			out.door = true;
		}
	};
	for (int64_t ix = 0, iy = 0; ix < nx || iy < ny;) {
		const int64_t decision = (1 + 2 * ix) * ny - (1 + 2 * iy) * nx;
		if (decision == 0) {
			// Through a corner: both neighbours are touched.
			add({p.x + sx, p.y});
			add({p.x, p.y + sy});
			p.x += sx;
			p.y += sy;
			ix++;
			iy++;
		} else if (decision < 0) {
			p.x += sx;
			ix++;
		} else {
			p.y += sy;
			iy++;
		}
		add(p);
	}
	return out;
}

} // namespace lb::core::sound

#include "core/vision/shadow_tell.h"

#include <algorithm>
#include <cmath>

namespace lb::core::vision {

namespace {

bool casts(const PerceptionTable &table, const sim::MirrorEntity &e, const ShadowParams &p) {
	if (p.never_cast.count(e.kind) != 0) {
		return false;
	}
	const SizeClass c = table.get(e.kind).size;
	return c == SizeClass::MINER || c == SizeClass::LARGE || c == SizeClass::LARGE_MOTIONLESS;
}

// Where the light comes from, and how far its shadow reaches: a point light from its position;
// a spill along its direction; an area or a spot from its tiles' centre.
bool light_origin(const light::LightGrid &light, uint32_t source, double &ox, double &oy, double &reach) {
	const std::optional<light::SourceDesc> s = light.source(source);
	if (!s) {
		return false;
	}
	reach = s->radius * light.radius_mult(source);
	switch (s->shape) {
		case light::Shape::POINT:
			ox = s->x;
			oy = s->y;
			return reach > 0.0;
		case light::Shape::SPILL:
			if (s->tiles.empty()) {
				return false;
			}
			ox = static_cast<double>(s->tiles[0].x) + 0.5 - s->dir.x * 1000.0;
			oy = static_cast<double>(s->tiles[0].y) + 0.5 - s->dir.y * 1000.0;
			return reach > 0.0;
		default: {
			double sx = 0.0, sy = 0.0;
			size_t n = 0;
			for (const world::Coord &t : s->tiles) {
				sx += static_cast<double>(t.x) + 0.5;
				sy += static_cast<double>(t.y) + 0.5;
				n++;
			}
			if (s->shape == light::Shape::SPOT) {
				sx = static_cast<double>(s->spot.x) + 0.5;
				sy = static_cast<double>(s->spot.y) + 0.5;
				n = 1;
			}
			if (n == 0) {
				return false;
			}
			ox = sx / static_cast<double>(n);
			oy = sy / static_cast<double>(n);
			if (reach <= 0.0) {
				reach = 4.0;
			}
			return true;
		}
	}
}

} // namespace

std::map<world::Coord, uint8_t> compute_shadows(const world::MineMap &map, const light::LightGrid &light, const PerceptionTable &table,
		const std::vector<sim::MirrorEntity> &entities, const ShadowParams &p) {
	std::map<world::Coord, uint8_t> out;
	if (!p.enabled) {
		return out;
	}
	const int top = std::max(1, std::min(3, p.levels - 1));
	for (const sim::MirrorEntity &e : entities) {
		if (!casts(table, e, p)) {
			continue;
		}
		const world::Coord at{static_cast<int64_t>(std::floor(e.x)), static_cast<int64_t>(std::floor(e.y))};
		const light::TileLight tl = light.tile_light(at);
		if (tl.value < p.min_light || tl.brightest == 0) {
			continue;
		}
		double ox = 0.0, oy = 0.0, reach = 0.0;
		if (!light_origin(light, tl.brightest, ox, oy, reach)) {
			continue;
		}
		double dx = e.x - ox, dy = e.y - oy;
		const double len = std::sqrt(dx * dx + dy * dy);  // determinism: allow (a client tell only; no rule reads it)
		if (len < 1e-9) {
			continue;  // a light on the body itself casts no direction
		}
		dx /= len;
		dy /= len;
		const int steps = static_cast<int>(std::ceil(reach - 1e-9));
		world::Coord last = at;
		for (int s = 1; s <= steps; s++) {
			const world::Coord t{static_cast<int64_t>(std::floor(e.x + dx * s)), static_cast<int64_t>(std::floor(e.y + dy * s))};
			if (t == last) {
				continue;
			}
			last = t;
			if (map.is_opaque(t)) {
				break;
			}
			if (light.value(t) < p.lit_min) {
				continue;
			}
			// 3 next to the body, falling to 1 at the end.
			const int level = steps <= 1 ? top : 1 + static_cast<int>(std::floor((top - 1) * static_cast<double>(steps - s) / (steps - 1) + 1e-9));
			uint8_t &cell = out[t];
			cell = static_cast<uint8_t>(std::max<int>(cell, std::min(level, top)));
		}
	}
	return out;
}

} // namespace lb::core::vision

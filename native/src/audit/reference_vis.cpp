#include "audit/reference_vis.h"

#include <algorithm>
#include <array>
#include <cmath>

namespace lb::audit {

namespace {

constexpr double TAU = 6.283185307179586476925286766559;

// An exact slope num / den, den > 0.
struct Frac {
	int64_t num;
	int64_t den;
};

int64_t div_floor(int64_t a, int64_t b) {
	int64_t q = a / b;
	if ((a % b != 0) && ((a < 0) != (b < 0))) {
		q -= 1;
	}
	return q;
}

// The column of the first tile in a row: depth * slope rounded, halves going up.
int64_t first_col(int64_t depth, Frac s) {
	return div_floor(2 * depth * s.num + s.den, 2 * s.den);
}

// The last tile's column: depth * slope rounded, halves going down.
int64_t last_col(int64_t depth, Frac s) {
	return -div_floor(s.den - 2 * depth * s.num, 2 * s.den);
}

struct Caster {
	Pos origin;
	int64_t limit;
	const Blocks &blocks;
	std::set<Pos> &out;
	int quadrant = 0;

	Pos at(int64_t depth, int64_t col) const {
		switch (quadrant) {
			case 0: return {origin.x + col, origin.y - depth};
			case 1: return {origin.x + col, origin.y + depth};
			case 2: return {origin.x + depth, origin.y + col};
			default: return {origin.x - depth, origin.y + col};
		}
	}

	// One row of a quadrant, recursing into the rows beyond each gap (Ford's scan).
	void scan(int64_t depth, Frac start, Frac end) {
		if (depth > limit) {
			return;
		}
		int prev = -1; // -1 none, 0 floor, 1 wall
		const int64_t lo = first_col(depth, start);
		const int64_t hi = last_col(depth, end);
		for (int64_t col = lo; col <= hi; col++) {
			const Pos p = at(depth, col);
			const bool wall = blocks(p);
			// The tile's centre slope col / depth inside [start, end]: symmetric.
			const bool inside = col * start.den >= depth * start.num && col * end.den <= depth * end.num;
			if (wall || inside) {
				out.insert(p);
			}
			if (prev == 1 && !wall) {
				start = Frac{2 * col - 1, 2 * depth};
			}
			if (prev == 0 && wall) {
				scan(depth + 1, start, Frac{2 * col - 1, 2 * depth});
			}
			prev = wall ? 1 : 0;
		}
		if (prev == 0) {
			scan(depth + 1, start, end);
		}
	}
};

double light_at_distance(double d, double radius, double peak, const LightDefs &l) {
	if (radius <= 0.0 || d < 0.0 || d > radius) {
		return 0.0;
	}
	if (peak <= l.core_value) {
		return peak + (l.edge_value - peak) * (d / radius);
	}
	const double core = l.core_fraction * radius;
	if (d <= core) {
		return peak + (l.core_value - peak) * (d / core);
	}
	return l.core_value + (l.edge_value - l.core_value) * ((d - core) / (radius - core));
}

int64_t milli(double v, const LightDefs &l) {
	return std::llround(v * static_cast<double>(l.scale));
}

struct Unit {
	double x;
	double y;
};

Unit unit_turns(double turns) {
	return {std::cos(turns * TAU), std::sin(turns * TAU)};
}

Unit unit_facing(uint32_t facing) {
	return unit_turns(static_cast<double>(facing & 0xFFFFu) / 65536.0);
}

Pos tile_at_point(double x, double y) {
	return {static_cast<int64_t>(std::floor(x)), static_cast<int64_t>(std::floor(y))};
}

struct Cone {
	double ax, ay;
	Unit f;
	double cos_half;

	Cone(double x, double y, uint32_t facing, double cone_deg)
		: ax(x), ay(y), f(unit_facing(facing)), cos_half(std::cos(cone_deg * 0.5 * TAU / 360.0)) {}

	bool contains(double px, double py) const {
		const double vx = px - ax, vy = py - ay;
		const double len2 = vx * vx + vy * vy;
		if (len2 <= 0.25) {
			return true; // within half a tile of the apex: the floor underfoot
		}
		const double dot = vx * f.x + vy * f.y;
		if (cos_half >= 0.0) {
			return dot >= 0.0 && dot * dot >= cos_half * cos_half * len2;
		}
		return dot >= 0.0 || dot * dot <= cos_half * cos_half * len2;
	}
};

struct Eval {
	const Observer &o;
	const VisionDefs &d;
	const std::map<Pos, TileLight> &light;
	std::set<Pos> los;
	Pos here;

	int64_t light_of(Pos t) const {
		auto it = light.find(t);
		return it == light.end() ? 0 : it->second.value;
	}

	State state(const Cone &cone, Pos t, int64_t &lit) const {
		lit = 0;
		if (o.blinded) {
			return BLINDED;
		}
		const int64_t dx = t.x - here.x, dy = t.y - here.y;
		if (dx * dx + dy * dy > d.range * d.range) {
			return BEYOND_RANGE;
		}
		const double cx = static_cast<double>(t.x) + 0.5, cy = static_cast<double>(t.y) + 0.5;
		if (o.clamp > 0.0) {
			const double ex = cx - o.x, ey = cy - o.y;
			if (ex * ex + ey * ey > o.clamp * o.clamp) {
				return BEYOND_RANGE;
			}
		}
		if (los.count(t) == 0) {
			return NO_LOS;
		}
		if (!cone.contains(cx, cy)) {
			return OUTSIDE_CONE;
		}
		if (o.bite.count(t) != 0) {
			return BITE;
		}
		lit = light_of(t);
		return lit < d.seen_min ? DARK : SEEN;
	}

	// The brightest tile of an entity's footprint that is seen or dark, and why it falls short.
	int64_t entity_light(const Cone &cone, const Entity &e, State &why) const {
		const int64_t f = std::max<int64_t>(1, e.footprint);
		const double half = static_cast<double>(f) * 0.5;
		const Pos lo = tile_at_point(e.x - half + 0.5, e.y - half + 0.5);
		int64_t best = -1;
		State reason = UNKNOWN;
		for (int64_t yy = 0; yy < f; yy++) {
			for (int64_t xx = 0; xx < f; xx++) {
				int64_t lit = 0;
				const State s = state(cone, Pos{lo.x + xx, lo.y + yy}, lit);
				if ((s == SEEN || s == DARK) && lit > best) {
					best = lit;
				}
				if (reason == UNKNOWN || s < reason) {
					reason = s;
				}
			}
		}
		why = best >= d.seen_min ? SEEN : (best >= 0 ? DARK : reason);
		return best;
	}

	int band(const Cone &cone, Pos t) const {
		int64_t lit = 0;
		if (state(cone, t, lit) != DARK) {
			return 0;
		}
		const double cx = static_cast<double>(t.x) + 0.5, cy = static_cast<double>(t.y) + 0.5;
		int out = 0;
		for (const auto &l : o.own_lights) {
			const double r = l.second;
			const double dx = cx - l.first.first, dy = cy - l.first.second;
			const double d2 = dx * dx + dy * dy;
			if (d2 <= r * r) {
				continue;
			}
			const double e = r + d.margin_entity, g = r + d.margin_geometry;
			if (d2 <= e * e) {
				return 2;
			}
			if (d2 <= g * g) {
				out = 1;
			}
		}
		return out;
	}
};

int64_t bucket_total(const VisionDefs &d) {
	return std::max<int64_t>(1, static_cast<int64_t>(d.cone_deg / d.bucket_deg + 0.5));
}

} // namespace

std::set<Pos> symmetric_fov(Pos origin, int64_t depth, const Blocks &blocks) {
	std::set<Pos> out;
	out.insert(origin);
	Caster c{origin, depth, blocks, out};
	for (int q = 0; q < 4; q++) {
		c.quadrant = q;
		c.scan(1, Frac{-1, 1}, Frac{1, 1});
	}
	return out;
}

std::map<Pos, TileLight> light_window(const std::vector<Source> &sources, const LightDefs &defs, const Blocks &blocks,
		const std::function<bool(Pos)> &exists, int64_t x0, int64_t y0, int64_t x1, int64_t y1) {
	std::vector<Source> ordered = sources;
	std::sort(ordered.begin(), ordered.end(), [](const Source &a, const Source &b) { return a.id < b.id; });
	std::map<Pos, int64_t> total;
	std::map<Pos, std::pair<int64_t, uint8_t>> brightest;
	auto inside = [&](Pos p) { return p.x >= x0 && p.x <= x1 && p.y >= y0 && p.y <= y1; };
	for (const Source &s : ordered) {
		std::map<Pos, int64_t> mine; // this source's light: its brightest value per tile
		auto put = [&](Pos p, int64_t v) {
			if (v <= 0 || !exists(p)) {
				return;
			}
			int64_t &slot = mine[p];
			slot = std::max(slot, std::min<int64_t>(v, 65535));
		};
		if (s.shape == POINT) {
			const double r = s.radius * s.radius_mult;
			const Pos origin = tile_at_point(s.x, s.y);
			if (r <= 0.0 || blocks(origin)) {
				continue;
			}
			const int64_t reach = static_cast<int64_t>(std::ceil(r)) + 1;
			if (origin.x + reach < x0 || origin.x - reach > x1 || origin.y + reach < y0 || origin.y - reach > y1) {
				continue;
			}
			for (const Pos &t : symmetric_fov(origin, reach, blocks)) {
				const double dx = static_cast<double>(t.x) + 0.5 - s.x;
				const double dy = static_cast<double>(t.y) + 0.5 - s.y;
				put(t, milli(light_at_distance(std::sqrt(dx * dx + dy * dy), r, s.peak, defs), defs));
			}
		} else if (s.shape == AREA) {
			for (const Pos &t : s.tiles) {
				put(t, milli(s.peak, defs));
			}
		} else if (s.shape == SPOT) {
			put(s.spot, milli(s.peak, defs));
		} else if (s.shape == SPILL) {
			bool shut = s.tiles.empty();
			for (const Pos &door : s.tiles) {
				shut = shut || blocks(door);
			}
			if (shut) {
				continue;
			}
			const int64_t reach = static_cast<int64_t>(std::ceil(s.radius)) + 1;
			for (const Pos &door : s.tiles) {
				for (const Pos &t : symmetric_fov(door, reach, blocks)) {
					const int64_t depth = (t.x - door.x) * s.dir.x + (t.y - door.y) * s.dir.y;
					if (depth < 1) {
						continue;
					}
					const double dist = static_cast<double>(depth) - 0.5;
					if (dist > s.radius) {
						continue;
					}
					put(t, milli(s.peak + (s.end_value - s.peak) * (dist / s.radius), defs));
				}
			}
		}
		for (const auto &[p, v] : mine) {
			if (!inside(p)) {
				continue;
			}
			total[p] += v;
			auto it = brightest.find(p);
			if (it == brightest.end() || v > it->second.first) {
				brightest[p] = {v, s.colour};
			}
		}
	}
	std::map<Pos, TileLight> out;
	const int64_t cap = milli(defs.cap, defs);
	for (const auto &[p, v] : total) {
		out[p] = TileLight{std::min(v, cap), brightest[p].second};
	}
	return out;
}

bool in_cone(double ax, double ay, uint32_t facing, double cone_deg, double px, double py) {
	return Cone(ax, ay, facing, cone_deg).contains(px, py);
}

int64_t glow_bucket(const Observer &o, const VisionDefs &d, double px, double py) {
	if (!Cone(o.x, o.y, o.facing, d.cone_deg).contains(px, py)) {
		return -1;
	}
	const double vx = px - o.x, vy = py - o.y;
	const double turns = static_cast<double>(o.facing & 0xFFFFu) / 65536.0;
	const int64_t n = bucket_total(d);
	int64_t k = 0;
	for (int64_t b = 1; b < n; b++) {
		const double deg = -d.cone_deg * 0.5 + static_cast<double>(b) * d.bucket_deg;
		const Unit ray = unit_turns(turns + deg / 360.0);
		if (ray.x * vy - ray.y * vx >= 0.0) {
			k = b; // clockwise of this boundary (screen space, +y down)
		}
	}
	return k;
}

Expected evaluate(const Observer &o, const VisionDefs &d, const std::map<Pos, TileLight> &light, const Blocks &opaque,
		const std::vector<Entity> &entities) {
	Expected out;
	out.glow.assign(static_cast<size_t>(bucket_total(d)), {false, 0});
	if (o.blinded) {
		out.blinded = true;
		return out;
	}
	Eval ev{o, d, light, {}, tile_at_point(o.x, o.y)};
	const int64_t r2 = d.range * d.range;
	for (const Pos &t : symmetric_fov(ev.here, d.range, opaque)) {
		const int64_t dx = t.x - ev.here.x, dy = t.y - ev.here.y;
		if (dx * dx + dy * dy <= r2) {
			ev.los.insert(t);
		}
	}
	const Cone cone(o.x, o.y, o.facing, d.cone_deg);
	const Unit f = unit_facing(o.facing);
	const double cx0 = o.x + f.x * d.squint_lead, cy0 = o.y + f.y * d.squint_lead;
	const double hw = d.view_w * 0.5 + d.detail_widen, hh = d.view_h * 0.5 + d.detail_widen;
	std::vector<std::array<int64_t, 8>> counts(out.glow.size(), std::array<int64_t, 8>{});
	for (const Pos &t : ev.los) {
		int64_t lit = 0;
		const State s = ev.state(cone, t, lit);
		if (s == SEEN) {
			const double cx = static_cast<double>(t.x) + 0.5, cy = static_cast<double>(t.y) + 0.5;
			auto it = light.find(t);
			const uint8_t colour = it == light.end() ? 0 : it->second.colour;
			if (cx >= cx0 - hw && cx <= cx0 + hw && cy >= cy0 - hh && cy <= cy0 + hh) {
				out.detail[t] = TileLight{lit, colour};
			} else {
				const int64_t b = glow_bucket(o, d, cx, cy);
				if (b >= 0) {
					out.glow[static_cast<size_t>(b)].first = true;
					counts[static_cast<size_t>(b)][colour & 7]++;
				}
			}
		} else if (s == DARK && ev.band(cone, t) > 0) {
			out.margin.insert(t);
		}
	}
	for (size_t b = 0; b < out.glow.size(); b++) {
		if (!out.glow[b].first) {
			continue;
		}
		int64_t best = -1;
		for (size_t c = 0; c < 8; c++) {
			if (counts[b][c] > best) {
				best = counts[b][c];
				out.glow[b].second = static_cast<uint8_t>(c);
			}
		}
	}
	const Cone wide(o.x, o.y, o.facing, std::min(360.0, d.cone_deg + 2.0 * o.turn_band));
	for (const Entity &e : entities) {
		if (e.id == o.self || e.size == SIZE_NONE) {
			continue;
		}
		State why = UNKNOWN;
		const int64_t lit = ev.entity_light(cone, e, why);
		if (why == SEEN) {
			if (e.size == SIZE_SMALL) {
				const int64_t small = e.identity_min >= 0 ? e.identity_min : d.small_min;
				if (lit >= small) {
					out.entities[e.id] = {LEVEL_IDENTITY, 0};
				}
				continue;
			}
			const int64_t identity = e.identity_min >= 0 ? e.identity_min : d.identity_min;
			out.entities[e.id] = lit >= identity ? std::pair<uint8_t, uint8_t>{LEVEL_IDENTITY, 0}
												 : std::pair<uint8_t, uint8_t>{LEVEL_TOKEN, e.token_class};
			continue;
		}
		// Unseen: VIS-04's margin band, or NET-12's turn band.
		const bool large = e.size == SIZE_MINER || e.size == SIZE_LARGE || e.size == SIZE_LARGE_MOTIONLESS;
		if ((e.size == SIZE_MINER || e.size == SIZE_LARGE) && ev.band(cone, tile_at_point(e.x, e.y)) == 2) {
			out.entities[e.id] = {LEVEL_MARGIN, e.token_class};
			continue;
		}
		if (o.turn_band > 0.0 && large) {
			State wide_why = UNKNOWN;
			if (ev.entity_light(wide, e, wide_why) >= d.seen_min && wide_why == SEEN) {
				out.entities[e.id] = {LEVEL_MARGIN, e.token_class};
			}
		}
	}
	return out;
}

} // namespace lb::audit

#include "core/creatures/creature_nav.h"

#include <algorithm>
#include <cmath>
#include <queue>
#include <set>
#include <tuple>
#include <unordered_map>

namespace lb::core::creatures {

using world::TileMaterial;

namespace {

constexpr int64_t DX[8] = {1, -1, 0, 0, 1, 1, -1, -1};
constexpr int64_t DY[8] = {0, 0, 1, -1, 1, -1, 1, -1};

uint64_t key(Coord t) {
	return (static_cast<uint64_t>(static_cast<uint32_t>(t.x)) << 32) | static_cast<uint32_t>(t.y);
}

// Distance from a point to a tile's square.
double square_distance(double x, double y, Coord t) {
	const double cx = std::clamp(x, static_cast<double>(t.x), static_cast<double>(t.x + 1));
	const double cy = std::clamp(y, static_cast<double>(t.y), static_cast<double>(t.y + 1));
	return std::sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy));
}

// Open set entry: f, then tile order, so equal costs always expand in (y, x) order.
struct Open {
	int64_t f;
	int64_t g;
	Coord t;
	bool operator>(const Open &o) const {
		if (f != o.f) {
			return f > o.f;
		}
		return o.t < t;
	}
};

} // namespace

bool CreatureNav::loaded(Coord t) const {
	auto tile = mine_.tile_at(t);
	return tile.has_value();
}

int64_t CreatureNav::light_milli(Coord t) const {
	return light_ != nullptr ? light_->value(t) : 0;
}

bool CreatureNav::wall_adjacent(Coord t) const {
	for (int i = 0; i < 8; i++) {
		if (mine_.is_solid({t.x + DX[i], t.y + DY[i]})) {
			return true;
		}
	}
	return false;
}

bool CreatureNav::near_brick(Coord t, int64_t clearance) const {
	for (int64_t dy = -clearance; dy <= clearance; dy++) {
		for (int64_t dx = -clearance; dx <= clearance; dx++) {
			if (mine_.effective_material({t.x + dx, t.y + dy}) == TileMaterial::BRICK) {
				return true;
			}
		}
	}
	return false;
}

bool CreatureNav::passable(NavMode mode, Coord t, const NavParams &p) const {
	if (!loaded(t)) {
		return false;
	}
	const TileMaterial m = mine_.effective_material(t);
	switch (mode) {
		case NavMode::WALKER:
		case NavMode::CRAWLER:
			// A closed air door holds the Moth (the follower's 3 s); a shut gate never opens.
			return m == TileMaterial::FLOOR || m == TileMaterial::WOODEN_DOOR;
		case NavMode::DARK:
			return m == TileMaterial::FLOOR && light_milli(t) < p.dark_threshold_milli;
		case NavMode::ROCK:
			if (mine_.materials.get(m).tapper_moves) {
				return true;
			}
			return m == TileMaterial::FLOOR && p.rock_crosses_floor && !near_brick(t, p.brick_clearance);
	}
	return false;
}

int64_t CreatureNav::step_multiple(NavMode mode, Coord t, const NavParams &p) const {
	if (mode == NavMode::CRAWLER && !wall_adjacent(t)) {
		return std::max<int64_t>(p.crawl_open_cost, 1);
	}
	return 1;
}

NavPath CreatureNav::path(NavMode mode, Coord from, Coord to, const NavParams &p) const {
	return search(mode, from, {to}, p);
}

NavPath CreatureNav::path_to_any(NavMode mode, Coord from, const std::vector<Coord> &goals, const NavParams &p) const {
	return search(mode, from, goals, p);
}

NavPath CreatureNav::search(NavMode mode, Coord from, const std::vector<Coord> &goals, const NavParams &p) const {
	NavPath out;
	if (goals.empty()) {
		return out;
	}
	const int64_t orth = mine_.orthogonal_cost_milli, diag = mine_.diagonal_cost_milli;
	std::set<Coord> goal_set(goals.begin(), goals.end());
	// Octile distance to the nearest goal (admissible: every step costs at least its length).
	const bool use_h = goals.size() <= 64;
	auto h = [&](Coord t) -> int64_t {
		if (!use_h) {
			return 0;
		}
		int64_t best = INT64_MAX;
		for (const Coord &g : goals) {
			const int64_t ax = std::llabs(g.x - t.x), ay = std::llabs(g.y - t.y);
			const int64_t d = orth * std::max(ax, ay) + (diag - orth) * std::min(ax, ay);
			best = std::min(best, d);
		}
		return best;
	};
	std::unordered_map<uint64_t, int64_t> g_of;
	std::unordered_map<uint64_t, Coord> parent;
	std::priority_queue<Open, std::vector<Open>, std::greater<Open>> open;
	g_of[key(from)] = 0;
	open.push({h(from), 0, from});
	std::set<Coord> closed;
	while (!open.empty()) {
		const Open cur = open.top();
		open.pop();
		if (closed.count(cur.t) != 0 || cur.g != g_of[key(cur.t)]) {
			continue;
		}
		closed.insert(cur.t);
		if (goal_set.count(cur.t) != 0) {
			out.found = true;
			out.cost_milli = cur.g;
			Coord t = cur.t;
			out.tiles.push_back(t);
			while (t != from) {
				t = parent[key(t)];
				out.tiles.push_back(t);
			}
			std::reverse(out.tiles.begin(), out.tiles.end());
			return out;
		}
		if (p.max_expansions >= 0 && static_cast<int64_t>(out.expansions) >= p.max_expansions) {
			out.hit_limit = true;
			return out;
		}
		out.expansions++;
		for (int i = 0; i < 8; i++) {
			const Coord n{cur.t.x + DX[i], cur.t.y + DY[i]};
			if (!passable(mode, n, p)) {
				if (!loaded(n)) {
					out.touched_unloaded = true;
				}
				continue;
			}
			const bool diagonal = i >= 4;
			if (diagonal && (!passable(mode, {cur.t.x + DX[i], cur.t.y}, p) || !passable(mode, {cur.t.x, cur.t.y + DY[i]}, p))) {
				continue; // no corner cutting
			}
			const int64_t g = cur.g + (diagonal ? diag : orth) * step_multiple(mode, n, p);
			if (p.max_cost_milli >= 0 && g > p.max_cost_milli) {
				out.hit_limit = true;
				continue;
			}
			auto it = g_of.find(key(n));
			if (it != g_of.end() && it->second <= g) {
				continue;
			}
			g_of[key(n)] = g;
			parent[key(n)] = cur.t;
			open.push({g + h(n), g, n});
		}
	}
	return out;
}

bool CreatureNav::still_valid(NavMode mode, const std::vector<Coord> &tiles, const NavParams &p) const {
	for (const Coord &t : tiles) {
		if (!passable(mode, t, p)) {
			return false;
		}
	}
	return true;
}

std::optional<Coord> CreatureNav::nearest_dark_tile(double x, double y, int64_t threshold_milli, int64_t max_radius) const {
	const Coord c{static_cast<int64_t>(std::floor(x)), static_cast<int64_t>(std::floor(y))};
	NavParams p;
	p.dark_threshold_milli = threshold_milli;
	std::optional<Coord> best;
	double best_d = 1e30;
	for (int64_t ty = c.y - max_radius; ty <= c.y + max_radius; ty++) {
		for (int64_t tx = c.x - max_radius; tx <= c.x + max_radius; tx++) {
			const Coord t{tx, ty};
			if (!passable(NavMode::DARK, t, p)) {
				continue;
			}
			const double d = (tx + 0.5 - x) * (tx + 0.5 - x) + (ty + 0.5 - y) * (ty + 0.5 - y);
			if (d < best_d) { // scanning in (y, x) order keeps the first of equals
				best_d = d;
				best = t;
			}
		}
	}
	return best;
}

std::optional<Coord> CreatureNav::reachable_dark_tile_nearest(Coord target, Coord from, const NavParams &p) const {
	// A flood from `from` through dark floor (its own tile counts even if lit), bounded by cost.
	std::unordered_map<uint64_t, int64_t> g_of;
	std::priority_queue<Open, std::vector<Open>, std::greater<Open>> open;
	g_of[key(from)] = 0;
	open.push({0, 0, from});
	std::set<Coord> reached;
	size_t expansions = 0;
	while (!open.empty()) {
		const Open cur = open.top();
		open.pop();
		if (reached.count(cur.t) != 0) {
			continue;
		}
		reached.insert(cur.t);
		if (p.max_expansions >= 0 && static_cast<int64_t>(++expansions) > p.max_expansions) {
			break;
		}
		for (int i = 0; i < 8; i++) {
			const Coord n{cur.t.x + DX[i], cur.t.y + DY[i]};
			if (!passable(NavMode::DARK, n, p)) {
				continue;
			}
			const bool diagonal = i >= 4;
			if (diagonal && (!passable(NavMode::DARK, {cur.t.x + DX[i], cur.t.y}, p) || !passable(NavMode::DARK, {cur.t.x, cur.t.y + DY[i]}, p))) {
				continue;
			}
			const int64_t g = cur.g + (diagonal ? mine_.diagonal_cost_milli : mine_.orthogonal_cost_milli);
			if (p.max_cost_milli >= 0 && g > p.max_cost_milli) {
				continue;
			}
			auto it = g_of.find(key(n));
			if (it != g_of.end() && it->second <= g) {
				continue;
			}
			g_of[key(n)] = g;
			open.push({g, g, n});
		}
	}
	std::optional<Coord> best;
	int64_t best_d = INT64_MAX;
	for (const Coord &t : reached) { // std::set iterates in (y, x) order
		if (!passable(NavMode::DARK, t, p)) {
			continue;
		}
		const int64_t d = (t.x - target.x) * (t.x - target.x) + (t.y - target.y) * (t.y - target.y);
		if (d < best_d) {
			best_d = d;
			best = t;
		}
	}
	return best;
}

std::vector<Coord> CreatureNav::light_edge_ring(Coord seed, int64_t threshold_milli, int64_t max_tiles) const {
	auto lit_floor = [&](Coord t) {
		return loaded(t) && mine_.effective_material(t) == TileMaterial::FLOOR && light_milli(t) >= threshold_milli;
	};
	std::set<Coord> ring;
	if (!lit_floor(seed)) {
		return {};
	}
	std::set<Coord> lit{seed};
	std::vector<Coord> stack{seed};
	while (!stack.empty() && static_cast<int64_t>(lit.size()) < max_tiles) {
		const Coord t = stack.back();
		stack.pop_back();
		for (int i = 0; i < 8; i++) {
			const Coord n{t.x + DX[i], t.y + DY[i]};
			if (lit.count(n) != 0) {
				continue;
			}
			if (lit_floor(n)) {
				lit.insert(n);
				stack.push_back(n);
			} else if (loaded(n) && mine_.effective_material(n) == TileMaterial::FLOOR) {
				ring.insert(n);
			}
		}
	}
	return std::vector<Coord>(ring.begin(), ring.end());
}

std::vector<Coord> CreatureNav::usable_faces_within(double x, double y, double r) const {
	std::vector<Coord> out;
	const int64_t x0 = static_cast<int64_t>(std::floor(x - r)) - 1, x1 = static_cast<int64_t>(std::floor(x + r)) + 1;
	const int64_t y0 = static_cast<int64_t>(std::floor(y - r)) - 1, y1 = static_cast<int64_t>(std::floor(y + r)) + 1;
	for (int64_t ty = y0; ty <= y1; ty++) {
		for (int64_t tx = x0; tx <= x1; tx++) {
			const Coord t{tx, ty};
			if (mine_.tapper_face_usable(t) && square_distance(x, y, t) <= r + 1e-9) {
				out.push_back(t);
			}
		}
	}
	return out;
}

std::optional<Coord> CreatureNav::nearest_usable_face(double x, double y, int64_t max_radius) const {
	std::optional<Coord> best;
	double best_d = 1e30;
	for (const Coord &t : usable_faces_within(x, y, static_cast<double>(max_radius))) {
		const double d = square_distance(x, y, t);
		if (d < best_d) {
			best_d = d;
			best = t;
		}
	}
	return best;
}

std::optional<Coord> CreatureNav::rock_tile_behind(Coord tile) const {
	if (mine_.tapper_face_usable(tile)) {
		return tile;
	}
	const Coord order[4] = {{tile.x, tile.y - 1}, {tile.x - 1, tile.y}, {tile.x + 1, tile.y}, {tile.x, tile.y + 1}};
	for (const Coord &n : order) {
		if (mine_.tapper_face_usable(n)) {
			return n;
		}
	}
	return std::nullopt;
}

NavPath CreatureNav::moth_path_within(Coord from, double mx, double my, double max_tiles, int64_t max_expansions) const {
	NavParams p;
	p.max_cost_milli = static_cast<int64_t>(std::llround(max_tiles * 1000.0));
	p.max_expansions = max_expansions;
	return search(NavMode::WALKER, from, {{static_cast<int64_t>(std::floor(mx)), static_cast<int64_t>(std::floor(my))}}, p);
}

NavPath CreatureNav::tapper_rock_path_within(Coord from, double mx, double my, double max_tiles, double reach, const NavParams &base) const {
	NavParams p = base;
	p.max_cost_milli = static_cast<int64_t>(std::llround(max_tiles * 1000.0));
	return search(NavMode::ROCK, from, usable_faces_within(mx, my, reach), p);
}

NavPath CreatureNav::stythe_dark_path_within(Coord from, double mx, double my, double max_tiles, double within, const NavParams &base) const {
	NavParams p = base;
	p.max_cost_milli = static_cast<int64_t>(std::llround(max_tiles * 1000.0));
	std::vector<Coord> goals;
	const int64_t r = static_cast<int64_t>(std::ceil(within)) + 1;
	const Coord c{static_cast<int64_t>(std::floor(mx)), static_cast<int64_t>(std::floor(my))};
	for (int64_t ty = c.y - r; ty <= c.y + r; ty++) {
		for (int64_t tx = c.x - r; tx <= c.x + r; tx++) {
			const double d = std::sqrt((tx + 0.5 - mx) * (tx + 0.5 - mx) + (ty + 0.5 - my) * (ty + 0.5 - my));
			if (d <= within + 1e-9 && passable(NavMode::DARK, {tx, ty}, p)) {
				goals.push_back({tx, ty});
			}
		}
	}
	return search(NavMode::DARK, from, goals, p);
}

} // namespace lb::core::creatures

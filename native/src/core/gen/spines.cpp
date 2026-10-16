#include "core/gen/spines.h"

#include "core/gen/biomes.h"
#include "core/generated/hash_domains.h"
#include "core/rng/rng.h"

#include <algorithm>
#include <functional>
#include <map>
#include <queue>

namespace lb::core::gen {

using lb::core::world::CELL_TILES;
using lb::core::world::Coord;
using lb::core::world::SHAFT_CENTRE_X2;
using lb::core::world::SHAFT_CENTRE_Y2;

namespace {

// gen.plan's key for a spine's tie-breaks (GEN-08's needs use the low numbers).
constexpr int64_t NEED_SPINE = 100;
// The most cells a spine may take before it counts as lost.
constexpr size_t MAX_SPINE_CELLS = 600;
// How far round the straight box between its ends a detour may go.
constexpr int64_t DETOUR_MARGIN = 12;

int64_t sign(int64_t v) {
	return v > 0 ? 1 : (v < 0 ? -1 : 0);
}

int64_t abs64(int64_t v) {
	return v < 0 ? -v : v;
}

// The shortest 4-neighbour way from `from` to `to` that `barred` allows, in a box round them; the
// cells after `from`, or empty if there is none. Neighbours are tried north, east, south, west.
std::vector<Coord> detour(Coord from, Coord to, const std::function<bool(Coord)> &barred) {
	const int64_t x0 = std::min(from.x, to.x) - DETOUR_MARGIN;
	const int64_t x1 = std::max(from.x, to.x) + DETOUR_MARGIN;
	const int64_t y0 = std::min(from.y, to.y) - DETOUR_MARGIN;
	const int64_t y1 = std::max(from.y, to.y) + DETOUR_MARGIN;
	std::map<Coord, Coord> parent;
	std::queue<Coord> open;
	open.push(from);
	parent[from] = from;
	const Coord steps[4] = {{0, -1}, {1, 0}, {0, 1}, {-1, 0}};
	while (!open.empty()) {
		const Coord c = open.front();
		open.pop();
		if (c == to) {
			std::vector<Coord> path;
			for (Coord at = to; at != from; at = parent[at]) {
				path.push_back(at);
			}
			std::reverse(path.begin(), path.end());
			return path;
		}
		for (const Coord &d : steps) {
			const Coord n{c.x + d.x, c.y + d.y};
			if (n.x < x0 || n.x > x1 || n.y < y0 || n.y > y1 || parent.count(n) != 0 || barred(n)) {
				continue;
			}
			parent[n] = c;
			open.push(n);
		}
	}
	return {};
}

// A walk with every loop cut out: where it comes back to a cell, the steps since that cell go.
std::vector<Coord> without_loops(const std::vector<Coord> &walk) {
	std::vector<Coord> out;
	std::map<Coord, size_t> at;
	for (const Coord &c : walk) {
		const auto seen = at.find(c);
		if (seen != at.end()) {
			for (size_t i = seen->second + 1; i < out.size(); i++) {
				at.erase(out[i]);
			}
			out.resize(seen->second + 1);
			continue;
		}
		at[c] = out.size();
		out.push_back(c);
	}
	return out;
}

Edge side_towards(Coord a, Coord b) {
	if (b.x > a.x) {
		return Edge::EAST;
	}
	if (b.x < a.x) {
		return Edge::WEST;
	}
	return b.y > a.y ? Edge::SOUTH : Edge::NORTH;
}

} // namespace

Edge spine_gate(const std::vector<Edge> &gates, int64_t dx2, int64_t dy2, uint64_t tie) {
	std::vector<Edge> best;
	int64_t best_score = 0;
	for (Edge g : gates) {
		int64_t score = 0;
		switch (g) {
			case Edge::NORTH:
				score = -dy2;
				break;
			case Edge::EAST:
				score = dx2;
				break;
			case Edge::SOUTH:
				score = dy2;
				break;
			default:
				score = -dx2;
				break;
		}
		if (best.empty() || score > best_score) {
			best = {g};
			best_score = score;
		} else if (score == best_score) {
			best.push_back(g);
		}
	}
	if (best.empty()) {
		return Edge::NORTH;
	}
	return best[static_cast<size_t>(tie % best.size())];
}

std::pair<int64_t, int64_t> door_point2(const PlannedSite &site) {
	const int64_t x = 2 * CELL_TILES * site.door.x;
	const int64_t y = 2 * CELL_TILES * site.door.y;
	int64_t px = x + CELL_TILES;
	int64_t py = y + CELL_TILES;
	switch (site.door_side) {
		case Edge::NORTH:
			py = y;
			break;
		case Edge::SOUTH:
			py = y + 2 * CELL_TILES;
			break;
		case Edge::WEST:
			px = x;
			break;
		default:
			px = x + 2 * CELL_TILES;
			break;
	}
	return {px - SHAFT_CENTRE_X2, py - SHAFT_CENTRE_Y2};
}

std::optional<Spine> route_spine(uint64_t seed, int32_t site_index, const PlannedSite &site, const std::vector<Edge> &gates,
		const std::set<Coord> &blocked, const std::vector<int64_t> &ring_bounds, int32_t replan) {
	const int64_t keys[2] = {NEED_SPINE, site_index};
	Rng tie(sub_seed(seed, hash_domain::GEN_PLAN, keys, 2, replan));
	const auto [dx2, dy2] = door_point2(site);
	Spine spine;
	spine.site = site_index;
	spine.replan = replan;
	spine.gate = spine_gate(gates, dx2, dy2, tie.next_u64());
	auto barred = [&](Coord c) {
		return (c.x == 0 && c.y == 0) || blocked.count(c) != 0 || ring_of_cell(c, ring_bounds) >= DEEP_RING;
	};
	const Coord start = neighbour({0, 0}, spine.gate);
	const Coord goal = site.approach();
	if (barred(start) || barred(goal)) {
		return std::nullopt;
	}
	Coord at = start;
	spine.cells.push_back(at);
	while (at != goal) {
		const int64_t dx = goal.x - at.x;
		const int64_t dy = goal.y - at.y;
		const Coord sx{at.x + sign(dx), at.y};
		const Coord sy{at.x, at.y + sign(dy)};
		std::vector<Coord> order;
		if (abs64(dx) > abs64(dy)) {
			order = {sx};
			if (dy != 0) {
				order.push_back(sy);
			}
		} else if (abs64(dy) > abs64(dx)) {
			order = {sy};
			if (dx != 0) {
				order.push_back(sx);
			}
		} else {
			order = tie.chance_ppm(500000) ? std::vector<Coord>{sx, sy} : std::vector<Coord>{sy, sx};
		}
		bool stepped = false;
		for (const Coord &next : order) {
			if (!barred(next)) {
				at = next;
				spine.cells.push_back(at);
				stepped = true;
				break;
			}
		}
		if (!stepped) {
			const std::vector<Coord> way = detour(at, goal, barred);
			if (way.empty()) {
				return std::nullopt;
			}
			spine.cells.insert(spine.cells.end(), way.begin(), way.end());
			at = goal;
		}
		if (spine.cells.size() > MAX_SPINE_CELLS) {
			return std::nullopt;
		}
	}
	// A detour can come back over the spine's own cells: each cell once.
	spine.cells = without_loops(spine.cells);
	return spine;
}

std::vector<EdgeKey> spine_edges(const Spine &spine, const PlannedSite &site) {
	std::vector<EdgeKey> out;
	out.push_back(edge_of({0, 0}, spine.gate));
	for (size_t i = 1; i < spine.cells.size(); i++) {
		out.push_back(edge_of(spine.cells[i - 1], side_towards(spine.cells[i - 1], spine.cells[i])));
	}
	out.push_back(edge_of(site.door, site.door_side));
	return out;
}

SpineSockets::SpineSockets(uint64_t seed, const RunPlan &plan, const CellClassifier &cells, SocketParams params)
	: seed_(seed), classifier_(cells), params_(std::move(params)) {
	params_.open_ppm = 1000000;
	for (const Spine &s : plan.spines) {
		if (s.site < 0 || static_cast<size_t>(s.site) >= plan.sites.size()) {
			continue;
		}
		for (const EdgeKey &e : spine_edges(s, plan.sites[static_cast<size_t>(s.site)])) {
			edges_.insert(e);
		}
		cells_.insert(s.cells.begin(), s.cells.end());
	}
}

std::optional<Socket> SpineSockets::query(const EdgeKey &edge) const {
	if (edges_.count(edge) == 0) {
		return std::nullopt;
	}
	const Coord a{edge.x, edge.y};
	const Coord b = edge.axis == Axis::EAST ? Coord{edge.x + 1, edge.y} : Coord{edge.x, edge.y + 1};
	const std::vector<int32_t> widths = shared_widths(classifier_.classify(a).widths, classifier_.classify(b).widths, params_);
	Socket s = hashed_socket(seed_, edge, params_, widths);
	s.forced = true;
	return s;
}

} // namespace lb::core::gen

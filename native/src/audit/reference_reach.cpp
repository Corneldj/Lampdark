#include "audit/reference_reach.h"

#include <cmath>
#include <map>
#include <queue>

namespace lb::audit {

double reach_cost(const std::vector<Pos> &origins, Pos to, double max_cost, bool voice, double closed_cost,
		const std::function<uint8_t(Pos)> &kind) {
	using Item = std::pair<double, Pos>;
	auto later = [](const Item &a, const Item &b) { return a.first > b.first || (a.first == b.first && b.second < a.second); };
	std::priority_queue<Item, std::vector<Item>, decltype(later)> open(later);
	std::map<Pos, double> best;
	for (const Pos &o : origins) {
		if (kind(o) == OPEN && best.count(o) == 0) {
			best[o] = 0.0;
			open.push({0.0, o});
		}
	}
	while (!open.empty()) {
		const Item it = open.top();
		open.pop();
		if (it.first > best[it.second]) {
			continue;
		}
		if (it.second == to) {
			return it.first;
		}
		for (int64_t dy = -1; dy <= 1; dy++) {
			for (int64_t dx = -1; dx <= 1; dx++) {
				if (dx == 0 && dy == 0) {
					continue;
				}
				const Pos n{it.second.x + dx, it.second.y + dy};
				const uint8_t k = kind(n);
				double step = 1.0;
				if (k == PORTAL_CLOSED) {
					if (voice) {
						continue;
					}
					step += closed_cost;
				} else if (k != OPEN) {
					continue;
				}
				const double c = it.first + step;
				if (c > max_cost + 1e-9) {
					continue;
				}
				auto b = best.find(n);
				if (b == best.end() || c < b->second) {
					best[n] = c;
					open.push({c, n});
				}
			}
		}
	}
	return -1.0;
}

Line straight_line(Pos from, Pos to, const std::function<bool(Pos)> &solid, const std::function<bool(Pos)> &brick,
		const std::function<bool(Pos)> &door) {
	Line out;
	const int64_t dx = to.x - from.x, dy = to.y - from.y;
	out.distance = std::sqrt(static_cast<double>(dx * dx + dy * dy));
	auto touch = [&](Pos t) {
		if (t == from || t == to) {
			return;
		}
		out.solid += solid(t) ? 1 : 0;
		out.brick = out.brick || brick(t);
		out.door = out.door || door(t);
	};
	// Walk the segment from centre to centre in exact integers: at each step the next boundary it
	// meets is a vertical one, a horizontal one, or a corner (where it touches both neighbours).
	const int64_t ax = dx < 0 ? -dx : dx, ay = dy < 0 ? -dy : dy;
	const int64_t sx = dx < 0 ? -1 : 1, sy = dy < 0 ? -1 : 1;
	Pos p = from;
	int64_t cx = 0, cy = 0; // vertical and horizontal boundaries crossed
	while (cx < ax || cy < ay) {
		// The x boundary is at parameter (2cx + 1) / (2ax), the y one at (2cy + 1) / (2ay).
		const int64_t lhs = (2 * cx + 1) * ay, rhs = (2 * cy + 1) * ax;
		if (lhs == rhs) {
			touch({p.x + sx, p.y});
			touch({p.x, p.y + sy});
			p = {p.x + sx, p.y + sy};
			cx++;
			cy++;
		} else if (lhs < rhs) {
			p = {p.x + sx, p.y};
			cx++;
		} else {
			p = {p.x, p.y + sy};
			cy++;
		}
		touch(p);
	}
	return out;
}

} // namespace lb::audit

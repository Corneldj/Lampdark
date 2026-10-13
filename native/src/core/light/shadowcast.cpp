#include "core/light/shadowcast.h"

#include <set>
#include <vector>

namespace lb::core::light {

namespace {

// A slope n / d with d > 0.
struct Slope {
	int64_t n;
	int64_t d;
};

int64_t floor_div(int64_t a, int64_t b) {
	const int64_t q = a / b;
	return (a % b != 0 && ((a < 0) != (b < 0))) ? q - 1 : q;
}

// round_ties_up(depth * s) = floor(depth * s + 1/2)
int64_t round_ties_up(int64_t depth, Slope s) {
	return floor_div(2 * depth * s.n + s.d, 2 * s.d);
}

// round_ties_down(depth * s) = ceil(depth * s - 1/2) = -floor(-(depth * s) + 1/2)
int64_t round_ties_down(int64_t depth, Slope s) {
	return -floor_div(-2 * depth * s.n + s.d, 2 * s.d);
}

// col >= depth * s  <=>  col * d >= depth * n
bool at_or_after(int64_t col, int64_t depth, Slope s) {
	return col * s.d >= depth * s.n;
}

bool at_or_before(int64_t col, int64_t depth, Slope s) {
	return col * s.d <= depth * s.n;
}

struct Row {
	int64_t depth;
	Slope start;
	Slope end;
};

} // namespace

void shadowcast(Coord origin, int64_t depth_limit, const std::function<bool(Coord)> &blocks,
		const std::function<void(Coord)> &visit) {
	std::set<Coord> seen;
	auto reveal = [&](Coord c) {
		if (seen.insert(c).second) {
			visit(c);
		}
	};
	reveal(origin);
	for (int quadrant = 0; quadrant < 4; quadrant++) {
		auto transform = [&](int64_t row, int64_t col) -> Coord {
			switch (quadrant) {
				case 0: return {origin.x + col, origin.y - row}; // north
				case 1: return {origin.x + col, origin.y + row}; // south
				case 2: return {origin.x + row, origin.y + col}; // east
				default: return {origin.x - row, origin.y + col}; // west
			}
		};
		std::vector<Row> stack;
		stack.push_back({1, {-1, 1}, {1, 1}});
		while (!stack.empty()) {
			Row row = stack.back();
			stack.pop_back();
			if (row.depth > depth_limit) {
				continue;
			}
			const int64_t min_col = round_ties_up(row.depth, row.start);
			const int64_t max_col = round_ties_down(row.depth, row.end);
			bool have_prev = false;
			bool prev_wall = false;
			for (int64_t col = min_col; col <= max_col; col++) {
				const Coord tile = transform(row.depth, col);
				const bool wall = blocks(tile);
				const bool symmetric = at_or_after(col, row.depth, row.start) && at_or_before(col, row.depth, row.end);
				if (wall || symmetric) {
					reveal(tile);
				}
				if (have_prev && prev_wall && !wall) {
					row.start = {2 * col - 1, 2 * row.depth};
				}
				if (have_prev && !prev_wall && wall) {
					Row next{row.depth + 1, row.start, {2 * col - 1, 2 * row.depth}};
					stack.push_back(next);
				}
				have_prev = true;
				prev_wall = wall;
			}
			if (have_prev && !prev_wall) {
				stack.push_back({row.depth + 1, row.start, row.end});
			}
		}
	}
}

} // namespace lb::core::light

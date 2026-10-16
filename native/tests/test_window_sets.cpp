// GEN-11: the window sets: which cells a run needs, which it may drop, and what it never drops.

#include "core/gen/gen_pool.h"

#include <doctest.h>

using namespace lb::core::gen;
using lb::core::world::Coord;

TEST_CASE("GEN-11 every cell within 4 of a holder is required (Chebyshev)") {
	const std::set<Coord> one = required_cells({{0, 0}}, 4);
	CHECK(one.size() == 81);
	CHECK(one.count({4, -4}) == 1);
	CHECK(one.count({5, 0}) == 0);
	const std::set<Coord> two = required_cells({{0, 0}, {3, 0}}, 4);
	CHECK(two.size() == 9 * 12); // the windows overlap
	CHECK(nearest_holder({7, 2}, {{0, 0}, {3, 0}}) == 4);
	CHECK(nearest_holder({7, 2}, {}) == INT64_MAX);
}

TEST_CASE("GEN-11 cells beyond 6 of every holder go; 5 and 6 stay; pinned cells never go") {
	const std::vector<Coord> holders{{0, 0}};
	const std::vector<Coord> loaded{{4, 0}, {5, 0}, {6, 0}, {7, 0}, {9, 9}, {0, 0}, {-7, 3}};
	const std::set<Coord> pinned{{-7, 3}};
	const std::vector<Coord> out = evictions(loaded, holders, pinned, WindowParams{});
	CHECK(out == std::vector<Coord>{{9, 9}, {7, 0}}); // the farthest first; (-7, 3) is pinned
	// Every holder gone: everything but the pinned cells goes.
	CHECK(evictions(loaded, {}, pinned, WindowParams{}).size() == loaded.size() - 1);
}

TEST_CASE("GEN-11 over the live-cell cap the farthest spare cells go too") {
	WindowParams p;
	p.max_live = 85;
	std::vector<Coord> loaded;
	for (int64_t y = -6; y <= 6; y++) {
		for (int64_t x = -6; x <= 6; x++) {
			loaded.push_back({x, y}); // 169 cells within 6
		}
	}
	const std::vector<Coord> out = evictions(loaded, {{0, 0}}, {}, p);
	CHECK(loaded.size() - out.size() <= 85);
	for (const Coord &c : out) {
		CHECK(chebyshev(c, {0, 0}) > p.generate); // never a required cell
	}
	CHECK(chebyshev(out.front(), {0, 0}) == 6); // the farthest first
	p.max_live = 10; // the required window alone is over the cap: it stays
	CHECK(loaded.size() - evictions(loaded, {{0, 0}}, {}, p).size() == 81);
}

TEST_CASE("GEN-11 the window reports what entered and left its sets, and nothing when no holder moved") {
	Window w(4, 5);
	Window::Change first = w.update({{0, 0}});
	CHECK(first.moved);
	CHECK(first.entered.size() == 81);
	CHECK(first.arrived.size() == 121); // the prefetch ring rides on the required set
	CHECK(first.left.empty());
	CHECK(first.departed.empty());
	// The same cells, in another order and repeated: nothing to do.
	CHECK_FALSE(w.update({{0, 0}, {0, 0}}).moved);
	// One cell east: a column in, a column out, in each set.
	Window::Change east = w.update({{1, 0}});
	CHECK(east.moved);
	CHECK(east.entered.size() == 9);
	CHECK(east.left.size() == 9);
	CHECK(east.arrived.size() == 11);
	CHECK(east.departed.size() == 11);
	for (const Coord &c : east.entered) {
		CHECK(c.x == 5);
	}
	for (const Coord &c : east.left) {
		CHECK(c.x == -4);
	}
	// A second holder: its window joins; overlapping cells enter nothing twice.
	Window::Change two = w.update({{1, 0}, {3, 0}});
	CHECK(two.entered.size() == 2 * 9);
	CHECK(two.left.empty());
	// Everyone gone: everything leaves.
	Window::Change none = w.update({});
	CHECK(none.left.size() == 9 * 11);
	CHECK(none.departed.size() == 11 * 13);
	CHECK(w.holders().empty());
	CHECK(w.prefetch_cells().empty());
}

TEST_CASE("GEN-11 the prefetch ring is never smaller than the required set") {
	Window w(4, 2);
	CHECK(w.prefetch_radius() == 4);
	CHECK(w.update({{0, 0}}).arrived.size() == 81);
}

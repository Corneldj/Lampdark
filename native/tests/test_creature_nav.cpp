// CRT-02: creature navigation. Modes, doors and gates, the crawl, the dark walker's threshold,
// the rock mover and brick, reach, bounded guard queries, unloaded ground and tie-breaking.
#include "doctest.h"

#include "core/creatures/creature_nav.h"
#include "vision_fixture.h"

#include <string>
#include <vector>

using namespace vision_fixture;
using lb::core::creatures::CreatureNav;
using lb::core::creatures::NavMode;
using lb::core::creatures::NavParams;
using lb::core::creatures::NavPath;

namespace {

std::vector<std::string> blank(char fill = '#') {
	return std::vector<std::string>(20, std::string(20, fill));
}

void carve(std::vector<std::string> &rows, int x0, int y0, int x1, int y1, char ch = '.') {
	for (int y = y0; y <= y1; y++) {
		for (int x = x0; x <= x1; x++) {
			rows[y][x] = ch;
		}
	}
}

} // namespace

TEST_CASE("each mode reaches reachable goals and reports none for unreachable ones") {
	auto rows = blank();
	carve(rows, 1, 1, 18, 3);  // a road
	carve(rows, 1, 10, 5, 12); // a sealed room
	World w(0, rows);
	w.settle();
	CreatureNav nav(w.mine, w.light.get());
	NavParams p;
	for (NavMode m : {NavMode::WALKER, NavMode::CRAWLER, NavMode::DARK}) {
		NavPath ok = nav.path(m, {1, 2}, {18, 2}, p);
		CHECK(ok.found);
		CHECK(ok.tiles.front() == Coord{1, 2});
		CHECK(ok.tiles.back() == Coord{18, 2});
		CHECK_FALSE(nav.path(m, {1, 2}, {3, 11}, p).found);
	}
	NavPath rock = nav.path(NavMode::ROCK, {5, 6}, {15, 7}, p);
	CHECK(rock.found);
	CHECK(nav.path(NavMode::ROCK, {5, 6}, {2, 11}, p).found); // the room's floor lies beneath reach
}

TEST_CASE("the Moth passes a closed air door, never a shut gate") {
	auto rows = blank();
	carve(rows, 1, 2, 18, 2);
	rows[2][6] = 'D';
	rows[2][12] = 'S';
	World w(0, rows);
	CreatureNav nav(w.mine, w.light.get());
	NavParams p;
	CHECK(nav.path(NavMode::WALKER, {1, 2}, {10, 2}, p).found);
	CHECK_FALSE(nav.path(NavMode::WALKER, {1, 2}, {15, 2}, p).found);
	CHECK_FALSE(nav.path(NavMode::DARK, {1, 2}, {10, 2}, p).found); // the Stythe opens neither
	rows[2][12] = 's';
	World open_gate(0, rows);
	CreatureNav nav2(open_gate.mine, open_gate.light.get());
	CHECK(nav2.path(NavMode::WALKER, {1, 2}, {15, 2}, p).found);
}

TEST_CASE("prowling hugs the ribs; hunting takes the shortest path") {
	auto rows = blank();
	carve(rows, 1, 1, 18, 18); // a big chamber
	World w(0, rows);
	CreatureNav nav(w.mine, w.light.get());
	NavParams p;
	NavPath crawl = nav.path(NavMode::CRAWLER, {1, 1}, {18, 18}, p);
	REQUIRE(crawl.found);
	size_t edge = 0;
	for (const Coord &t : crawl.tiles) {
		edge += nav.wall_adjacent(t) ? 1 : 0;
	}
	CHECK(static_cast<double>(edge) / crawl.tiles.size() >= 0.8);
	NavPath hunt = nav.path(NavMode::WALKER, {1, 1}, {18, 18}, p);
	CHECK(hunt.cost_milli == 17 * 1414); // the diagonal: shortest
}

TEST_CASE("the dark walker treats light at its threshold as a wall") {
	auto rows = blank();
	carve(rows, 1, 2, 18, 2);
	World w(0, rows);
	w.spot({9, 2}, 0.40);
	w.settle();
	CreatureNav nav(w.mine, w.light.get());
	NavParams p;
	p.dark_threshold_milli = 300;
	CHECK_FALSE(nav.path(NavMode::DARK, {1, 2}, {18, 2}, p).found);
	p.dark_threshold_milli = 500; // the Thin
	CHECK(nav.path(NavMode::DARK, {1, 2}, {18, 2}, p).found);
	p.dark_threshold_milli = 300;
	auto nearest = nav.reachable_dark_tile_nearest({18, 2}, {1, 2}, p);
	REQUIRE(nearest.has_value());
	CHECK(*nearest == Coord{8, 2}); // the reachable dark tile nearest the target
	CHECK(nav.nearest_dark_tile(9.5, 2.5, 300, 4) == std::optional<Coord>(Coord{8, 2}));
	auto ring = nav.light_edge_ring({9, 2}, 300, 100);
	CHECK(ring == std::vector<Coord>{{8, 2}, {10, 2}});
}

TEST_CASE("the rock mover never enters brick, nor floor within 2 tiles of it") {
	auto rows = blank();
	carve(rows, 0, 9, 19, 11);     // a road across the cell
	carve(rows, 14, 0, 19, 19, 'B'); // a brick-lined zone east
	carve(rows, 15, 9, 19, 11);    // its arch floor
	World w(0, rows);
	CreatureNav nav(w.mine, w.light.get());
	NavParams p;
	NavPath across = nav.path(NavMode::ROCK, {5, 5}, {5, 15}, p);
	REQUIRE(across.found); // beneath the road
	for (const Coord &t : across.tiles) {
		CHECK(w.mine.effective_material(t) != lb::core::world::TileMaterial::BRICK);
	}
	CHECK_FALSE(nav.path(NavMode::ROCK, {5, 5}, {17, 10}, p).found); // the arch floor is beyond it
	CHECK_FALSE(nav.passable(NavMode::ROCK, {12, 10}, p));           // floor 2 from brick
	CHECK(nav.passable(NavMode::ROCK, {11, 10}, p));
	p.rock_crosses_floor = false;
	CHECK_FALSE(nav.path(NavMode::ROCK, {5, 5}, {5, 15}, p).found);
}

TEST_CASE("reach: 1.5 tiles from a usable face, never brick, timber or a door") {
	auto rows = blank();
	carve(rows, 1, 1, 18, 3);   // a 3-wide road, rows 1-3
	carve(rows, 1, 7, 18, 11);  // a 5-wide chamber, rows 7-11
	carve(rows, 1, 14, 18, 16); // a 3-wide road walled in brick and timber
	carve(rows, 0, 13, 19, 13, 'B');
	carve(rows, 0, 17, 19, 17, 'T');
	World w(0, rows);
	CreatureNav nav(w.mine, w.light.get());
	CHECK_FALSE(nav.usable_faces_within(9.5, 2.5, 1.5).empty()); // middle of the 3-wide road
	CHECK(nav.usable_faces_within(9.5, 9.5, 1.5).empty());       // middle of the 5-wide chamber
	CHECK_FALSE(nav.usable_faces_within(9.5, 8.5, 1.5).empty()); // off its centre line
	CHECK(nav.usable_faces_within(9.5, 15.5, 1.5).empty());      // brick and timber faces
	CHECK(nav.rock_tile_behind({9, 1}) == std::optional<Coord>(Coord{9, 0}));
}

TEST_CASE("guard queries hold up to their limit and stop past it") {
	auto rows = blank();
	carve(rows, 0, 5, 19, 5);
	World w(1, rows); // neighbours open floor: a long straight run east along row 5
	CreatureNav nav(w.mine, w.light.get());
	for (int len : {29, 30, 31}) {
		NavPath r = nav.moth_path_within({0, 5}, len + 0.5, 5.5, 30.0, 2000);
		CHECK(r.found == (len <= 30));
		if (len > 30) {
			CHECK(r.hit_limit);
		}
	}
	NavParams p;
	for (int len : {20, 21, 22}) {
		CHECK(nav.stythe_dark_path_within({0, 5}, len + 0.5, 5.5, 21.0, 0.0, p).found == (len <= 21));
	}
	NavParams capped;
	capped.max_expansions = 5;
	CHECK(nav.stythe_dark_path_within({0, 5}, 15.5, 5.5, 21.0, 0.0, capped).hit_limit);
}

TEST_CASE("unloaded ground is solid and flagged") {
	auto rows = blank();
	carve(rows, 0, 5, 19, 5);
	World w(0, rows);
	CreatureNav nav(w.mine, w.light.get());
	NavPath r = nav.path(NavMode::WALKER, {5, 5}, {25, 5}, NavParams{});
	CHECK_FALSE(r.found);
	CHECK(r.touched_unloaded);
}

TEST_CASE("ties break by tile order") {
	auto rows = blank();
	carve(rows, 1, 1, 9, 9);
	World w(0, rows);
	CreatureNav nav(w.mine, w.light.get());
	NavPath a = nav.path(NavMode::WALKER, {1, 1}, {5, 1}, NavParams{});
	NavPath b = nav.path(NavMode::WALKER, {1, 1}, {5, 1}, NavParams{});
	CHECK(a.tiles == b.tiles);
	CHECK(a.tiles == std::vector<Coord>{{1, 1}, {2, 1}, {3, 1}, {4, 1}, {5, 1}});
}

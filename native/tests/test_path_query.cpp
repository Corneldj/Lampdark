#include "mine_fixture.h"

#include <doctest.h>

#include <chrono>

using namespace mine_fixture;

TEST_CASE("path distance matches hand-computed fixtures") {
	MineMap mine;
	mine.commit(cell_from({0, 0}, {
		"#########",
		"#.......#",
		"#.......#",
		"#..###..#",
		"#.......#",
		"#########",
	}));
	CHECK(mine.path_distance({1, 1}, {7, 1}, 100000).distance_milli == 6000);  // straight
	CHECK(mine.path_distance({1, 1}, {3, 3}, 100000).distance_milli == -1);    // inside rock
	// (1,1) diagonal to (2,2), then 4 straight steps round the block: 1.414 + 4. The block
	// forbids the shorter diagonals past its corners.
	CHECK(mine.path_distance({1, 1}, {4, 4}, 100000).distance_milli == 5414);
	CHECK(mine.path_distance({2, 2}, {2, 4}, 100000).distance_milli == 2000);
	CHECK(mine.path_distance({1, 1}, {1, 1}, 100000).distance_milli == 0);
}

TEST_CASE("no corner cutting past solid tiles") {
	MineMap mine;
	mine.commit(cell_from({0, 0}, {"####", "#.##", "##.#", "####"}));
	CHECK(mine.path_distance({1, 1}, {2, 2}, 100000).distance_milli == -1);
}

TEST_CASE("shut barriers block unless doors are open; the flag lets the path through") {
	MineMap mine;
	auto cell = cell_from({0, 0}, {"#######", "#..D..#", "#######"});
	Barrier door;
	door.id = 7;
	door.tiles = {static_cast<uint16_t>(Cell::index_of(3, 1))};
	cell->barriers.push_back(door);
	mine.commit(std::move(cell));
	CHECK(mine.path_distance({1, 1}, {5, 1}, 100000).distance_milli == -1);
	CHECK(mine.path_distance({1, 1}, {5, 1}, 100000, true).distance_milli == 4000);
	mine.set_barrier({0, 0}, 7, true);
	CHECK(mine.path_distance({1, 1}, {5, 1}, 100000).distance_milli == 4000);
}

TEST_CASE("unloaded cells are never entered and are flagged") {
	MineMap mine;
	std::vector<std::string> rows(CELL_TILES, std::string(CELL_TILES, '#'));
	rows[5] = std::string(CELL_TILES, '.');
	mine.commit(cell_from({0, 0}, rows));
	const PathResult blocked = mine.path_distance({0, 5}, {25, 5}, 100000);
	CHECK(blocked.distance_milli == -1);
	CHECK(blocked.touched_unloaded);
	mine.commit(cell_from({1, 0}, rows));
	const PathResult through = mine.path_distance({0, 5}, {25, 5}, 100000);
	CHECK(through.distance_milli == 25000);
}

TEST_CASE("queries stop at their maximum") {
	MineMap mine;
	std::vector<std::string> rows(CELL_TILES, std::string(CELL_TILES, '#'));
	rows[5] = std::string(CELL_TILES, '.');
	mine.commit(cell_from({0, 0}, rows));
	const PathResult capped = mine.path_distance({0, 5}, {19, 5}, 10000);
	CHECK(capped.distance_milli == -1);
	CHECK(capped.hit_max);
	CHECK(mine.flood_count({0, 5}, 10000) == 11); // tiles 0..10
}

TEST_CASE("nearest open tile: straight-line nearest, exclusions, lowest index on ties") {
	MineMap mine;
	mine.commit(cell_from({0, 0}, {"#####", "#...#", "#####"}));
	CHECK(*mine.nearest_open_tile(2.5, 0.5, {}, 5) == Coord{2, 1});
	CHECK(*mine.nearest_open_tile(2.5, 0.5, {{2, 1}}, 5) == Coord{1, 1}); // tie of 1 and 3: lowest x
	CHECK_FALSE(mine.nearest_open_tile(15.0, 15.0, {}, 2).has_value());
}

TEST_CASE("a 70-tile flood through a road network fits its budget") {
	MineMap mine;
	std::vector<std::string> grid(CELL_TILES, std::string(CELL_TILES, '#'));
	for (int i = 0; i < CELL_TILES; i++) {
		for (int r : {2, 3, 4, 12, 13, 14}) {
			grid[r][i] = '.';
			grid[i][r] = '.';
		}
	}
	for (int64_t cy = -3; cy <= 3; cy++) {
		for (int64_t cx = -3; cx <= 3; cx++) {
			mine.commit(cell_from({cx, cy}, grid));
		}
	}
	const auto start = std::chrono::steady_clock::now();
	size_t reached = 0;
	for (int i = 0; i < 20; i++) {
		reached = mine.flood_count({3, 3}, 70000);
	}
	const double ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - start).count() / 20.0;
	MESSAGE("70-tile flood: " << reached << " tiles in " << ms << " ms");
	CHECK(reached > 1000);
#ifndef LB_DEBUG_TOOLS
	CHECK(ms < 1.0); // GEN-01 proposes 0.2 ms for a typical road flood; this grid is denser
#endif
}

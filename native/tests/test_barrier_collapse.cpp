#include "mine_fixture.h"

#include <doctest.h>

#include <chrono>

using namespace mine_fixture;

TEST_CASE("a barrier flip changes tiles at once and queues one change") {
	MineMap mine;
	auto cell = cell_from({1, 0}, {"#####", "#.S.#", "#.S.#", "#####"});
	Barrier gate;
	gate.id = 3;
	gate.portal = 11;
	gate.tiles = {static_cast<uint16_t>(Cell::index_of(2, 1)), static_cast<uint16_t>(Cell::index_of(2, 2))};
	cell->barriers.push_back(gate);
	mine.commit(std::move(cell));
	CHECK_FALSE(mine.is_walkable({22, 1}));
	CHECK(mine.set_barrier({1, 0}, 3, true));
	CHECK(mine.is_walkable({22, 1}));
	CHECK(mine.is_walkable({22, 2}));
	const std::vector<TileChange> changes = mine.take_changes();
	REQUIRE(changes.size() == 1);
	CHECK(changes[0].reason == "barrier_open");
	CHECK(changes[0].x0 == 22);
	CHECK(changes[0].y0 == 1);
	CHECK(changes[0].y1 == 2);
	CHECK(mine.take_changes().empty());
	CHECK_FALSE(mine.set_barrier({1, 0}, 99, true));
}

TEST_CASE("a collapse swap writes the fallen set and back") {
	MineMap mine;
	auto cell = cell_from({0, 0}, {"#####", "#...#", "#####"});
	Collapse fall;
	fall.id = 1;
	fall.standing = {{static_cast<uint16_t>(Cell::index_of(2, 1)), static_cast<uint8_t>(TileMaterial::FLOOR)}};
	fall.fallen = {{static_cast<uint16_t>(Cell::index_of(2, 1)), static_cast<uint8_t>(TileMaterial::ROCK)}};
	cell->collapses.push_back(fall);
	mine.commit(std::move(cell));
	CHECK(mine.is_walkable({2, 1}));
	CHECK(mine.path_distance({1, 1}, {3, 1}, 10000).distance_milli == 2000);
	CHECK(mine.set_collapse({0, 0}, 1, true));
	CHECK_FALSE(mine.is_walkable({2, 1}));
	CHECK(mine.path_distance({1, 1}, {3, 1}, 10000).distance_milli == -1);
	CHECK(mine.take_changes()[0].reason == "collapse_fallen");
}

TEST_CASE("commit and field rebuild timing") {
	MineMap mine;
	std::vector<std::string> grid(CELL_TILES, std::string(CELL_TILES, '#'));
	for (int i = 0; i < CELL_TILES; i++) {
		grid[3][i] = '.';
		grid[i][3] = '.';
	}
	const auto start = std::chrono::steady_clock::now();
	int n = 0;
	for (int64_t cy = 0; cy < 6; cy++) {
		for (int64_t cx = 0; cx < 6; cx++) {
			mine.commit(cell_from({cx, cy}, grid));
			n++;
		}
	}
	const double ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - start).count() / n;
	MESSAGE("commit with neighbour field rebuilds: " << ms << " ms per cell");
	CHECK(mine.loaded_count() == 36);
}

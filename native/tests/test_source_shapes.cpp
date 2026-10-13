#include "light_fixture.h"

#include <doctest.h>

using namespace light_fixture;

namespace {

// Base camp: brick walls, a floor room x 2-9, y 2-9, and a gate at (10, 5) to a road east.
std::vector<std::string> camp(char gate) {
	std::vector<std::string> rows(20, std::string(20, 'B'));
	for (int y = 2; y <= 9; y++) {
		for (int x = 2; x <= 9; x++) {
			rows[y][x] = '.';
		}
	}
	rows[5][10] = gate;
	for (int x = 11; x < 20; x++) {
		rows[4][x] = '#';
		rows[5][x] = '.';
		rows[6][x] = '#';
	}
	return rows;
}

SourceDesc emergency(const MineMap &mine) {
	SourceDesc d;
	d.shape = Shape::AREA;
	d.kind = "emergency";
	d.colour = ColourClass::WHITE;
	d.peak = 0.6;
	for (int64_t y = 0; y < 20; y++) {
		for (int64_t x = 0; x < 10; x++) {
			if (mine.is_walkable({x, y})) {
				d.tiles.push_back({x, y});
			}
		}
	}
	return d;
}

SourceDesc spill() {
	SourceDesc d;
	d.shape = Shape::SPILL;
	d.kind = "gate_spill";
	d.colour = ColourClass::WHITE;
	d.radius = 6.0;
	d.peak = 0.6;
	d.end_value = 0.12;
	d.tiles = {{10, 5}};
	d.dir = {1, 0};
	return d;
}

} // namespace

TEST_CASE("base camp's floor reads 0.6 throughout with no other light") {
	MineMap mine;
	LightGrid grid(mine);
	mine.commit(mine_fixture::cell_from({0, 0}, camp('S')));
	grid.on_cell_loaded({0, 0});
	grid.add_source(emergency(mine));
	grid.update();
	for (int64_t y = 2; y <= 9; y++) {
		for (int64_t x = 2; x <= 9; x++) {
			CHECK(grid.value({x, y}) == 600);
		}
	}
	CHECK(grid.value({12, 5}) == 0); // the road stays dark
}

TEST_CASE("an open gate spills 0.6 to 0.12 over 6 tiles, 0.30 or more to 3.75; shut, nothing") {
	MineMap mine;
	LightGrid grid(mine);
	auto cell = mine_fixture::cell_from({0, 0}, camp('S'));
	lb::core::world::Barrier gate;
	gate.id = 1;
	gate.tiles = {static_cast<uint16_t>(lb::core::world::Cell::index_of(10, 5))};
	cell->barriers.push_back(gate);
	mine.commit(std::move(cell));
	grid.on_cell_loaded({0, 0});
	grid.add_source(spill());
	grid.update();
	CHECK(grid.value({11, 5}) == 0); // shut
	mine.set_barrier({0, 0}, 1, true);
	for (const lb::core::world::TileChange &c : mine.take_changes()) {
		grid.on_tiles_changed(c.x0, c.y0, c.x1, c.y1);
	}
	grid.update();
	CHECK(grid.value({11, 5}) == 560);  // depth 0.5
	CHECK(grid.value({13, 5}) == 400);  // depth 2.5
	CHECK(grid.value({14, 5}) == 320);  // depth 3.5: still 0.30 or more (to 3.75)
	CHECK(grid.value({15, 5}) == 240);  // depth 4.5: below
	CHECK(grid.value({16, 5}) == 160);  // depth 5.5
	CHECK(grid.value({17, 5}) == 0);    // beyond 6
}

TEST_CASE("a spot adds its value on one tile; egg-glow peaks at 0.2") {
	MineMap mine;
	LightGrid grid(mine);
	load_open(mine, &grid);
	SourceDesc spot;
	spot.shape = Shape::SPOT;
	spot.kind = "spot";
	spot.peak = 0.30;
	spot.spot = {4, 4};
	grid.add_source(spot);
	SourceDesc egg = lamp(10.5, 10.5, 1.5);
	egg.kind = "egg_glow";
	egg.colour = ColourClass::EGG_GLOW;
	egg.peak = 0.2;
	egg.flags = 0;
	grid.add_source(egg);
	grid.update();
	CHECK(grid.value({4, 4}) == 300);
	CHECK(grid.value({4, 5}) == 0);
	CHECK(grid.value({10, 10}) == 200);
	CHECK(grid.value({11, 10}) == 147); // 1 tile off: 0.2 - 0.08 * (1/1.5)
	CHECK(grid.tile_light({10, 10}).colour == ColourClass::EGG_GLOW);
}

TEST_CASE("a tile directly behind a pillar reads 0; a shut door blocks, opened it passes") {
	MineMap mine;
	LightGrid grid(mine);
	std::vector<std::string> rows = open_floor();
	rows[5][7] = '#';
	rows[12][7] = 'D';
	for (int x = 0; x < 20; x++) {
		if (x != 7) {
			rows[12][x] = '#';
		}
	}
	auto cell = mine_fixture::cell_from({0, 0}, rows);
	lb::core::world::Barrier door;
	door.id = 2;
	door.tiles = {static_cast<uint16_t>(lb::core::world::Cell::index_of(7, 12))};
	cell->barriers.push_back(door);
	mine.commit(std::move(cell));
	grid.on_cell_loaded({0, 0});
	grid.add_source(lamp(5.5, 5.5, 5.5));
	grid.add_source(lamp(7.5, 10.5, 4.0));
	grid.update();
	CHECK(grid.value({7, 5}) > 0); // the pillar's lit face
	CHECK(grid.value({8, 5}) == 0);
	CHECK(grid.value({9, 5}) == 0);
	CHECK(grid.value({7, 13}) == 0); // behind the shut door
	mine.set_barrier({0, 0}, 2, true);
	for (const lb::core::world::TileChange &c : mine.take_changes()) {
		grid.on_tiles_changed(c.x0, c.y0, c.x1, c.y1);
	}
	grid.update();
	CHECK(grid.value({7, 13}) > 0);
}

TEST_CASE("unloaded cells receive nothing; a source in an unloaded cell casts nothing") {
	MineMap mine;
	LightGrid grid(mine);
	mine.commit(mine_fixture::cell_from({0, 0}, open_floor()));
	grid.on_cell_loaded({0, 0});
	grid.add_source(lamp(18.5, 5.5, 5.5));
	grid.add_source(lamp(25.5, 5.5, 5.5));
	grid.update();
	CHECK(grid.value({19, 5}) > 0);
	CHECK(grid.value({21, 5}) == 0);
	CHECK(grid.value({16, 5}) < 1000);
	mine.commit(mine_fixture::cell_from({1, 0}, open_floor()));
	grid.on_cell_loaded({1, 0});
	grid.update();
	CHECK(grid.value({21, 5}) > 0);
	CHECK(grid.value({25, 5}) == 1000); // the second lamp now casts too
}

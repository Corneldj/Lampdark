#include "light_fixture.h"

#include <doctest.h>

using namespace light_fixture;

TEST_CASE("two wick-down lamps 2 tiles either side of a tile sum to 0.42") {
	MineMap mine;
	LightGrid grid(mine);
	load_open(mine, &grid);
	grid.add_source(lamp(3.5, 5.5, 2.5));
	grid.add_source(lamp(7.5, 5.5, 2.5));
	grid.update();
	CHECK(grid.value({5, 5}) == 420);
}

TEST_CASE("overlaps cap at 1.0") {
	MineMap mine;
	LightGrid grid(mine);
	load_open(mine, &grid);
	for (int i = 0; i < 5; i++) {
		grid.add_source(lamp(5.5, 5.5, 4.0));
	}
	grid.update();
	CHECK(grid.value({5, 5}) == 1000);
	CHECK(grid.value({6, 5}) == 1000);
}

TEST_CASE("value_from sums only the matching owners") {
	MineMap mine;
	LightGrid grid(mine);
	load_open(mine, &grid);
	grid.add_source(lamp(3.5, 5.5, 2.5, 11));
	grid.add_source(lamp(7.5, 5.5, 2.5, 12));
	grid.update();
	CHECK(grid.value_from({5, 5}, {11}) == 210);
	CHECK(grid.value_from({5, 5}, {12}) == 210);
	CHECK(grid.value_from({5, 5}, {11, 12}) == 420);
	CHECK(grid.value_from({5, 5}, {99}) == 0);
}

TEST_CASE("each tile records its brightest source and colour") {
	MineMap mine;
	LightGrid grid(mine);
	load_open(mine, &grid);
	const uint32_t a = grid.add_source(lamp(3.5, 5.5, 4.0));
	SourceDesc flare = lamp(9.5, 5.5, 14.0);
	flare.kind = "flare";
	flare.colour = ColourClass::PALE_AMBER;
	const uint32_t f = grid.add_source(flare);
	grid.update();
	CHECK(grid.tile_light({3, 5}).brightest == a);
	CHECK(grid.tile_light({3, 5}).colour == ColourClass::AMBER);
	CHECK(grid.tile_light({9, 5}).brightest == f);
	CHECK(grid.tile_light({9, 5}).colour == ColourClass::PALE_AMBER);
}

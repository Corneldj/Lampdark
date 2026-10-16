#include "mine_fixture.h"

#include <doctest.h>

using namespace mine_fixture;

namespace {

constexpr uint32_t REACH = 1500; // CRT-09's 1.5-tile reach, in thousandths

int count_beyond(const MineMap &mine, Coord cell) {
	int beyond = 0;
	for (int64_t y = 0; y < CELL_TILES; y++) {
		for (int64_t x = 0; x < CELL_TILES; x++) {
			const Coord t{cell.x * CELL_TILES + x, cell.y * CELL_TILES + y};
			if (mine.is_walkable(t) && mine.strike_milli(t) > REACH) {
				beyond++;
			}
		}
	}
	return beyond;
}

std::vector<std::string> road(int width) {
	std::vector<std::string> rows(CELL_TILES, std::string(CELL_TILES, '#'));
	for (int y = 8; y < 8 + width; y++) {
		rows[y] = std::string(CELL_TILES, '.');
	}
	return rows;
}

} // namespace

TEST_CASE("every tile of 1-, 2- and 3-wide rock roads is within 1.5 tiles") {
	for (int width : {1, 2, 3}) {
		MineMap mine;
		// Neighbours carry the road on, so its ends are not dead ends.
		mine.commit(cell_from({-1, 0}, road(width)));
		mine.commit(cell_from({0, 0}, road(width)));
		mine.commit(cell_from({1, 0}, road(width)));
		CHECK(count_beyond(mine, {0, 0}) == 0);
		CHECK(mine.strike_milli({5, 8}) == 500u); // the road's edge row
		if (width == 3) {
			CHECK(mine.strike_milli({5, 9}) == 1500u); // the middle of a 3-wide road: exactly in reach
		}
	}
}

TEST_CASE("a 5x5 rock chamber has exactly one tile beyond reach, an 8x8 a 4x4 block") {
	MineMap five;
	five.commit(cell_from({0, 0}, room(5)));
	CHECK(count_beyond(five, {0, 0}) == 1);
	CHECK(five.strike_milli({9, 9}) == 2500); // the centre
	MineMap eight;
	eight.commit(cell_from({0, 0}, room(8)));
	CHECK(count_beyond(eight, {0, 0}) == 16);
	for (int64_t y = 8; y <= 11; y++) {
		for (int64_t x = 8; x <= 11; x++) {
			CHECK(eight.strike_milli({x, y}) > REACH);
		}
	}
}

TEST_CASE("brick and timber faces count for nothing") {
	for (char wall : {'B', 'T'}) {
		MineMap mine;
		mine.commit(cell_from({0, 0}, room(3, wall)));
		CHECK(count_beyond(mine, {0, 0}) == 9); // no usable face anywhere near
		CHECK(mine.strike_milli({9, 9}) == MineMap::FIELD_FAR);
	}
}

TEST_CASE("the strike field reaches across cell borders") {
	MineMap mine;
	std::vector<std::string> left(CELL_TILES, std::string(CELL_TILES, 'B'));
	left[10][19] = '.'; // a floor tile on the east edge, brick all round inside its cell
	mine.commit(cell_from({0, 0}, left));
	CHECK(mine.strike_milli({19, 10}) == MineMap::FIELD_FAR);
	mine.commit(cell_from({1, 0}, std::vector<std::string>(CELL_TILES, std::string(CELL_TILES, '#'))));
	CHECK(mine.strike_milli({19, 10}) == 500); // the rock face in the next cell
	mine.unload({1, 0});
	CHECK(mine.strike_milli({19, 10}) == MineMap::FIELD_FAR);
}

TEST_CASE("GEN-11 the fields follow a door worked after they were last read") {
	// Rock all round but a room on rows 10-12 and a door at (10, 5), five rows above it.
	std::vector<std::string> rows = room(0);
	for (int y = 10; y <= 12; y++) {
		rows[y] = "#####..........#####";
	}
	rows[5][10] = 'D';
	auto cell = cell_from({0, 0}, rows);
	Barrier door;
	door.id = 1;
	door.tiles = {static_cast<uint16_t>(Cell::index_of(10, 5))};
	cell->barriers.push_back(door);
	MineMap mine;
	mine.commit(std::move(cell));
	CHECK(mine.depth_milli({10, 4}) == MineMap::FIELD_FAR); // the shut door is solid; the room is out of reach
	REQUIRE(mine.set_barrier({0, 0}, 1, true));
	CHECK(mine.depth_milli({10, 4}) == 500u); // the open door is open floor beside it
	REQUIRE(mine.set_barrier({0, 0}, 1, false));
	CHECK(mine.depth_milli({10, 4}) == MineMap::FIELD_FAR);
}

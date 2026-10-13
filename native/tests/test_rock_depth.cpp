#include "mine_fixture.h"

#include <doctest.h>

using namespace mine_fixture;

TEST_CASE("a 4-thick pillar is rich-rock eligible and a 2-thick wall is thin") {
	std::vector<std::string> rows(CELL_TILES, std::string(CELL_TILES, '.'));
	for (int y = 4; y < 8; y++) {
		rows[y].replace(4, 4, "####"); // 4x4 pillar
	}
	for (int y = 12; y < 18; y++) {
		rows[y].replace(4, 2, "##"); // 2-thick wall
	}
	MineMap mine;
	// Floor all round, so the pillar's neighbours do not merge with unloaded rock.
	for (int64_t cy = -1; cy <= 1; cy++) {
		for (int64_t cx = -1; cx <= 1; cx++) {
			mine.commit(cell_from({cx, cy}, cx == 0 && cy == 0 ? rows : std::vector<std::string>(CELL_TILES, std::string(CELL_TILES, '.'))));
		}
	}
	CHECK(mine.thickness({5, 5}) == 4);
	CHECK(mine.thickness({4, 4}) == 4);
	CHECK(mine.thickness({4, 14}) == 2);
	CHECK(mine.thickness({9, 9}) == 0); // floor
	CHECK(mine.depth_milli({5, 5}) == 1500);
	CHECK(mine.depth_milli({4, 4}) == 500);
	CHECK(mine.depth_milli({4, 14}) == 500);
	CHECK(mine.depth_milli({9, 9}) == MineMap::FIELD_FAR); // floor has no depth
}

TEST_CASE("thickness is capped and counts rock and coal only") {
	MineMap mine;
	std::vector<std::string> rows(CELL_TILES, std::string(CELL_TILES, '#'));
	rows[0] = std::string(CELL_TILES, 'B');
	mine.commit(cell_from({0, 0}, rows));
	CHECK(mine.thickness({0, 0}) == 0);                  // brick
	CHECK(mine.thickness({10, 10}) == MineMap::THICKNESS_CAP);
}

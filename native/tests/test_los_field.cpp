// VIS-03: the line-of-sight field (pillars, doorways, range, cache invalidation).
#include "doctest.h"

#include "vision_fixture.h"

using namespace vision_fixture;

TEST_CASE("a pillar casts a shadow; a doorway lets sight through") {
	std::vector<std::string> rows(20, std::string(20, '.'));
	rows[10][12] = '#'; // pillar east of (10, 10)
	for (int y = 0; y < 20; y++) {
		if (y != 13) {
			rows[y][16] = '#'; // a wall at x = 16 with a doorway at y = 13
		}
	}
	World w(1, rows);
	LosField f;
	f.cast({10, 10}, 40, [&](Coord t) { return w.mine.is_opaque(t); });
	CHECK(f.visible({12, 10}));         // the pillar's face is seen
	CHECK_FALSE(f.visible({14, 10}));   // its shadow
	CHECK(f.visible({11, 10}));
	CHECK(f.visible({16, 13}));         // the doorway
	CHECK(f.visible({17, 14}));         // and through it
	CHECK_FALSE(f.visible({18, 3}));    // behind the wall
	CHECK(f.visible({10, 10}));         // the origin
}

TEST_CASE("nothing beyond the range by centre distance") {
	World w(2);
	LosField f;
	f.cast({0, 0}, 40, [&](Coord t) { return w.mine.is_opaque(t); });
	CHECK(f.visible({40, 0}));
	CHECK_FALSE(f.visible({41, 0}));
	CHECK(f.visible({28, 28}));          // 39.6
	CHECK_FALSE(f.visible({29, 29}));    // 41.0
}

TEST_CASE("the field is cached until the miner changes tile or the window changes") {
	World w(2);
	Vision &v = *w.vision;
	v.set_observer(1, 0, 0.5, 0.5, EAST);
	v.compute(1, {});
	CHECK(v.recasts() == 1);
	v.set_observer(1, 0, 0.9, 0.2, EAST); // same tile
	v.compute(1, {});
	CHECK(v.recasts() == 1);
	v.set_observer(1, 0, 1.2, 0.2, EAST); // next tile
	v.compute(1, {});
	CHECK(v.recasts() == 2);
	v.on_tiles_changed(90, 90, 95, 95); // outside the window
	v.compute(1, {});
	CHECK(v.recasts() == 2);
	v.on_tiles_changed(10, 0, 10, 0); // inside
	v.compute(1, {});
	CHECK(v.recasts() == 3);
}

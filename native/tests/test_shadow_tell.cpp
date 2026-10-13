// VIS-09: the shadow tell. A body lit to 0.30 casts a shadow away from the brightest light on it,
// as long as that light's radius, stopping at walls, on lit tiles only, 3 next to the body falling
// to 1; 1 tile wide for every caster, the Moth's like a miner's; never the Stythe's.
#include "light_fixture.h"

#include "core/vision/shadow_tell.h"

#include <doctest.h>

using namespace light_fixture;
using namespace lb::core::vision;
using lb::core::sim::MirrorEntity;

namespace {

constexpr uint16_t MINER = 1, MOTH = 3, STYTHE = 5, ITEM = 9;

PerceptionTable table() {
	PerceptionTable t;
	PerceptionClass miner;
	miner.size = SizeClass::MINER;
	t.set(MINER, miner);
	PerceptionClass large;
	large.size = SizeClass::LARGE;
	t.set(MOTH, large);
	t.set(STYTHE, miner);
	PerceptionClass small;
	small.size = SizeClass::SMALL;
	t.set(ITEM, small);
	return t;
}

// Open floor everywhere, with a dim even light so tiles past a lamp's edge stay lit, and an
// optional wall column at x = `wall_x` in cell (0, 0).
void world(MineMap &mine, LightGrid &grid, int wall_x = -1) {
	for (int64_t cy = -1; cy <= 1; cy++) {
		for (int64_t cx = -1; cx <= 1; cx++) {
			std::vector<std::string> rows = open_floor();
			if (cx == 0 && cy == 0 && wall_x >= 0) {
				for (std::string &r : rows) {
					r[static_cast<size_t>(wall_x)] = '#';
				}
			}
			mine.commit(mine_fixture::cell_from({cx, cy}, rows));
			grid.on_cell_loaded({cx, cy});
		}
	}
	SourceDesc dim;
	dim.shape = Shape::AREA;
	dim.kind = "emergency";
	dim.colour = ColourClass::WHITE;
	dim.peak = 0.2;
	for (int64_t y = 0; y < 20; y++) {
		for (int64_t x = 0; x < 20; x++) {
			if (x != wall_x) {
				dim.tiles.push_back({x, y});
			}
		}
	}
	grid.add_source(dim);
}

MirrorEntity body(uint32_t id, uint16_t kind, double x, double y) {
	MirrorEntity e;
	e.id = id;
	e.kind = kind;
	e.x = x;
	e.y = y;
	return e;
}

} // namespace

TEST_CASE("a lit body shades 4 tiles straight away from a radius-4 lamp, 3 falling to 1") {
	MineMap mine;
	LightGrid grid(mine);
	world(mine, grid);
	grid.add_source(lamp(3.5, 5.5, 4.0));
	grid.update();
	ShadowParams p;
	const auto s = compute_shadows(mine, grid, table(), {body(1, MINER, 5.5, 5.5)}, p);
	CHECK(grid.value({5, 5}) >= 300);
	CHECK(s.size() == 4);
	CHECK(s.at({6, 5}) == 3);
	CHECK(s.at({7, 5}) == 2);
	CHECK(s.at({8, 5}) == 1);
	CHECK(s.at({9, 5}) == 1);
	CHECK(s.count({4, 5}) == 0);  // never toward the lamp
	CHECK(s.count({5, 5}) == 0);  // nor under the body
}

TEST_CASE("lit to the threshold casts; just under it does not") {
	MineMap mine;
	LightGrid grid(mine);
	world(mine, grid);
	grid.add_source(lamp(3.5, 5.5, 4.0));
	grid.update();
	ShadowParams p;
	p.min_light = grid.value({5, 5});
	CHECK(!compute_shadows(mine, grid, table(), {body(1, MINER, 5.5, 5.5)}, p).empty());
	p.min_light = grid.value({5, 5}) + 1;
	CHECK(compute_shadows(mine, grid, table(), {body(1, MINER, 5.5, 5.5)}, p).empty());
}

TEST_CASE("with two lights the shadow points away from the brighter") {
	MineMap mine;
	LightGrid grid(mine);
	world(mine, grid);
	grid.add_source(lamp(7.5, 5.5, 2.5));   // dim, to the east
	grid.add_source(lamp(4.5, 5.5, 5.5));   // bright, close to the west
	grid.update();
	ShadowParams p;
	const auto s = compute_shadows(mine, grid, table(), {body(1, MINER, 5.5, 5.5)}, p);
	CHECK(s.count({6, 5}) == 1);
	CHECK(s.count({4, 5}) == 0);
}

TEST_CASE("the shadow stops at a wall and shades only lit tiles") {
	MineMap mine;
	LightGrid grid(mine);
	world(mine, grid, 8);
	grid.add_source(lamp(3.5, 5.5, 4.0));
	grid.update();
	ShadowParams p;
	const auto s = compute_shadows(mine, grid, table(), {body(1, MINER, 5.5, 5.5)}, p);
	CHECK(s.count({6, 5}) == 1);
	CHECK(s.count({7, 5}) == 1);
	CHECK(s.count({8, 5}) == 0);  // the wall
	CHECK(s.count({9, 5}) == 0);  // past it
	MineMap dark_mine;
	LightGrid dark(dark_mine);
	load_open(dark_mine, &dark);  // no dim light: past the lamp's edge is dark
	dark.add_source(lamp(3.5, 5.5, 4.0));
	dark.update();
	const auto d = compute_shadows(dark_mine, dark, table(), {body(1, MINER, 5.5, 5.5)}, p);
	for (const auto &kv : d) {
		CHECK(dark.value(kv.first) >= p.lit_min);
	}
	CHECK(d.size() < 4);
}

TEST_CASE("the Stythe never casts; small things never; a miner and the Moth cast alike") {
	MineMap mine;
	LightGrid grid(mine);
	world(mine, grid);
	grid.add_source(lamp(3.5, 5.5, 4.0));
	grid.update();
	ShadowParams p;
	p.never_cast = {STYTHE};
	CHECK(compute_shadows(mine, grid, table(), {body(1, STYTHE, 5.5, 5.5)}, p).empty());
	CHECK(compute_shadows(mine, grid, table(), {body(1, ITEM, 5.5, 5.5)}, p).empty());
	const auto miner = compute_shadows(mine, grid, table(), {body(1, MINER, 5.5, 5.5)}, p);
	const auto moth = compute_shadows(mine, grid, table(), {body(7, MOTH, 5.5, 5.5)}, p);
	CHECK(miner == moth);
	p.enabled = false;
	CHECK(compute_shadows(mine, grid, table(), {body(1, MINER, 5.5, 5.5)}, p).empty());
}

TEST_CASE("overlapping shadows keep the deepest level") {
	MineMap mine;
	LightGrid grid(mine);
	world(mine, grid);
	grid.add_source(lamp(3.5, 5.5, 4.0));
	grid.update();
	ShadowParams p;
	const auto s = compute_shadows(mine, grid, table(), {body(1, MINER, 5.5, 5.5), body(2, MINER, 6.5, 5.5)}, p);
	CHECK(s.at({7, 5}) == 3);  // next to the second body, deeper than the first's 2
}

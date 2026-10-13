// VIS-03: the seen rule, touch range, the blind area, thresholds, overrides and reasons.
#include "doctest.h"

#include "vision_fixture.h"

#include <cmath>
#include <set>

using namespace vision_fixture;

namespace {

std::set<Coord> frame_tiles(const PerceptionFrame &f) {
	std::set<Coord> out;
	for (const FrameTile &t : f.tiles) {
		out.insert(t.tile);
	}
	return out;
}

} // namespace

TEST_CASE("a tile is seen exactly when in sight, within 55 degrees and lit to 0.12") {
	std::vector<std::string> rows(20, std::string(20, '.'));
	rows[8][12] = '#';
	rows[13][9] = '#';
	rows[10][14] = 'B';
	World w(1, rows);
	// A checkerboard of light levels around the threshold.
	for (int64_t y = 0; y < 20; y++) {
		for (int64_t x = 0; x < 20; x++) {
			const double value = ((x * 7 + y * 3) % 4 == 0) ? 0.11 : ((x + y) % 3 == 0 ? 0.12 : 0.5);
			w.spot({x, y}, value);
		}
	}
	w.settle();
	Vision &v = *w.vision;
	v.params.view_w = 200.0; // all detail for this test
	v.params.view_h = 200.0;
	const double ox = 10.3, oy = 10.6;
	const uint32_t facing = 9000; // about 49 degrees
	v.set_observer(1, 0, ox, oy, facing);
	const std::set<Coord> seen = frame_tiles(v.compute(1, {}));
	LosField los;
	los.cast({10, 10}, 40, [&](Coord t) { return w.mine.is_opaque(t); });
	const double facing_rad = facing / 65536.0 * 6.283185307179586;
	int checked = 0;
	for (int64_t y = 0; y < 20; y++) {
		for (int64_t x = 0; x < 20; x++) {
			const double dx = x + 0.5 - ox, dy = y + 0.5 - oy;
			double off = std::atan2(dy, dx) - facing_rad;
			while (off > 3.141592653589793) off -= 6.283185307179586;
			while (off < -3.141592653589793) off += 6.283185307179586;
			const double deg = std::fabs(off) * 180.0 / 3.141592653589793;
			if (std::fabs(deg - 55.0) < 1e-6) {
				continue; // on the edge: no reference tie-break
			}
			const bool apex = dx * dx + dy * dy <= 0.25;
			const bool in_cone = apex || deg < 55.0;
			const bool lit = w.light->tile_light({x, y}).value >= 120;
			CHECK_MESSAGE(seen.count({x, y}) == (los.visible({x, y}) && in_cone && lit), "tile ", x, ",", y);
			checked++;
		}
	}
	CHECK(checked > 390);
}

TEST_CASE("touch range shows nothing") {
	World w(1);
	w.settle(); // no light anywhere
	Vision &v = *w.vision;
	v.set_observer(1, 1, 5.5, 5.5, EAST);
	const PerceptionFrame f = v.compute(1, {entity(1, MINER, 5.5, 5.5), entity(2, MINER, 6.5, 5.5)});
	CHECK(f.tiles.empty());
	CHECK(f.tokens.empty());
	CHECK(f.identified.empty());
	CHECK(v.unseen_reason(1, entity(2, MINER, 6.5, 5.5)) == Unseen::DARK);
}

TEST_CASE("your own lamp behind you is black to you, seen by a teammate facing it") {
	World w(1);
	w.area({0, 0}, {19, 19}, 1.0);
	w.settle();
	Vision &v = *w.vision;
	v.set_observer(1, 1, 10.5, 10.5, EAST);
	v.set_observer(2, 2, 2.5, 10.5, EAST);
	CHECK_FALSE(v.tile_seen(1, {6, 10})); // behind miner 1, lit to 1.0
	CHECK(v.tile_seen(2, {6, 10}));       // in front of miner 2
	const PerceptionFrame f = v.compute(1, {});
	for (const FrameTile &t : f.tiles) {
		CHECK(Cone::make(10.5, 10.5, EAST, 110.0).contains_tile(t.tile.x, t.tile.y));
	}
}

TEST_CASE("absent at 0.11, a token at 0.29, identified at 0.30") {
	World w(1);
	w.spot({12, 10}, 0.11);
	w.spot({12, 12}, 0.29);
	w.spot({12, 8}, 0.30);
	w.settle();
	Vision &v = *w.vision;
	v.set_observer(1, 1, 10.5, 10.5, EAST);
	const std::vector<MirrorEntity> es = {entity(1, MINER, 10.5, 10.5), entity(2, MINER, 12.5, 10.5),
		entity(3, MINER, 12.5, 12.5), entity(4, STYTHE, 12.5, 8.5)};
	CHECK(v.sees_entity(1, es[1]) == Level::NONE);
	CHECK(v.sees_entity(1, es[2]) == Level::TOKEN);
	CHECK(v.sees_entity(1, es[3]) == Level::IDENTITY);
	const PerceptionFrame f = v.compute(1, es);
	REQUIRE(f.tokens.size() == 1);
	CHECK(f.tokens[0].size == SizeClass::MINER); // a token is a size class and a position only
	CHECK(f.tokens[0].x == 12.5);
	CHECK(f.identified == std::vector<uint32_t>{4});
}

TEST_CASE("blinded empties the frame; a 4-tile clamp sends nothing beyond 4 tiles") {
	World w(1);
	w.area({0, 0}, {19, 19}, 0.8);
	w.settle();
	Vision &v = *w.vision;
	v.set_observer(1, 1, 5.5, 10.5, EAST);
	CHECK(v.compute(1, {}).tiles.size() > 50);
	v.set_blinded(1, true);
	const PerceptionFrame blind = v.compute(1, {entity(2, MINER, 7.5, 10.5)});
	CHECK(blind.blinded);
	CHECK(blind.tiles.empty());
	CHECK(blind.tokens.empty());
	CHECK(blind.identified.empty());
	v.set_blinded(1, false);
	v.set_radius_clamp(1, 4.0);
	const PerceptionFrame clamped = v.compute(1, {entity(2, MINER, 7.5, 10.5), entity(3, MINER, 12.5, 10.5)});
	for (const FrameTile &t : clamped.tiles) {
		const double dx = t.tile.x + 0.5 - 5.5, dy = t.tile.y + 0.5 - 10.5;
		CHECK(dx * dx + dy * dy <= 16.0);
	}
	CHECK(clamped.identified == std::vector<uint32_t>{2});
}

TEST_CASE("unseen reasons: dark, outside the cone, the bite, no line of sight, beyond range") {
	std::vector<std::string> rows(20, std::string(20, '.'));
	rows[10][14] = '#';
	World w(2, rows);
	w.area({-20, -20}, {39, 39}, 0.5);
	w.light->add_source([] {
		SourceDesc d;
		d.shape = Shape::SPOT;
		d.kind = "test_dark";
		d.peak = 0.0;
		d.spot = {12, 12};
		return d;
	}());
	w.settle();
	Vision &v = *w.vision;
	v.set_observer(1, 1, 10.5, 10.5, EAST);
	v.set_bite_tiles(1, {Coord{12, 9}});
	CHECK(v.unseen_reason(1, entity(2, MINER, 12.5, 10.5)) == Unseen::SEEN);
	CHECK(v.unseen_reason(1, entity(3, MINER, 6.5, 10.5)) == Unseen::OUTSIDE_CONE);
	CHECK(v.unseen_reason(1, entity(4, MINER, 12.5, 9.5)) == Unseen::BITE);
	CHECK(v.unseen_reason(1, entity(5, MINER, 16.5, 10.5)) == Unseen::NO_LOS);
	CHECK(v.unseen_reason(1, entity(6, MINER, 55.5, 10.5)) == Unseen::BEYOND_RANGE);
	const PerceptionFrame f = v.compute(1, {entity(4, MINER, 12.5, 9.5)});
	CHECK(f.identified.empty()); // anything on a bitten tile goes with it
	CHECK(frame_tiles(f).count({12, 9}) == 0);
	World dark(1);
	dark.settle();
	dark.vision->set_observer(1, 1, 10.5, 10.5, EAST);
	CHECK(dark.vision->unseen_reason(1, entity(2, MINER, 12.5, 10.5)) == Unseen::DARK);
}

TEST_CASE("decals: blood at 0.12, chalk and line numbers at 0.30") {
	World w(1);
	w.spot({12, 10}, 0.2);
	w.spot({13, 10}, 0.3);
	w.settle();
	Vision &v = *w.vision;
	v.set_decals({12, 10}, DECAL_BLOOD | DECAL_CHALK);
	v.set_decals({13, 10}, DECAL_CHALK | DECAL_LINE_NUMBER);
	v.set_observer(1, 1, 10.5, 10.5, EAST);
	for (const FrameTile &t : v.compute(1, {}).tiles) {
		if (t.tile == Coord{12, 10}) {
			CHECK(t.decals == DECAL_BLOOD);
		}
		if (t.tile == Coord{13, 10}) {
			CHECK(t.decals == (DECAL_CHALK | DECAL_LINE_NUMBER));
		}
	}
}

TEST_CASE("is_seen_by_any and in_cone") {
	World w(1);
	w.area({0, 0}, {19, 19}, 0.5);
	w.settle();
	Vision &v = *w.vision;
	v.set_observer(1, 1, 5.5, 5.5, EAST);
	v.set_observer(2, 2, 15.5, 15.5, NORTH);
	CHECK(v.is_seen_by_any({9, 5}));
	CHECK(v.is_seen_by_any({15, 10}));
	CHECK_FALSE(v.is_seen_by_any({2, 15}));
	CHECK(v.in_cone(1, 20.0, 5.5));
	CHECK_FALSE(v.in_cone(1, 1.0, 5.5));
}

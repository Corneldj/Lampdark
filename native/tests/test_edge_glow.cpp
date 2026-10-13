// VIS-03: the detail region, the edge glow by bearing, and nothing beyond 40 tiles.
#include "doctest.h"

#include "vision_fixture.h"

#include <cmath>
#include <set>

using namespace vision_fixture;

TEST_CASE("20 tiles ahead is detail, 30 is edge glow, 41 is nothing") {
	World w(3);
	w.spot({20, 0}, 0.5, ColourClass::WHITE);
	w.spot({30, 0}, 0.5, ColourClass::WHITE);
	w.spot({41, 0}, 0.5, ColourClass::WHITE);
	w.settle();
	Vision &v = *w.vision;
	v.set_observer(1, 1, 0.5, 0.5, EAST);
	const PerceptionFrame f = v.compute(1, {});
	std::set<Coord> tiles;
	for (const FrameTile &t : f.tiles) {
		tiles.insert(t.tile);
	}
	CHECK(tiles.count({20, 0}) == 1);
	CHECK(tiles.count({30, 0}) == 0);
	CHECK(tiles.count({41, 0}) == 0);
	REQUIRE(f.glow.size() == 22);
	int present = 0;
	for (size_t b = 0; b < f.glow.size(); b++) {
		if (f.glow[b].present) {
			present++;
			CHECK((b == 10 || b == 11)); // dead ahead: the two middle buckets meet at the facing
			CHECK(f.glow[b].colour == static_cast<uint8_t>(ColourClass::WHITE));
		}
	}
	CHECK(present == 1); // only the tile at 30; 41 sends nothing
}

TEST_CASE("buckets are 5 degrees across the cone, left edge first") {
	World w(1);
	Vision &v = *w.vision;
	v.set_observer(1, 1, 0.0, 0.0, EAST);
	for (int b = 0; b < 22; b++) {
		const double deg = -55.0 + 5.0 * b + 2.5; // the middle of bucket b
		const double r = deg * 3.141592653589793 / 180.0;
		CHECK(v.glow_bucket(1, 30.0 * std::cos(r), 30.0 * std::sin(r)) == b);
	}
	CHECK(v.glow_bucket(1, -30.0, 0.0) == -1); // behind: no bucket
}

TEST_CASE("the detail region follows the full-squint view, widened by 2 tiles") {
	World w(1);
	Vision &v = *w.vision;
	v.set_observer(1, 1, 0.0, 0.0, EAST);
	const std::array<double, 4> r = v.detail_rect(1);
	CHECK(r[0] == doctest::Approx(8.0 - 17.0));
	CHECK(r[2] == doctest::Approx(8.0 + 17.0));
	CHECK(r[1] == doctest::Approx(-(16.875 / 2.0 + 2.0)));
	CHECK(r[3] == doctest::Approx(16.875 / 2.0 + 2.0));
}

TEST_CASE("glow records presence and dominant colour, not distance or brightness") {
	World w(3);
	w.spot({30, -2}, 0.2, ColourClass::AMBER);
	w.spot({35, -2}, 0.9, ColourClass::EGG_GLOW);
	w.spot({38, -2}, 0.9, ColourClass::EGG_GLOW);
	w.settle();
	Vision &v = *w.vision;
	v.set_observer(1, 1, 0.5, 0.5, EAST);
	const PerceptionFrame f = v.compute(1, {});
	int present = 0;
	for (const GlowBucket &g : f.glow) {
		if (g.present) {
			present++;
			CHECK(g.colour == static_cast<uint8_t>(ColourClass::EGG_GLOW));
		}
	}
	CHECK(present == 1);
}

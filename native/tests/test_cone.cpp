// VIS-03: deterministic trig and the vision cone (angles, apex, straight edges).
#include "doctest.h"

#include "core/vision/cone.h"

#include <cmath>
#include <initializer_list>

using namespace lb::core::vision;

TEST_CASE("unit vectors match the reference over the whole circle") {
	for (int i = 0; i <= 4096; i++) {
		const double turns = static_cast<double>(i) / 4096.0 - 0.5;
		const Vec2 v = unit_at_turns(turns);
		const double a = turns * 6.283185307179586;
		CHECK(std::fabs(v.x - std::cos(a)) < 1e-14);
		CHECK(std::fabs(v.y - std::sin(a)) < 1e-14);
	}
	CHECK(unit_at_facing(0).x == doctest::Approx(1.0));
	CHECK(unit_at_facing(16384).y == doctest::Approx(1.0)); // +y, screen down
	CHECK(cos_deg(55.0) == doctest::Approx(std::cos(55.0 * 3.141592653589793 / 180.0)).epsilon(1e-14));
}

TEST_CASE("the cone is 110 degrees about the facing") {
	const Cone c = Cone::make(0.5, 0.5, 0, 110.0);
	for (double deg : {0.0, 30.0, -30.0, 54.9, -54.9}) {
		const double r = deg * 3.141592653589793 / 180.0;
		CHECK(c.contains(0.5 + 10.0 * std::cos(r), 0.5 + 10.0 * std::sin(r)));
	}
	for (double deg : {55.1, -55.1, 90.0, 180.0, -120.0}) {
		const double r = deg * 3.141592653589793 / 180.0;
		CHECK_FALSE(c.contains(0.5 + 10.0 * std::cos(r), 0.5 + 10.0 * std::sin(r)));
	}
}

TEST_CASE("the apex: within half a tile counts as inside, even behind") {
	const Cone c = Cone::make(10.3, 4.7, 16384, 110.0);
	CHECK(c.contains(10.3, 4.3));       // 0.4 behind the facing
	CHECK_FALSE(c.contains(10.3, 4.1)); // 0.6 behind
}

TEST_CASE("edges are straight lines from the miner, never a notch") {
	const Cone c = Cone::make(0.0, 0.0, 8192, 110.0); // facing 45 degrees
	const double edge = (45.0 + 54.99) * 3.141592653589793 / 180.0;
	const double out = (45.0 + 55.01) * 3.141592653589793 / 180.0;
	for (int d = 1; d <= 40; d++) {
		CHECK(c.contains(d * std::cos(edge), d * std::sin(edge)));
		CHECK_FALSE(c.contains(d * std::cos(out), d * std::sin(out)));
	}
}

TEST_CASE("a 140 degree cone (Q6)") {
	const Cone c = Cone::make(0.0, 0.0, 0, 140.0);
	CHECK(c.contains(10.0 * std::cos(1.2), 10.0 * std::sin(1.2)));  // 68.8 degrees
	CHECK_FALSE(c.contains(10.0 * std::cos(1.23), 10.0 * std::sin(1.23))); // 70.5 degrees
}

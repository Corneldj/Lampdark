#include "core/sim/entity_mirror.h"

#include <doctest.h>

using namespace lb::core::sim;

TEST_CASE("the entity mirror round-trips what was pushed") {
	EntityMirror mirror;
	std::vector<MirrorEntity> pushed = {{1, 1, 10.5, -3.25, 0}, {4, 3, 700.0, 12.0, 7}, {9, 12, -0.5, 0.5, 1}};
	CHECK(mirror.set(42, pushed));
	CHECK(mirror.tick() == 42);
	CHECK(mirror.entities() == pushed);
	CHECK(mirror.find(4).value() == pushed[1]);
	CHECK_FALSE(mirror.find(5).has_value());
	CHECK_FALSE(mirror.find(0).has_value());
}

TEST_CASE("the mirror rejects unordered, duplicate or zero IDs and keeps its contents") {
	EntityMirror mirror;
	CHECK(mirror.set(1, {{2, 1, 0, 0, 0}}));
	CHECK_FALSE(mirror.set(2, {{3, 1, 0, 0, 0}, {3, 1, 0, 0, 0}}));
	CHECK_FALSE(mirror.set(2, {{5, 1, 0, 0, 0}, {4, 1, 0, 0, 0}}));
	CHECK_FALSE(mirror.set(2, {{0, 1, 0, 0, 0}}));
	CHECK(mirror.tick() == 1);
	CHECK(mirror.size() == 1);
}

#include "light_fixture.h"

#include <doctest.h>

#include <set>

using namespace light_fixture;

TEST_CASE("shadowcast in the open reaches every tile within depth; the origin first") {
	std::vector<Coord> seen;
	shadowcast({0, 0}, 3, [](Coord) { return false; }, [&](Coord t) { seen.push_back(t); });
	CHECK(seen.front() == Coord{0, 0});
	CHECK(seen.size() == 49); // a 7x7 square
}

TEST_CASE("a 1-tile pillar casts a hard shadow; walls are lit but pass nothing") {
	std::set<Coord> seen;
	auto pillar = [](Coord t) { return t == Coord{2, 0}; };
	shadowcast({0, 0}, 6, pillar, [&](Coord t) { seen.insert(t); });
	CHECK(seen.count({2, 0}) == 1); // the lit face
	CHECK(seen.count({3, 0}) == 0);
	CHECK(seen.count({5, 0}) == 0);
	CHECK(seen.count({3, 2}) == 1);
}

TEST_CASE("shadowcasting is symmetric: if A sees B, B sees A") {
	auto walls = [](Coord t) { return (t.x * 7 + t.y * 13) % 5 == 0 && !(t.x == 0 && t.y == 0); };
	std::set<Coord> from_origin;
	shadowcast({0, 0}, 6, walls, [&](Coord t) { from_origin.insert(t); });
	for (const Coord &t : from_origin) {
		if (walls(t)) {
			continue;
		}
		std::set<Coord> back;
		shadowcast(t, 12, walls, [&](Coord u) { back.insert(u); });
		CHECK(back.count({0, 0}) == 1);
	}
}

TEST_CASE("a doorway lets light through only along its opening") {
	std::set<Coord> seen;
	auto wall_with_door = [](Coord t) { return t.x == 2 && t.y != 0; };
	shadowcast({0, 0}, 8, wall_with_door, [&](Coord t) { seen.insert(t); });
	CHECK(seen.count({4, 0}) == 1);
	CHECK(seen.count({4, 6}) == 0); // hidden behind the wall
}

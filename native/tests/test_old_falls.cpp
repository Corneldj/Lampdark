// GEN-07: old falls: their rate among eligible cells, their exclusions, their forced exits and the
// two halves of the road they leave.

#include "core/rng/rng.h"
#include "main_road_fixture.h"

#include <doctest.h>

using namespace main_road_fixture;

TEST_CASE("GEN-07 old falls hold 1/6 of eligible cells and never a crossing, bend, arch or spine") {
	lb::core::Rng rng(711);
	int64_t eligible = 0;
	int64_t falls = 0;
	for (int s = 0; s < 400; s++) {
		const uint64_t seed = rng.next_u64();
		std::set<Coord> arches{{1, 0}, {0, 1}, {-1, 0}};
		MainRoads roads(seed, MainRoadParams{}, {80, 200, 400, 700}, arches);
		roads.is_spine = [](Coord c) { return c.x == 0 && c.y < 0 && c.y > -8; }; // a spine up the north arm
		for (int64_t k = -4; k <= 4; k++) {
			for (int64_t along = -35; along <= 35; along++) {
				for (bool row : {true, false}) {
					const Coord c = row ? Coord{along, k * 8} : Coord{k * 8, along};
					if (!roads.is_main_road_cell(c) || (!row && roads.on_row(c))) {
						continue; // each cell once
					}
					const bool fall = roads.old_fall(c);
					if (roads.is_crossing(c) || roads.bend_in(c) >= 0 || arches.count(c) != 0 || roads.is_spine(c)) {
						CHECK_FALSE(fall);
						continue;
					}
					eligible++;
					falls += fall ? 1 : 0;
				}
			}
		}
	}
	const double rate = static_cast<double>(falls) / static_cast<double>(eligible);
	MESSAGE(falls, " old falls in ", eligible, " eligible cells: ", rate);
	CHECK(std::abs(rate - 1.0 / 6.0) < 0.005);
}

TEST_CASE("GEN-07 an old fall's exits are open on both sides, and it splits the road in two") {
	auto set = road_set();
	lb::core::Rng rng(712);
	int64_t seen = 0;
	for (int s = 0; s < 40 && seen < 200; s++) {
		auto run = road_run(rng.next_u64(), set);
		Deriver d(run->inputs(), 512);
		for (int64_t k = -3; k <= 3; k++) {
			for (int64_t along = -30; along <= 30; along++) {
				for (bool row : {true, false}) {
					const Coord c = row ? Coord{along, k * 8} : Coord{k * 8, along};
					if (!run->roads->old_fall(c)) {
						continue;
					}
					const std::optional<Layout> l = d.derive(c, 0);
					REQUIRE(l.has_value());
					CHECK(l->template_id == "main_straight_oldfall");
					const Edge near = row ? Edge::NORTH : Edge::WEST;
					const Edge far = row ? Edge::SOUTH : Edge::EAST;
					const Socket &a = l->sockets[static_cast<size_t>(near)];
					const Socket &b = l->sockets[static_cast<size_t>(far)];
					CHECK(a.open);
					CHECK(a.forced);
					CHECK(a.offset == 5);
					CHECK(b.open);
					CHECK(b.forced);
					CHECK(b.offset == 15);
					// The same sockets from the neighbours' side.
					CHECK(d.socket(edge_of(neighbour(c, near), opposite(near))) == a);
					CHECK(d.socket(edge_of(neighbour(c, far), opposite(far))) == b);
					// The fall is rock across the road; rails stop at it.
					const Coord mid = row ? Coord{10, 10} : Coord{10, 10};
					CHECK(l->cell.tiles[static_cast<size_t>(Cell::index_of(mid.x, mid.y))].material != static_cast<uint8_t>(TileMaterial::FLOOR));
					seen++;
				}
			}
		}
	}
	CHECK(seen >= 100);
}

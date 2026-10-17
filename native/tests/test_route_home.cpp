// LFT-12: a phone line's road home through derived cells. From a road tile cells out, or from beside
// a phone hung on a wall, the route steps 4-connected over passable tiles to a gate's opening beyond
// base camp; asked again it is the same (a pure function of the seed); its crossings name the
// alternates whose fallen rock it crosses; and a search held too close to base camp finds none.

#include "validate_fixture.h"

#include <doctest.h>

using namespace validate_fixture;
using lb::core::world::Coord;
using lb::core::world::TileMaterial;

namespace {

bool passable_at(const DerivedWorld &world, Coord t) {
	const std::optional<Layout> l = world.layout(lb::core::world::cell_of(t));
	if (!l || l->base_camp) {
		return false;
	}
	const Coord local = lb::core::world::local_of(t);
	const TileMaterial m = static_cast<TileMaterial>(l->cell.tiles[static_cast<size_t>(Cell::index_of(local.x, local.y))].material);
	return m == TileMaterial::FLOOR || m == TileMaterial::STEEL || m == TileMaterial::WOODEN_DOOR;
}

// The first passable tile of a cell, scanning rows.
std::optional<Coord> floor_in(const DerivedWorld &world, Coord cell) {
	for (int64_t y = 0; y < lb::core::world::CELL_TILES; y++) {
		for (int64_t x = 0; x < lb::core::world::CELL_TILES; x++) {
			const Coord t = lb::core::world::tile_of(cell, {x, y});
			if (passable_at(world, t)) {
				return t;
			}
		}
	}
	return std::nullopt;
}

} // namespace

TEST_CASE("LFT-12 a phone's road home, through derived cells to a gate") {
	int64_t routed = 0;
	for (uint64_t seed : {41ull, 977ull}) {
		const auto run = planned_run(seed, 1);
		for (const Coord cell : {Coord{3, 0}, Coord{-2, 2}, Coord{1, -3}}) {
			const std::optional<Coord> from = floor_in(*run->world, cell);
			if (!from) {
				continue;
			}
			const RouteHome r = route_home(*run->world, *from, 6, 400000);
			REQUIRE_MESSAGE(r.found, "seed " << seed << " cell " << cell.x << "," << cell.y);
			CHECK(r.tiles.front() == *from);
			for (size_t i = 1; i < r.tiles.size(); i++) {
				const int64_t step = std::abs(r.tiles[i].x - r.tiles[i - 1].x) + std::abs(r.tiles[i].y - r.tiles[i - 1].y);
				CHECK(step == 1);
				CHECK(passable_at(*run->world, r.tiles[i]));
			}
			const Coord last = lb::core::world::cell_of(r.tiles.back());
			CHECK_MESSAGE(std::abs(last.x) + std::abs(last.y) == 1, "it ends beside base camp, at a gate");
			const RouteHome again = route_home(*run->world, *from, 6, 400000);
			CHECK(again.tiles == r.tiles);
			CHECK(again.crossings == r.crossings);
			for (const auto &[c, id] : r.crossings) {
				const std::optional<Layout> l = run->world->layout(c);
				REQUIRE(l);
				bool crossed = false;
				for (const lb::core::world::Collapse &alt : l->cell.collapses) {
					if (alt.id != id) {
						continue;
					}
					for (const lb::core::world::TileWrite &w : alt.fallen) {
						const Coord t = lb::core::world::tile_of(c, {w.index % lb::core::world::CELL_TILES, w.index / lb::core::world::CELL_TILES});
						crossed = crossed || std::find(r.tiles.begin(), r.tiles.end(), t) != r.tiles.end();
					}
				}
				CHECK_MESSAGE(crossed, "a crossing's fallen rock lies on the route");
			}
			CHECK_FALSE_MESSAGE(route_home(*run->world, *from, 1, 400000).found, "held to the cells beside base camp, none from 2+ cells out");
			routed++;
		}
	}
	CHECK(routed >= 4);
}

TEST_CASE("LFT-12 a phone on a wall starts from the floor beside it") {
	const auto run = planned_run(41, 1);
	const std::optional<Coord> floor = floor_in(*run->world, {2, 0});
	REQUIRE(floor);
	// The rock next to that floor tile: scanning rows, the tile before it (or above) is solid.
	Coord wall = {floor->x - 1, floor->y};
	if (passable_at(*run->world, wall)) {
		wall = {floor->x, floor->y - 1};
	}
	REQUIRE_FALSE(passable_at(*run->world, wall));
	const RouteHome r = route_home(*run->world, wall, 6, 400000);
	REQUIRE(r.found);
	CHECK(passable_at(*run->world, r.tiles.front()));
	CHECK(std::abs(r.tiles.front().x - wall.x) + std::abs(r.tiles.front().y - wall.y) == 1);
}

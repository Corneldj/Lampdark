#include "core/world/coords.h"
#include "golden/coords_vectors.gen.h"

#include <doctest.h>

using namespace lb::core::world;

TEST_CASE("floor division puts negative tiles in negative cells") {
	CHECK(cell_of({-1, 0}).x == -1);
	CHECK(local_of({-1, 0}).x == 19);
	CHECK(cell_of({-20, 0}).x == -1);
	CHECK(local_of({-20, 0}).x == 0);
	CHECK(cell_of({-21, 0}).x == -2);
	CHECK(local_of({-21, 0}).x == 19);
	for (const golden_coords::Division &d : golden_coords::DIVISION) {
		CHECK(floor_div(d.tile, CELL_TILES) == d.cell);
		CHECK(floor_mod(d.tile, CELL_TILES) == d.local);
	}
}

TEST_CASE("cell_of and local_of round-trip every tile in -200..200") {
	for (int64_t x = -200; x <= 200; x++) {
		for (int64_t y = -200; y <= 200; y += 7) {
			const Coord t{x, y};
			const Coord l = local_of(t);
			CHECK(tile_of(cell_of(t), l) == t);
			CHECK(l.x >= 0);
			CHECK(l.x < CELL_TILES);
		}
	}
}

TEST_CASE("blocks, regions and cell distances") {
	CHECK(block_of_cell({-1, 1}) == Coord{-1, 0});
	CHECK(block_of_cell({3, -4}) == Coord{1, -2});
	CHECK(region_of_cell({-1, 4}) == Coord{-1, 0});
	CHECK(region_of_cell({5, -6}) == Coord{1, -2});
	CHECK(cell_chebyshev({0, 0}, {3, -4}) == 4);
	CHECK(cell_manhattan({0, 0}, {3, -4}) == 7);
}

TEST_CASE("ring boundaries match the shared vectors in every direction") {
	for (const golden_coords::Ring &r : golden_coords::RINGS) {
		CHECK(ring_of_tile({r.x, r.y}, golden_coords::BOUNDS) == r.ring);
	}
	CHECK(ring_of_tile({10, 10}, golden_coords::BOUNDS) == 0);
}

TEST_CASE("ring_of_point agrees with ring_of_tile at tile centres") {
	for (const golden_coords::Ring &r : golden_coords::RINGS) {
		CHECK(ring_of_point(r.x + 0.5, r.y + 0.5, golden_coords::BOUNDS) == r.ring);
	}
	for (int64_t x = -820; x <= 820; x += 13) {
		for (int64_t y = -820; y <= 820; y += 17) {
			CHECK(ring_of_point(x + 0.5, y + 0.5, golden_coords::BOUNDS) == ring_of_tile({x, y}, golden_coords::BOUNDS));
		}
	}
	for (const golden_coords::Point &p : golden_coords::POINTS) {
		CHECK(ring_of_point(p.x, p.y, golden_coords::BOUNDS) == p.ring);
	}
}

TEST_CASE("ring bounds are data: moving them moves the boundary") {
	const std::vector<int64_t> wider = {90, 200, 400, 700};
	CHECK(ring_of_tile({90, 9}, golden_coords::BOUNDS) == 1); // centre about 80.5 tiles out
	CHECK(ring_of_tile({90, 9}, wider) == 0);
}

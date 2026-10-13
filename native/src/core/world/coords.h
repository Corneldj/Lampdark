#pragma once
// World coordinates (FND-07). Integer maths only, so every result is identical on every
// platform. Thread-safe: pure functions.
//
// Axes: +x east, +y south; north is -y and stays up on screen. Tiles are 1 m. Cell (cx, cy)
// covers tiles x in [20cx, 20cx+19], y in [20cy, 20cy+19]; cell (0,0) holds base camp and
// the shaft. Blocks are 2x2 cells (biomes), regions 5x5 cells (points of interest).

#include "core/generated/world_ids.h"

#include <cstdint>
#include <vector>

namespace lb::core::world {

struct Coord {
	int64_t x = 0;
	int64_t y = 0;
	bool operator==(const Coord &o) const { return x == o.x && y == o.y; }
	bool operator!=(const Coord &o) const { return !(*this == o); }
	// Row-major order (y, then x): the global tile order ties are broken by.
	bool operator<(const Coord &o) const { return y != o.y ? y < o.y : x < o.x; }
};

// Floor division and its matching modulo: floor_div(-1, 20) == -1, floor_mod(-1, 20) == 19.
constexpr int64_t floor_div(int64_t a, int64_t b) {
	const int64_t q = a / b;
	return (a % b != 0 && ((a < 0) != (b < 0))) ? q - 1 : q;
}
constexpr int64_t floor_mod(int64_t a, int64_t b) {
	return a - floor_div(a, b) * b;
}

constexpr Coord cell_of(Coord tile) { return {floor_div(tile.x, CELL_TILES), floor_div(tile.y, CELL_TILES)}; }
constexpr Coord local_of(Coord tile) { return {floor_mod(tile.x, CELL_TILES), floor_mod(tile.y, CELL_TILES)}; }
constexpr Coord tile_of(Coord cell, Coord local) {
	return {cell.x * CELL_TILES + local.x, cell.y * CELL_TILES + local.y};
}
constexpr Coord block_of_cell(Coord cell) { return {floor_div(cell.x, BLOCK_CELLS), floor_div(cell.y, BLOCK_CELLS)}; }
constexpr Coord region_of_cell(Coord cell) { return {floor_div(cell.x, REGION_CELLS), floor_div(cell.y, REGION_CELLS)}; }

int64_t cell_chebyshev(Coord a, Coord b);
int64_t cell_manhattan(Coord a, Coord b);

// The ring of a tile, by its centre's straight-line distance from the shaft. `bounds` are the
// starts of rings 1..n in tiles (depth.ring_start_tiles: 80, 200, 400, 700); the ring is the
// number of bounds b with distance >= b. Exact: doubled integer coordinates, no sqrt.
int64_t ring_of_tile(Coord tile, const std::vector<int64_t> &bounds);

// The ring of a point in tile units: squared distance against squared bounds. Agrees with
// ring_of_tile at tile centres.
int64_t ring_of_point(double x, double y, const std::vector<int64_t> &bounds);

} // namespace lb::core::world

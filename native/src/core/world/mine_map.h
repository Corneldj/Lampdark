#pragma once
// The loaded mine (GEN-01): committed cells, the material table, the distance fields, barrier
// and collapse changes, and path queries. Tick thread only: GEN-11's workers build Cells
// off-thread and hand them over; commit() and unload() run between systems on the tick
// thread, so no query ever sees a half-committed cell.

#include "core/world/cell.h"

#include <map>
#include <memory>
#include <optional>
#include <set>
#include <vector>

namespace lb::core::world {

// A change of tiles, reported in the tick it happens (tiles_changed).
struct TileChange {
	Coord cell;
	int64_t x0 = 0, y0 = 0, x1 = 0, y1 = 0; // inclusive global tile rect
	std::string reason;
};

struct PathResult {
	int64_t distance_milli = -1; // -1: unreachable within the maximum
	bool touched_unloaded = false;
	bool hit_max = false;
};

class MineMap {
public:
	// Field search reach, in tiles: distances beyond it read as FIELD_FAR.
	static constexpr int64_t FIELD_REACH = 4;
	static constexpr uint32_t FIELD_FAR = 0xFFFFFFFF;
	static constexpr uint8_t THICKNESS_CAP = 8;

	MaterialTable materials = MaterialTable::defaults();
	// Path costs in thousandths of a tile (mine.path_diagonal_cost: 1.414).
	int64_t orthogonal_cost_milli = 1000;
	int64_t diagonal_cost_milli = 1414;

	void commit(std::unique_ptr<Cell> cell);
	bool unload(Coord cell);
	bool is_loaded(Coord cell) const { return cells_.count(cell) != 0; }
	size_t loaded_count() const { return cells_.size(); }
	const Cell *cell(Coord coord) const;
	std::vector<Coord> loaded_cells() const; // ascending (y, x)

	// Tile queries by global tile. Unloaded tiles read as solid ROCK with `loaded` false.
	std::optional<Tile> tile_at(Coord tile) const;
	TileMaterial effective_material(Coord tile) const;
	bool is_walkable(Coord tile, bool doors_open = false) const;
	bool is_solid(Coord tile) const;
	bool is_opaque(Coord tile) const;
	// A solid tile whose material allows Tapper face use and which touches open floor.
	bool tapper_face_usable(Coord tile) const;
	uint32_t strike_milli(Coord tile) const; // FIELD_FAR if beyond reach or not floor
	uint32_t depth_milli(Coord tile) const;  // FIELD_FAR if beyond reach or not solid
	uint8_t thickness(Coord tile) const;     // 0 for anything but rock or coal

	// Opens or shuts a barrier; swaps a collapse alternate. Each applies at once and queues a
	// TileChange. Return false for an unknown cell or ID.
	bool set_barrier(Coord cell, uint32_t barrier_id, bool open);
	bool set_collapse(Coord cell, uint32_t collapse_id, bool fallen);
	std::vector<TileChange> take_changes();

	// 8-connected walk cost (orthogonal 1, diagonal 1.414, no corner cutting), stopping at
	// max_milli. Shut barriers block unless doors_open. Unloaded cells block and are flagged.
	PathResult path_distance(Coord from, Coord to, int64_t max_milli, bool doors_open = false) const;
	// Every walkable tile within max_milli of `from` (a flood); returns how many were reached.
	size_t flood_count(Coord from, int64_t max_milli, bool doors_open = false) const;

	// The walkable tile whose centre is nearest (x, y) in a straight line, skipping `exclude`,
	// within max_radius tiles. Ties go to the lowest (y, x).
	std::optional<Coord> nearest_open_tile(double x, double y, const std::set<Coord> &exclude, int64_t max_radius) const;

private:
	std::map<Coord, std::unique_ptr<Cell>> cells_;
	std::vector<TileChange> changes_;

	Cell *cell_mut(Coord coord);
	void rebuild_fields_around(Coord cell);
	void rebuild_fields(Cell &cell);
	// A dense copy of walkability around a query: 0 blocked, 1 walkable, 2 unloaded.
	struct Window {
		int64_t x0 = 0, y0 = 0, w = 0;
		std::vector<uint8_t> pass;
	};
	Window window_around(Coord centre, int64_t radius, bool doors_open) const;
	template <typename Visit>
	void walk(Coord from, int64_t max_milli, bool doors_open, Visit visit, bool &touched_unloaded) const;
};

} // namespace lb::core::world

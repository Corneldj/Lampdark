#pragma once
// One 20x20-tile cell of the mine (GEN-01): tiles, anchors, barriers and collapse alternates,
// plus the derived distance fields. Built off-thread (GEN-11), then committed to the MineMap
// on the tick thread; after commit only the MineMap touches it.

#include "core/world/coords.h"
#include "core/world/materials.h"

#include <array>
#include <cstdint>
#include <string>
#include <vector>

namespace lb::core::world {

constexpr int64_t CELL_AREA = CELL_TILES * CELL_TILES;

struct Tile {
	uint8_t material = static_cast<uint8_t>(TileMaterial::ROCK);
	uint8_t state = 0;
	uint16_t zone = 0; // Road Graph zone (SND-01)
};

// Anchor types (GEN-01). Never marked in the world, never sent to a client.
enum class AnchorType : uint8_t {
	TIMBER_HOOK, RUBBLE_HEAP, LANDMARK, CHAMBER, REMAINS, ITEM, WALL_FIXTURE, DOOR_SITE,
	TRAP_SITE, LOW_ROAD, GAS_AREA, GAS_DEAD_END, RICH_ROCK, COLLAPSE, POI_SLOT, COUNT
};

struct Anchor {
	AnchorType type = AnchorType::ITEM;
	int32_t x = 0; // local tile
	int32_t y = 0;
	int32_t w = 1;
	int32_t h = 1;
	std::vector<std::string> tags;
	std::string kind; // e.g. a poi_slot's kind
};

// A gate or air door: a tile set that opens and shuts, with its Road Graph portal.
struct Barrier {
	uint32_t id = 0;
	uint32_t portal = 0;
	std::vector<uint16_t> tiles; // local indices (y * 20 + x)
	bool open = false;
};

struct TileWrite {
	uint16_t index = 0;
	uint8_t material = 0;
};

// A collapse alternate: the standing and fallen tile sets (HAZ-03 decides when it falls).
struct Collapse {
	uint32_t id = 0;
	std::vector<TileWrite> standing;
	std::vector<TileWrite> fallen;
	bool is_fallen = false;
};

struct Cell {
	Coord coord;
	std::array<Tile, CELL_AREA> tiles{};
	std::vector<Anchor> anchors;
	std::vector<Barrier> barriers;
	std::vector<Collapse> collapses;
	std::vector<uint8_t> road_graph; // SND-01's zones and portals, opaque here

	// Derived on commit and after tile changes, in thousandths of a tile.
	std::array<uint32_t, CELL_AREA> strike_milli{}; // floor: to the nearest usable rock face
	std::array<uint32_t, CELL_AREA> depth_milli{};  // solid: to the nearest open floor
	std::array<uint8_t, CELL_AREA> thickness{};     // rock: side of the largest all-rock square holding it

	static int64_t index_of(int64_t lx, int64_t ly) { return ly * CELL_TILES + lx; }
};

// Canonical bytes of a cell's content and state (tiles, anchors, barriers, collapses, Road
// Graph block), hashed with FND-06 for GEN-05/GEN-11/GEN-14's comparisons.
uint64_t content_digest(const Cell &cell);

} // namespace lb::core::world

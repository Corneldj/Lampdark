#pragma once
// Cells with Road Graph zones for SND-01's tests. Tile characters: '1'-'9' floor in that zone,
// 'o' an opening portal tile, 'S' a gate tile, 'D' an air-door tile (both portal tiles),
// '#' rock, 'B' brick, 'c' coal. Missing tiles are rock.

#include "core/sound/road_graph.h"

#include <memory>
#include <string>
#include <vector>

namespace road_fixture {

using namespace lb::core::world;
using namespace lb::core::sound;

inline std::unique_ptr<Cell> cell(Coord coord, const std::vector<std::string> &rows) {
	auto c = std::make_unique<Cell>();
	c->coord = coord;
	for (int64_t y = 0; y < CELL_TILES; y++) {
		for (int64_t x = 0; x < CELL_TILES; x++) {
			const char ch = y < static_cast<int64_t>(rows.size()) && x < static_cast<int64_t>(rows[y].size()) ? rows[y][x] : '#';
			Tile &t = c->tiles[Cell::index_of(x, y)];
			t.zone = 0;
			if (ch >= '1' && ch <= '9') {
				t.material = static_cast<uint8_t>(TileMaterial::FLOOR);
				t.zone = static_cast<uint16_t>(ch - '0');
			} else if (ch == 'o') {
				t.material = static_cast<uint8_t>(TileMaterial::FLOOR);
			} else if (ch == 'S') {
				t.material = static_cast<uint8_t>(TileMaterial::STEEL);
			} else if (ch == 'D') {
				t.material = static_cast<uint8_t>(TileMaterial::WOODEN_DOOR);
			} else if (ch == 'B') {
				t.material = static_cast<uint8_t>(TileMaterial::BRICK);
			} else if (ch == 'c') {
				t.material = static_cast<uint8_t>(TileMaterial::COAL);
			} else {
				t.material = static_cast<uint8_t>(TileMaterial::ROCK);
			}
		}
	}
	return c;
}

inline CellBlock zones(std::initializer_list<uint16_t> ids) {
	CellBlock b;
	for (uint16_t id : ids) {
		b.zones.push_back({id, ZoneKind::ROAD});
	}
	return b;
}

inline PortalDecl portal(uint16_t id, PortalKind kind, uint16_t a, uint16_t b, std::vector<Coord> local_tiles, uint32_t barrier = 0) {
	PortalDecl p;
	p.id = id;
	p.kind = kind;
	p.zone_a = a;
	p.zone_b = b;
	p.barrier = barrier;
	for (const Coord &t : local_tiles) {
		p.tiles.push_back(static_cast<uint16_t>(Cell::index_of(t.x, t.y)));
	}
	return p;
}

inline Barrier barrier(uint32_t id, std::vector<Coord> local_tiles, bool open = false) {
	Barrier b;
	b.id = id;
	b.open = open;
	for (const Coord &t : local_tiles) {
		b.tiles.push_back(static_cast<uint16_t>(Cell::index_of(t.x, t.y)));
	}
	return b;
}

inline std::vector<std::string> road_row(int row, char zone = '1') {
	std::vector<std::string> rows(CELL_TILES, std::string(CELL_TILES, '#'));
	rows[row] = std::string(CELL_TILES, zone);
	return rows;
}

} // namespace road_fixture

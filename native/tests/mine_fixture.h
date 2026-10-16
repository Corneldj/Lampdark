#pragma once
// Builds cells from ASCII rows for GEN-01's tests: '.' floor, '=' rails, '~' sump mud, '#' rock, 'c' coal, 'B' brick,
// 'T' timber, 'S' shut steel gate, 's' open gate, 'D' shut air door, 'd' open air door.
// Missing rows and columns are rock.

#include "core/world/mine_map.h"

#include <memory>
#include <string>
#include <vector>

namespace mine_fixture {

using namespace lb::core::world;

inline std::unique_ptr<Cell> cell_from(Coord coord, const std::vector<std::string> &rows) {
	auto cell = std::make_unique<Cell>();
	cell->coord = coord;
	for (int64_t y = 0; y < CELL_TILES; y++) {
		for (int64_t x = 0; x < CELL_TILES; x++) {
			const char ch = y < static_cast<int64_t>(rows.size()) && x < static_cast<int64_t>(rows[y].size()) ? rows[y][x] : '#';
			Tile &t = cell->tiles[Cell::index_of(x, y)];
			switch (ch) {
				case '.': t.material = static_cast<uint8_t>(TileMaterial::FLOOR); break;
				case '=':
					t.material = static_cast<uint8_t>(TileMaterial::FLOOR);
					t.state = STATE_RAIL;
					break;
				case '~':
					t.material = static_cast<uint8_t>(TileMaterial::FLOOR);
					t.state = STATE_MUD;
					break;
				case 'c': t.material = static_cast<uint8_t>(TileMaterial::COAL); break;
				case 'B': t.material = static_cast<uint8_t>(TileMaterial::BRICK); break;
				case 'T': t.material = static_cast<uint8_t>(TileMaterial::TIMBER); break;
				case 'S': t.material = static_cast<uint8_t>(TileMaterial::STEEL); break;
				case 's': t.material = static_cast<uint8_t>(TileMaterial::STEEL); t.state = STATE_OPEN; break;
				case 'D': t.material = static_cast<uint8_t>(TileMaterial::WOODEN_DOOR); break;
				case 'd': t.material = static_cast<uint8_t>(TileMaterial::WOODEN_DOOR); t.state = STATE_OPEN; break;
				default: t.material = static_cast<uint8_t>(TileMaterial::ROCK); break;
			}
		}
	}
	return cell;
}

// A square room of `side` floor tiles centred in an all-`wall` cell.
inline std::vector<std::string> room(int side, char wall = '#') {
	std::vector<std::string> rows(CELL_TILES, std::string(CELL_TILES, wall));
	const int start = (CELL_TILES - side) / 2;
	for (int y = start; y < start + side; y++) {
		for (int x = start; x < start + side; x++) {
			rows[y][x] = '.';
		}
	}
	return rows;
}

} // namespace mine_fixture

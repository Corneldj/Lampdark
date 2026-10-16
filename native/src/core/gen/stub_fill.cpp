#include "core/gen/stub_fill.h"

#include "core/sound/zone_block.h"

#include <set>

namespace lb::core::gen {

using lb::core::world::Cell;
using lb::core::world::CELL_TILES;
using lb::core::world::Coord;
using lb::core::world::TileMaterial;

Cell fill_stubs(const Template &t, const CellSockets &sockets, Coord coord, Coord local) {
	Cell cell = t.cells.front();
	for (const Cell &c : t.cells) {
		if (c.coord == local) {
			cell = c;
		}
	}
	cell.coord = coord;
	// Throat tiles are footprint-global: this cell's start at local * 20.
	const int64_t ox = local.x * CELL_TILES;
	const int64_t oy = local.y * CELL_TILES;
	for (const Stub &s : t.stubs) {
		if (!(s.cell == local)) {
			continue;
		}
		const Socket &socket = sockets[static_cast<size_t>(s.edge)];
		const bool used = socket.open && socket.offset == s.offset && socket.width <= s.max_width;
		std::set<std::pair<int64_t, int64_t>> keep;
		if (used) {
			for (const Coord &c : throat(t, s, socket.width)) {
				keep.insert({c.x - ox, c.y - oy});
			}
		}
		for (const Coord &g : throat(t, s, s.max_width)) {
			const Coord c{g.x - ox, g.y - oy};
			if (keep.count({c.x, c.y}) == 0 && c.x >= 0 && c.y >= 0 && c.x < CELL_TILES && c.y < CELL_TILES) {
				lb::core::world::Tile &tile = cell.tiles[static_cast<size_t>(Cell::index_of(c.x, c.y))];
				tile.material = static_cast<uint8_t>(TileMaterial::ROCK);
				tile.state = 0;
			}
		}
	}
	using lb::core::sound::ZoneKind;
	const bool base_camp = t.kind == TemplateKind::BASE_CAMP;
	const uint8_t room = static_cast<uint8_t>(t.kind == TemplateKind::POI ? ZoneKind::POI : ZoneKind::CHAMBER);
	cut_zones(cell, room, base_camp);
	cut_collapses(cell, room, base_camp);
	return cell;
}

} // namespace lb::core::gen

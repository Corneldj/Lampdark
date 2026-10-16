#include "core/gen/template.h"

#include "core/sound/zone_block.h"

#include <algorithm>
#include <deque>
#include <map>
#include <set>
#include <tuple>

namespace lb::core::gen {

using lb::core::sound::CellBlock;
using lb::core::sound::PortalDecl;
using lb::core::sound::PortalKind;
using lb::core::sound::ZoneDecl;
using lb::core::sound::ZoneKind;
using lb::core::world::Anchor;
using lb::core::world::AnchorType;
using lb::core::world::Barrier;
using lb::core::world::Cell;
using lb::core::world::CELL_AREA;
using lb::core::world::CELL_TILES;
using lb::core::world::TileMaterial;
using lb::core::world::ZoneWrite;

namespace {

bool is_floor(const Cell &c, int64_t i) {
	return c.tiles[static_cast<size_t>(i)].material == static_cast<uint8_t>(TileMaterial::FLOOR);
}

bool is_door(const Cell &c, int64_t i) {
	const uint8_t m = c.tiles[static_cast<size_t>(i)].material;
	return m == static_cast<uint8_t>(TileMaterial::WOODEN_DOOR) || m == static_cast<uint8_t>(TileMaterial::STEEL);
}

std::vector<int64_t> neighbours(int64_t i) {
	std::vector<int64_t> out;
	const int64_t x = i % CELL_TILES;
	const int64_t y = i / CELL_TILES;
	if (x + 1 < CELL_TILES)
		out.push_back(i + 1);
	if (x > 0)
		out.push_back(i - 1);
	if (y + 1 < CELL_TILES)
		out.push_back(i + CELL_TILES);
	if (y > 0)
		out.push_back(i - CELL_TILES);
	return out;
}

// The 4-connected component of `start` among the tiles `member` accepts.
template <typename F>
std::vector<int64_t> component(int64_t start, std::vector<uint8_t> &seen, F member) {
	std::vector<int64_t> out{start};
	seen[static_cast<size_t>(start)] = 1;
	std::deque<int64_t> q{start};
	while (!q.empty()) {
		const int64_t t = q.front();
		q.pop_front();
		for (int64_t n : neighbours(t)) {
			if (!seen[static_cast<size_t>(n)] && member(n)) {
				seen[static_cast<size_t>(n)] = 1;
				out.push_back(n);
				q.push_back(n);
			}
		}
	}
	return out;
}

// The zones a run of tiles touches, in the order first met.
std::vector<uint16_t> touched(const std::vector<int64_t> &run, const std::vector<uint16_t> &zone) {
	std::vector<uint16_t> out;
	for (int64_t t : run) {
		for (int64_t n : neighbours(t)) {
			const uint16_t z = zone[static_cast<size_t>(n)];
			if (z != 0 && std::find(out.begin(), out.end(), z) == out.end()) {
				out.push_back(z);
			}
		}
	}
	return out;
}

} // namespace

void cut_zones(Cell &cell, uint8_t room_kind, bool base_camp) {
	std::vector<uint16_t> zone(CELL_AREA, 0);
	CellBlock block;
	uint16_t next_zone = 1;
	uint16_t next_portal = 1;
	std::vector<uint8_t> seen(CELL_AREA, 0);
	// Barriers first, so their ids hold in every collapse's fallen cut: each run of one door or gate
	// material, with its portal (the zones it joins are filled in last).
	std::vector<std::vector<int64_t>> doors;
	for (int64_t i = 0; i < CELL_AREA; i++) {
		if (!seen[static_cast<size_t>(i)] && is_door(cell, i)) {
			const uint8_t m = cell.tiles[static_cast<size_t>(i)].material;
			doors.push_back(component(i, seen, [&](int64_t n) { return cell.tiles[static_cast<size_t>(n)].material == m; }));
		}
	}
	cell.barriers.clear();
	for (size_t d = 0; d < doors.size(); d++) {
		const lb::core::world::Tile &first = cell.tiles[static_cast<size_t>(doors[d][0])];
		Barrier b;
		b.id = static_cast<uint32_t>(d + 1);
		b.portal = next_portal;
		b.open = (first.state & lb::core::world::STATE_OPEN) != 0;
		PortalDecl p;
		p.id = next_portal++;
		p.kind = first.material == static_cast<uint8_t>(TileMaterial::STEEL) ? PortalKind::GATE : PortalKind::AIR_DOOR;
		p.barrier = b.id;
		std::sort(doors[d].begin(), doors[d].end());
		for (int64_t t : doors[d]) {
			b.tiles.push_back(static_cast<uint16_t>(t));
			p.tiles.push_back(static_cast<uint16_t>(t));
		}
		block.portals.push_back(p);
		cell.barriers.push_back(b);
	}
	// Rooms: each chamber anchor's floor.
	const ZoneKind room = base_camp ? ZoneKind::BASE_CAMP : static_cast<ZoneKind>(room_kind);
	std::set<uint16_t> rooms;
	for (const Anchor &a : cell.anchors) {
		if (a.type != AnchorType::CHAMBER) {
			continue;
		}
		const uint16_t id = next_zone++;
		block.zones.push_back(ZoneDecl{id, room});
		rooms.insert(id);
		for (int64_t y = std::max<int64_t>(0, a.y); y < a.y + a.h && y < CELL_TILES; y++) {
			for (int64_t x = std::max<int64_t>(0, a.x); x < a.x + a.w && x < CELL_TILES; x++) {
				if (is_floor(cell, Cell::index_of(x, y))) {
					zone[static_cast<size_t>(Cell::index_of(x, y))] = id;
				}
			}
		}
	}
	// Opening candidates: floor outside the rooms touching one; each 4-connected run is one opening.
	std::vector<uint8_t> opening(CELL_AREA, 0);
	for (int64_t i = 0; i < CELL_AREA; i++) {
		if (!is_floor(cell, i) || zone[static_cast<size_t>(i)] != 0) {
			continue;
		}
		for (int64_t n : neighbours(i)) {
			opening[static_cast<size_t>(i)] |= rooms.count(zone[static_cast<size_t>(n)]) != 0 ? 1 : 0;
		}
	}
	std::vector<std::vector<int64_t>> runs;
	std::fill(seen.begin(), seen.end(), 0);
	for (int64_t i = 0; i < CELL_AREA; i++) {
		if (opening[static_cast<size_t>(i)] && !seen[static_cast<size_t>(i)]) {
			runs.push_back(component(i, seen, [&](int64_t n) { return opening[static_cast<size_t>(n)] != 0; }));
		}
	}
	// Roads: the remaining floor regions.
	std::fill(seen.begin(), seen.end(), 0);
	const ZoneKind road = base_camp ? ZoneKind::BASE_CAMP : ZoneKind::ROAD;
	for (int64_t i = 0; i < CELL_AREA; i++) {
		if (!is_floor(cell, i) || zone[static_cast<size_t>(i)] != 0 || opening[static_cast<size_t>(i)] || seen[static_cast<size_t>(i)]) {
			continue;
		}
		const uint16_t id = next_zone++;
		block.zones.push_back(ZoneDecl{id, road});
		for (int64_t t : component(i, seen, [&](int64_t n) { return is_floor(cell, n) && zone[static_cast<size_t>(n)] == 0 && !opening[static_cast<size_t>(n)]; })) {
			zone[static_cast<size_t>(t)] = id;
		}
	}
	// An opening that leads nowhere (a nook, a mouth onto a door, or the cell's edge, where the
	// neighbour's edge link joins it) is part of its room; the rest are portals between two zones.
	for (const std::vector<int64_t> &run : runs) {
		const std::vector<uint16_t> zs = touched(run, zone);
		if (zs.size() == 1) {
			for (int64_t t : run) {
				zone[static_cast<size_t>(t)] = zs[0];
			}
			continue;
		}
		PortalDecl p;
		p.id = next_portal++;
		p.kind = PortalKind::OPENING;
		p.zone_a = zs.size() > 0 ? zs[0] : 0;
		p.zone_b = zs.size() > 1 ? zs[1] : 0;
		std::vector<int64_t> sorted = run;
		std::sort(sorted.begin(), sorted.end());
		for (int64_t t : sorted) {
			p.tiles.push_back(static_cast<uint16_t>(t));
		}
		block.portals.push_back(p);
	}
	// Each barrier joins the zones on its sides.
	for (size_t d = 0; d < doors.size(); d++) {
		const std::vector<uint16_t> zs = touched(doors[d], zone);
		block.portals[d].zone_a = zs.size() > 0 ? zs[0] : 0;
		block.portals[d].zone_b = zs.size() > 1 ? zs[1] : 0;
	}
	for (int64_t i = 0; i < CELL_AREA; i++) {
		cell.tiles[static_cast<size_t>(i)].zone = zone[static_cast<size_t>(i)];
	}
	cell.road_graph = lb::core::sound::encode_block(block);
}

void cut_collapses(Cell &cell, uint8_t room_kind, bool base_camp) {
	const std::optional<CellBlock> standing = lb::core::sound::decode_block(cell.road_graph);
	if (!standing) {
		return;
	}
	uint16_t max_zone = 0;
	uint16_t max_portal = 0;
	std::map<uint16_t, ZoneKind> standing_kind;
	std::map<std::vector<uint16_t>, uint16_t> standing_portal; // tiles -> id
	for (const ZoneDecl &z : standing->zones) {
		max_zone = std::max(max_zone, z.id);
		standing_kind[z.id] = z.kind;
	}
	for (const PortalDecl &p : standing->portals) {
		max_portal = std::max(max_portal, p.id);
		standing_portal[p.tiles] = p.id;
	}
	for (auto &col : cell.collapses) {
		Cell fallen = cell;
		for (const auto &w : col.fallen) {
			fallen.tiles[w.index].material = w.material;
		}
		fallen.collapses.clear();
		cut_zones(fallen, room_kind, base_camp);
		CellBlock fb = *lb::core::sound::decode_block(fallen.road_graph);
		std::map<uint16_t, ZoneKind> fallen_kind;
		for (const ZoneDecl &z : fb.zones) {
			fallen_kind[z.id] = z.kind;
		}
		// Stable ids: each fallen zone keeps the id of the standing zone it overlaps most (largest
		// overlaps first, so a split road's bigger piece keeps it); the rest take fresh ids. An
		// opening keeps its id where its tiles are unchanged.
		std::map<std::pair<uint16_t, uint16_t>, int32_t> overlap;
		for (int64_t i = 0; i < CELL_AREA; i++) {
			const uint16_t f = fallen.tiles[static_cast<size_t>(i)].zone;
			const uint16_t s = cell.tiles[static_cast<size_t>(i)].zone;
			if (f != 0 && s != 0 && fallen_kind[f] == standing_kind[s]) {
				overlap[{f, s}]++;
			}
		}
		std::vector<std::tuple<int32_t, uint16_t, uint16_t>> order;
		for (const auto &[fs, n] : overlap) {
			order.emplace_back(-n, fs.first, fs.second);
		}
		std::sort(order.begin(), order.end());
		std::map<uint16_t, uint16_t> zmap;
		std::set<uint16_t> taken;
		for (const auto &[n, f, s] : order) {
			if (zmap.count(f) == 0 && taken.count(s) == 0) {
				zmap[f] = s;
				taken.insert(s);
			}
		}
		uint16_t next_zone = static_cast<uint16_t>(max_zone + 1);
		for (const ZoneDecl &z : fb.zones) {
			if (zmap.count(z.id) == 0) {
				zmap[z.id] = next_zone++;
			}
		}
		uint16_t next_portal = static_cast<uint16_t>(max_portal + 1);
		for (ZoneDecl &z : fb.zones) {
			z.id = zmap[z.id];
		}
		for (PortalDecl &p : fb.portals) {
			auto same = standing_portal.find(p.tiles);
			p.id = same != standing_portal.end() ? same->second : next_portal++;
			p.zone_a = p.zone_a != 0 ? zmap[p.zone_a] : 0;
			p.zone_b = p.zone_b != 0 ? zmap[p.zone_b] : 0;
		}
		std::sort(fb.zones.begin(), fb.zones.end(), [](const ZoneDecl &a, const ZoneDecl &b) { return a.id < b.id; });
		std::sort(fb.portals.begin(), fb.portals.end(), [](const PortalDecl &a, const PortalDecl &b) { return a.id < b.id; });
		// The writes: each walkable tile whose zone differs (a fallen tile keeps its id, unwalked).
		col.zones.clear();
		for (int64_t i = 0; i < CELL_AREA; i++) {
			const uint16_t f = fallen.tiles[static_cast<size_t>(i)].zone;
			const uint16_t now = f != 0 ? zmap[f] : 0;
			const uint16_t was = cell.tiles[static_cast<size_t>(i)].zone;
			if (is_floor(fallen, i) && now != was) {
				col.zones.push_back(ZoneWrite{static_cast<uint16_t>(i), was, now});
			}
		}
		col.fallen_road_graph = lb::core::sound::encode_block(fb);
	}
}

} // namespace lb::core::gen

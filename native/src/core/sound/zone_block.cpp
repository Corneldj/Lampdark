#include "core/sound/zone_block.h"

#include <set>

namespace lb::core::sound {

namespace {

struct Writer {
	std::vector<uint8_t> out;
	void u8(uint64_t v) { out.push_back(static_cast<uint8_t>(v)); }
	void u16(uint64_t v) { u8(v); u8(v >> 8); }
	void u32(uint64_t v) { u16(v); u16(v >> 16); }
};

struct Reader {
	const std::vector<uint8_t> &in;
	size_t at = 0;
	bool ok = true;
	uint64_t u8() {
		if (at >= in.size()) {
			ok = false;
			return 0;
		}
		return in[at++];
	}
	uint64_t u16() { const uint64_t lo = u8(); return lo | (u8() << 8); }
	uint64_t u32() { const uint64_t lo = u16(); return lo | (u16() << 16); }
};

} // namespace

std::vector<uint8_t> encode_block(const CellBlock &block) {
	Writer w;
	w.u8(BLOCK_VERSION);
	w.u16(block.zones.size());
	for (const ZoneDecl &z : block.zones) {
		w.u16(z.id);
		w.u8(static_cast<uint8_t>(z.kind));
	}
	w.u16(block.portals.size());
	for (const PortalDecl &p : block.portals) {
		w.u16(p.id);
		w.u8(static_cast<uint8_t>(p.kind));
		w.u16(p.zone_a);
		w.u16(p.zone_b);
		w.u32(p.barrier);
		w.u16(p.tiles.size());
		for (uint16_t t : p.tiles) {
			w.u16(t);
		}
	}
	return w.out;
}

std::optional<CellBlock> decode_block(const std::vector<uint8_t> &bytes) {
	if (bytes.empty()) {
		return CellBlock{};
	}
	Reader r{bytes};
	if (r.u8() != BLOCK_VERSION) {
		return std::nullopt;
	}
	CellBlock block;
	const uint64_t zones = r.u16();
	for (uint64_t i = 0; i < zones && r.ok; i++) {
		ZoneDecl z;
		z.id = static_cast<uint16_t>(r.u16());
		const uint64_t kind = r.u8();
		if (kind >= static_cast<uint64_t>(ZoneKind::COUNT)) {
			return std::nullopt;
		}
		z.kind = static_cast<ZoneKind>(kind);
		block.zones.push_back(z);
	}
	const uint64_t portals = r.u16();
	for (uint64_t i = 0; i < portals && r.ok; i++) {
		PortalDecl p;
		p.id = static_cast<uint16_t>(r.u16());
		const uint64_t kind = r.u8();
		if (kind >= static_cast<uint64_t>(PortalKind::COUNT)) {
			return std::nullopt;
		}
		p.kind = static_cast<PortalKind>(kind);
		p.zone_a = static_cast<uint16_t>(r.u16());
		p.zone_b = static_cast<uint16_t>(r.u16());
		p.barrier = static_cast<uint32_t>(r.u32());
		const uint64_t n = r.u16();
		for (uint64_t t = 0; t < n && r.ok; t++) {
			p.tiles.push_back(static_cast<uint16_t>(r.u16()));
		}
		block.portals.push_back(std::move(p));
	}
	if (!r.ok || r.at != bytes.size()) {
		return std::nullopt;
	}
	return block;
}

std::vector<std::string> validate_block(const lb::core::world::Cell &cell, const CellBlock &block) {
	using namespace lb::core::world;
	std::vector<std::string> problems;
	std::set<uint16_t> zone_ids;
	for (const ZoneDecl &z : block.zones) {
		if (z.id == 0 || !zone_ids.insert(z.id).second) {
			problems.push_back("zone id " + std::to_string(z.id) + " is 0 or repeated");
		}
	}
	std::set<uint16_t> portal_tiles;
	std::set<uint16_t> portal_ids;
	for (const PortalDecl &p : block.portals) {
		if (!portal_ids.insert(p.id).second) {
			problems.push_back("portal id " + std::to_string(p.id) + " repeated");
		}
		if (zone_ids.count(p.zone_a) == 0 || zone_ids.count(p.zone_b) == 0 || p.zone_a == p.zone_b) {
			problems.push_back("portal " + std::to_string(p.id) + " does not join two declared zones");
		}
		if (p.tiles.empty()) {
			problems.push_back("portal " + std::to_string(p.id) + " has no tiles");
		}
		for (uint16_t t : p.tiles) {
			if (t >= CELL_AREA || !portal_tiles.insert(t).second) {
				problems.push_back("portal " + std::to_string(p.id) + " tile " + std::to_string(t) + " is out of range or shared");
			}
		}
		if (p.barrier != 0) {
			bool found = false;
			for (const Barrier &b : cell.barriers) {
				if (b.id == p.barrier) {
					found = std::set<uint16_t>(b.tiles.begin(), b.tiles.end()) == std::set<uint16_t>(p.tiles.begin(), p.tiles.end());
				}
			}
			if (!found) {
				problems.push_back("portal " + std::to_string(p.id) + " does not cover barrier " + std::to_string(p.barrier) + "'s tiles");
			}
		}
	}
	const MaterialTable materials = MaterialTable::defaults();
	for (int64_t i = 0; i < CELL_AREA; i++) {
		const Tile &t = cell.tiles[static_cast<size_t>(i)];
		const TileMaterial m = static_cast<TileMaterial>(t.material);
		const bool barrier_tile = m == TileMaterial::STEEL || m == TileMaterial::WOODEN_DOOR;
		const bool walkable = !materials.get(m).solid || barrier_tile;
		const bool on_portal = portal_tiles.count(static_cast<uint16_t>(i)) != 0;
		if (on_portal) {
			if (t.zone != 0) {
				problems.push_back("portal tile " + std::to_string(i) + " also has zone " + std::to_string(t.zone));
			}
			continue;
		}
		if (walkable && (t.zone == 0 || zone_ids.count(t.zone) == 0)) {
			problems.push_back("walkable tile (" + std::to_string(i % CELL_TILES) + ", " + std::to_string(i / CELL_TILES) + ") is in no declared zone");
		}
		// A solid tile may keep its zone id: a fallen collapse alternate leaves it there.
	}
	return problems;
}

} // namespace lb::core::sound

#include "core/world/cell.h"

#include "core/generated/hash_domains.h"
#include "core/rng/hash.h"

namespace lb::core::world {

namespace {

struct Bytes {
	std::vector<uint8_t> data;
	void u8(uint64_t v) { data.push_back(static_cast<uint8_t>(v)); }
	void u32(uint64_t v) {
		for (int i = 0; i < 4; i++) {
			data.push_back(static_cast<uint8_t>(v >> (8 * i)));
		}
	}
	void str(const std::string &s) {
		u32(s.size());
		data.insert(data.end(), s.begin(), s.end());
	}
};

} // namespace

uint64_t content_digest(const Cell &cell) {
	Bytes b;
	b.u32(static_cast<uint64_t>(cell.coord.x));
	b.u32(static_cast<uint64_t>(cell.coord.y));
	for (const Tile &t : cell.tiles) {
		b.u8(t.material);
		b.u8(t.state);
		b.u8(t.zone);
		b.u8(t.zone >> 8);
	}
	b.u32(cell.anchors.size());
	for (const Anchor &a : cell.anchors) {
		b.u8(static_cast<uint8_t>(a.type));
		b.u32(static_cast<uint64_t>(a.x));
		b.u32(static_cast<uint64_t>(a.y));
		b.u32(static_cast<uint64_t>(a.w));
		b.u32(static_cast<uint64_t>(a.h));
		b.u32(a.tags.size());
		for (const std::string &tag : a.tags) {
			b.str(tag);
		}
		b.str(a.kind);
	}
	b.u32(cell.barriers.size());
	for (const Barrier &bar : cell.barriers) {
		b.u32(bar.id);
		b.u32(bar.portal);
		b.u8(bar.open ? 1 : 0);
		b.u32(bar.tiles.size());
		for (uint16_t i : bar.tiles) {
			b.u32(i);
		}
	}
	b.u32(cell.collapses.size());
	for (const Collapse &c : cell.collapses) {
		b.u32(c.id);
		b.u8(c.is_fallen ? 1 : 0);
		for (const std::vector<TileWrite> *set : {&c.standing, &c.fallen}) {
			b.u32(set->size());
			for (const TileWrite &w : *set) {
				b.u32(w.index);
				b.u8(w.material);
			}
		}
	}
	b.u32(cell.road_graph.size());
	b.data.insert(b.data.end(), cell.road_graph.begin(), cell.road_graph.end());
	// Fold the bytes into 64-bit keys for FND-06's keyed hash.
	std::vector<int64_t> keys((b.data.size() + 7) / 8 + 1, 0);
	keys[0] = static_cast<int64_t>(b.data.size());
	for (size_t i = 0; i < b.data.size(); i++) {
		keys[1 + i / 8] = static_cast<int64_t>(static_cast<uint64_t>(keys[1 + i / 8]) | (uint64_t{b.data[i]} << (8 * (i % 8))));
	}
	return hash_u64(0, hash_domain::GEN_CELL_DIGEST, keys.data(), keys.size());
}

} // namespace lb::core::world

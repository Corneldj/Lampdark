#include "core/gen/template.h"

#include <cstring>

namespace lb::core::gen {

using lb::core::world::Anchor;
using lb::core::world::AnchorType;
using lb::core::world::Barrier;
using lb::core::world::Cell;
using lb::core::world::CELL_AREA;
using lb::core::world::Collapse;
using lb::core::world::TileWrite;
using lb::core::world::ZoneWrite;

namespace {

struct W {
	std::vector<uint8_t> &d;
	void u8(uint64_t v) { d.push_back(static_cast<uint8_t>(v)); }
	void u16(uint64_t v) {
		u8(v);
		u8(v >> 8);
	}
	void u32(uint64_t v) {
		for (int i = 0; i < 4; i++) {
			u8(v >> (8 * i));
		}
	}
	void u64(uint64_t v) {
		u32(v);
		u32(v >> 32);
	}
	void str(const std::string &s) {
		u16(s.size());
		d.insert(d.end(), s.begin(), s.end());
	}
	void bytes(const std::vector<uint8_t> &b) {
		u32(b.size());
		d.insert(d.end(), b.begin(), b.end());
	}
};

struct R {
	const std::vector<uint8_t> &d;
	size_t &at;
	bool ok = true;
	bool need(size_t n) {
		if (at + n > d.size()) {
			ok = false;
		}
		return ok;
	}
	uint64_t u8() { return need(1) ? d[at++] : 0; }
	uint64_t u16() {
		const uint64_t lo = u8();
		return lo | (u8() << 8);
	}
	uint64_t u32() {
		uint64_t v = 0;
		for (int i = 0; i < 4; i++) {
			v |= u8() << (8 * i);
		}
		return v;
	}
	uint64_t u64() {
		const uint64_t lo = u32();
		return lo | (u32() << 32);
	}
	std::string str() {
		const size_t n = u16();
		if (!need(n)) {
			return {};
		}
		std::string s(d.begin() + static_cast<std::ptrdiff_t>(at), d.begin() + static_cast<std::ptrdiff_t>(at + n));
		at += n;
		return s;
	}
	std::vector<uint8_t> bytes() {
		const size_t n = u32();
		if (!need(n)) {
			return {};
		}
		std::vector<uint8_t> b(d.begin() + static_cast<std::ptrdiff_t>(at), d.begin() + static_cast<std::ptrdiff_t>(at + n));
		at += n;
		return b;
	}
};

const uint8_t MAGIC[4] = {'L', 'B', 'T', 'P'};

} // namespace

void encode_cell(std::vector<uint8_t> &out, const Cell &cell) {
	W w{out};
	w.u32(static_cast<uint64_t>(cell.coord.x));
	w.u32(static_cast<uint64_t>(cell.coord.y));
	for (const auto &t : cell.tiles) {
		w.u8(t.material);
		w.u8(t.state);
		w.u16(t.zone);
	}
	w.u16(cell.anchors.size());
	for (const Anchor &a : cell.anchors) {
		w.u8(static_cast<uint8_t>(a.type));
		w.u32(static_cast<uint64_t>(a.x));
		w.u32(static_cast<uint64_t>(a.y));
		w.u32(static_cast<uint64_t>(a.w));
		w.u32(static_cast<uint64_t>(a.h));
		w.u16(a.tags.size());
		for (const std::string &tag : a.tags) {
			w.str(tag);
		}
		w.str(a.kind);
	}
	w.u16(cell.barriers.size());
	for (const Barrier &b : cell.barriers) {
		w.u32(b.id);
		w.u32(b.portal);
		w.u8(b.open ? 1 : 0);
		w.u16(b.tiles.size());
		for (uint16_t i : b.tiles) {
			w.u16(i);
		}
	}
	w.u16(cell.collapses.size());
	for (const Collapse &c : cell.collapses) {
		w.u32(c.id);
		w.u8(c.is_fallen ? 1 : 0);
		for (const std::vector<TileWrite> *set : {&c.standing, &c.fallen}) {
			w.u16(set->size());
			for (const TileWrite &t : *set) {
				w.u16(t.index);
				w.u8(t.material);
			}
		}
		w.u16(c.zones.size());
		for (const ZoneWrite &z : c.zones) {
			w.u16(z.index);
			w.u16(z.standing);
			w.u16(z.fallen);
		}
		w.bytes(c.fallen_road_graph);
	}
	w.bytes(cell.road_graph);
}

bool decode_cell(const std::vector<uint8_t> &in, size_t &at, Cell &cell) {
	R r{in, at};
	cell.coord.x = static_cast<int32_t>(static_cast<uint32_t>(r.u32()));
	cell.coord.y = static_cast<int32_t>(static_cast<uint32_t>(r.u32()));
	for (auto &t : cell.tiles) {
		t.material = static_cast<uint8_t>(r.u8());
		t.state = static_cast<uint8_t>(r.u8());
		t.zone = static_cast<uint16_t>(r.u16());
	}
	cell.anchors.resize(r.u16());
	for (Anchor &a : cell.anchors) {
		a.type = static_cast<AnchorType>(r.u8());
		a.x = static_cast<int32_t>(static_cast<uint32_t>(r.u32()));
		a.y = static_cast<int32_t>(static_cast<uint32_t>(r.u32()));
		a.w = static_cast<int32_t>(static_cast<uint32_t>(r.u32()));
		a.h = static_cast<int32_t>(static_cast<uint32_t>(r.u32()));
		a.tags.resize(r.u16());
		for (std::string &tag : a.tags) {
			tag = r.str();
		}
		a.kind = r.str();
	}
	cell.barriers.resize(r.u16());
	for (Barrier &b : cell.barriers) {
		b.id = static_cast<uint32_t>(r.u32());
		b.portal = static_cast<uint32_t>(r.u32());
		b.open = r.u8() != 0;
		b.tiles.resize(r.u16());
		for (uint16_t &i : b.tiles) {
			i = static_cast<uint16_t>(r.u16());
		}
	}
	cell.collapses.resize(r.u16());
	for (Collapse &c : cell.collapses) {
		c.id = static_cast<uint32_t>(r.u32());
		c.is_fallen = r.u8() != 0;
		for (std::vector<TileWrite> *set : {&c.standing, &c.fallen}) {
			set->resize(r.u16());
			for (TileWrite &t : *set) {
				t.index = static_cast<uint16_t>(r.u16());
				t.material = static_cast<uint8_t>(r.u8());
			}
		}
		c.zones.resize(r.u16());
		for (ZoneWrite &z : c.zones) {
			z.index = static_cast<uint16_t>(r.u16());
			z.standing = static_cast<uint16_t>(r.u16());
			z.fallen = static_cast<uint16_t>(r.u16());
		}
		c.fallen_road_graph = r.bytes();
	}
	cell.road_graph = r.bytes();
	return r.ok;
}

std::vector<uint8_t> encode_pack(const std::string &set_version, const std::vector<Template> &templates) {
	std::vector<uint8_t> out(MAGIC, MAGIC + 4);
	W w{out};
	w.u16(PACK_FORMAT);
	w.str(set_version);
	w.u32(templates.size());
	for (const Template &t : templates) {
		w.str(t.id);
		w.u8(static_cast<uint8_t>(t.kind));
		w.str(t.biome);
		w.u8(static_cast<uint64_t>(t.footprint_w));
		w.u8(static_cast<uint64_t>(t.footprint_h));
		w.str(t.poi_kind);
		uint64_t bits = 0;
		std::memcpy(&bits, &t.weight, sizeof bits);
		w.u64(bits);
		w.u32(t.author_version);
		w.u16(t.stubs.size());
		for (const Stub &s : t.stubs) {
			w.u8(static_cast<uint64_t>(s.cell.x));
			w.u8(static_cast<uint64_t>(s.cell.y));
			w.u8(static_cast<uint8_t>(s.edge));
			w.u8(static_cast<uint64_t>(s.offset));
			w.u8(static_cast<uint64_t>(s.max_width));
			w.u8(static_cast<uint64_t>(s.depth));
			w.u8(s.door ? 1 : 0);
		}
		w.u32(t.rib.size());
		for (const RibOffset &rb : t.rib) {
			w.u8(static_cast<uint64_t>(rb.cell.x));
			w.u8(static_cast<uint64_t>(rb.cell.y));
			w.u16(rb.index);
			w.u32(rb.milli);
		}
		w.u8(t.cells.size());
		for (const Cell &c : t.cells) {
			encode_cell(out, c);
		}
	}
	return out;
}

std::optional<Pack> decode_pack(const std::vector<uint8_t> &bytes) {
	if (bytes.size() < 4 || std::memcmp(bytes.data(), MAGIC, 4) != 0) {
		return std::nullopt;
	}
	size_t at = 4;
	R r{bytes, at};
	if (r.u16() != PACK_FORMAT) {
		return std::nullopt;
	}
	Pack pack;
	pack.set_version = r.str();
	const size_t count = r.u32();
	if (!r.ok || count > 100000) {
		return std::nullopt;
	}
	pack.templates.resize(count);
	for (Template &t : pack.templates) {
		t.id = r.str();
		const uint64_t kind = r.u8();
		if (kind >= static_cast<uint64_t>(TemplateKind::COUNT)) {
			return std::nullopt;
		}
		t.kind = static_cast<TemplateKind>(kind);
		t.biome = r.str();
		t.footprint_w = static_cast<int32_t>(r.u8());
		t.footprint_h = static_cast<int32_t>(r.u8());
		t.poi_kind = r.str();
		const uint64_t bits = r.u64();
		std::memcpy(&t.weight, &bits, sizeof bits);
		t.author_version = static_cast<uint32_t>(r.u32());
		t.stubs.resize(r.u16());
		for (Stub &s : t.stubs) {
			s.cell.x = static_cast<int64_t>(r.u8());
			s.cell.y = static_cast<int64_t>(r.u8());
			s.edge = static_cast<Edge>(r.u8());
			s.offset = static_cast<int32_t>(r.u8());
			s.max_width = static_cast<int32_t>(r.u8());
			s.depth = static_cast<int32_t>(r.u8());
			s.door = r.u8() != 0;
		}
		t.rib.resize(r.u32());
		for (RibOffset &rb : t.rib) {
			rb.cell.x = static_cast<int64_t>(r.u8());
			rb.cell.y = static_cast<int64_t>(r.u8());
			rb.index = static_cast<uint16_t>(r.u16());
			rb.milli = static_cast<uint32_t>(r.u32());
		}
		t.cells.resize(r.u8());
		for (Cell &c : t.cells) {
			if (!r.ok || !decode_cell(bytes, at, c)) {
				return std::nullopt;
			}
		}
		if (!r.ok) {
			return std::nullopt;
		}
	}
	if (!r.ok || at != bytes.size()) {
		return std::nullopt;
	}
	return pack;
}

} // namespace lb::core::gen

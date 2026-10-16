#pragma once
// GEN-04's template fixtures: a biome cell that passes every rule, a point of interest and a plain
// fallback, each built from ASCII rows (mine_fixture's characters) and cut by the zone cutter.
// The failing fixtures in test_template_validate.cpp are small edits of these.

#include "core/gen/template.h"
#include "core/sound/zone_block.h"
#include "mine_fixture.h"

#include <string>
#include <vector>

namespace template_fixture {

using namespace lb::core::gen;
using namespace lb::core::world;

// A 3-wide road west to east (a stub at each end), a 1-wide road north to a stub with a collapse
// on it, a spur south to a dead end, and a 6x6 chamber off the road through a 1-wide mouth.
inline std::vector<std::string> base_rows() {
	return {
			"##########.#########", // 0
			"##########.#########", // 1
			"##########.#########", // 2
			"##########.#########", // 3
			"##########.#########", // 4
			"##########.#########", // 5
			"##########.#########", // 6
			"##########.#########", // 7
			"##########.#########", // 8
			"....................", // 9
			"....................", // 10
			"....................", // 11
			"##########.####.####", // 12
			"#######......##.####", // 13
			"#######......##.####", // 14
			"#######......##.####", // 15
			"#######......#######", // 16
			"#######......#######", // 17
			"#######......#######", // 18
			"####################", // 19
	};
}

inline Anchor anchor(AnchorType type, int32_t x, int32_t y, int32_t w = 1, int32_t h = 1, const std::string &kind = "") {
	Anchor a;
	a.type = type;
	a.x = x;
	a.y = y;
	a.w = w;
	a.h = h;
	a.kind = kind;
	return a;
}

inline std::vector<Anchor> base_anchors() {
	return {
			anchor(AnchorType::CHAMBER, 7, 13, 6, 6),
			anchor(AnchorType::TIMBER_HOOK, 2, 10),
			anchor(AnchorType::TIMBER_HOOK, 7, 10),
			anchor(AnchorType::TIMBER_HOOK, 12, 10),
			anchor(AnchorType::TIMBER_HOOK, 17, 10),
			anchor(AnchorType::TIMBER_HOOK, 10, 4),
			anchor(AnchorType::TIMBER_HOOK, 15, 13),
			anchor(AnchorType::TIMBER_HOOK, 8, 14),
			anchor(AnchorType::LANDMARK, 5, 9, 1, 1, "broken_tub"),
			anchor(AnchorType::RUBBLE_HEAP, 14, 11),
			anchor(AnchorType::RICH_ROCK, 2, 1, 4, 4),
			anchor(AnchorType::WALL_FIXTURE, 9, 12),
			anchor(AnchorType::REMAINS, 15, 15),
			anchor(AnchorType::DOOR_SITE, 10, 12),
			anchor(AnchorType::GAS_AREA, 7, 13, 6, 6),
			anchor(AnchorType::GAS_DEAD_END, 15, 12, 1, 4),
	};
}

// Rock across `tiles` (local x, y) when fallen.
inline Collapse collapse(uint32_t id, const std::vector<std::pair<int, int>> &tiles) {
	Collapse c;
	c.id = id;
	for (const auto &[x, y] : tiles) {
		const uint16_t i = static_cast<uint16_t>(Cell::index_of(x, y));
		c.standing.push_back({i, static_cast<uint8_t>(TileMaterial::FLOOR)});
		c.fallen.push_back({i, static_cast<uint8_t>(TileMaterial::ROCK)});
	}
	return c;
}

inline Stub stub(Edge edge, int32_t offset, int32_t width, int32_t depth = 2, bool door = false, Coord cell = {0, 0}) {
	Stub s;
	s.cell = cell;
	s.edge = edge;
	s.offset = offset;
	s.max_width = width;
	s.depth = depth;
	s.door = door;
	return s;
}

struct Spec {
	std::string id = "fixture_seam_01";
	TemplateKind kind = TemplateKind::BIOME_CELL;
	std::string poi_kind;
	std::vector<std::string> rows = base_rows();
	std::vector<Anchor> anchors = base_anchors();
	std::vector<Collapse> collapses = {collapse(1, {{10, 5}})};
	std::vector<Stub> stubs = {stub(Edge::WEST, 10, 3), stub(Edge::EAST, 10, 3), stub(Edge::NORTH, 10, 1)};
	std::vector<RibOffset> rib = {RibOffset{{0, 0}, static_cast<uint16_t>(Cell::index_of(6, 13)), 200}};
	bool cut = true;
};

inline uint8_t room_kind(TemplateKind kind) {
	return static_cast<uint8_t>(kind == TemplateKind::POI ? lb::core::sound::ZoneKind::POI : lb::core::sound::ZoneKind::CHAMBER);
}

inline Cell cell_of(const Spec &s, Coord coord = {0, 0}) {
	auto cell = mine_fixture::cell_from(coord, s.rows);
	cell->anchors = s.anchors;
	cell->collapses = s.collapses;
	if (s.cut) {
		cut_zones(*cell, room_kind(s.kind), s.kind == TemplateKind::BASE_CAMP);
		cut_collapses(*cell, room_kind(s.kind), s.kind == TemplateKind::BASE_CAMP);
	}
	return *cell;
}

inline Template make(const Spec &s) {
	Template t;
	t.id = s.id;
	t.kind = s.kind;
	t.biome = "seam";
	t.poi_kind = s.poi_kind;
	t.cells.push_back(cell_of(s));
	t.stubs = s.stubs;
	t.rib = s.rib;
	return t;
}

// A pump room: a door stub north into a 6x6 room with two contents slots and a phone.
inline Spec poi_spec() {
	Spec s;
	s.id = "fixture_pump_room";
	s.kind = TemplateKind::POI;
	s.poi_kind = "pump_room";
	s.rows = {
			"##########.#########",
			"##########.#########",
			"##########.#########",
			"#######......#######",
			"#######......#######",
			"#######......#######",
			"#######......#######",
			"#######......#######",
			"#######......#######",
	};
	s.anchors = {
			anchor(AnchorType::CHAMBER, 7, 3, 6, 6),
			anchor(AnchorType::TIMBER_HOOK, 10, 4),
			anchor(AnchorType::POI_SLOT, 8, 5, 1, 1, "pump_room"),
			anchor(AnchorType::POI_SLOT, 11, 7, 1, 1, "pump_room"),
			anchor(AnchorType::WALL_FIXTURE, 6, 4, 1, 1, "phone"),
	};
	s.collapses = {};
	s.stubs = {stub(Edge::NORTH, 10, 1, 2, true)};
	s.rib = {};
	return s;
}

inline ValidateParams poi_params() {
	ValidateParams p;
	p.poi_slots["pump_room"] = 2;
	p.poi_phone_kinds.insert("pump_room");
	return p;
}

// A plain fallback: 3-wide roads on every stub line (offsets 5, 10 and 15 both ways), a stub at
// all 12 edge positions at width 3.
inline Spec fallback_spec() {
	Spec s;
	s.id = "fixture_seam_fallback";
	s.kind = TemplateKind::FALLBACK;
	const std::string open_row(20, '.');
	const std::string col_row = "####...##...##...###";
	s.rows.clear();
	for (int y = 0; y < 20; y++) {
		const bool row = (y >= 4 && y <= 6) || (y >= 9 && y <= 11) || (y >= 14 && y <= 16);
		s.rows.push_back(row ? open_row : col_row);
	}
	s.anchors = {anchor(AnchorType::LANDMARK, 2, 5, 1, 1, "chalk"), anchor(AnchorType::RUBBLE_HEAP, 8, 5)};
	for (int a : {5, 10, 15}) {
		for (int b : {5, 10, 15}) {
			s.anchors.push_back(anchor(AnchorType::TIMBER_HOOK, a, b));
		}
		s.anchors.push_back(anchor(AnchorType::TIMBER_HOOK, 1, a));
		s.anchors.push_back(anchor(AnchorType::TIMBER_HOOK, 18, a));
		s.anchors.push_back(anchor(AnchorType::TIMBER_HOOK, a, 1));
		s.anchors.push_back(anchor(AnchorType::TIMBER_HOOK, a, 18));
	}
	s.collapses = {};
	s.stubs.clear();
	for (Edge e : {Edge::NORTH, Edge::EAST, Edge::SOUTH, Edge::WEST}) {
		for (int offset : {5, 10, 15}) {
			s.stubs.push_back(stub(e, offset, 3));
		}
	}
	s.rib = {};
	return s;
}

} // namespace template_fixture

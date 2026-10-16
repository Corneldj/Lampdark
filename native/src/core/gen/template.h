#pragma once
// GEN-04's cell templates (Gameplay §12.3, GDD §15.4): hand-made one- to four-cell layouts the
// generator stitches into the mine. A template is GEN-01 cells (tiles, zones, typed anchors,
// barriers, collapse alternates with their pre-cut fallen zones and Road Graph blocks) plus its
// stubs, its rib art and its metadata. The validator (one implementation for the editor, the
// exporter, GEN-12 and GEN-14) and the packed binary the server loads live here. Server-only.

#include "core/world/cell.h"

#include <cstdint>
#include <map>
#include <optional>
#include <set>
#include <string>
#include <vector>

namespace lb::core::gen {

enum class TemplateKind : uint8_t { BIOME_CELL,
	MAIN_ROAD,
	POI,
	FALLBACK,
	BASE_CAMP,
	COUNT };
enum class Edge : uint8_t { NORTH,
	EAST,
	SOUTH,
	WEST,
	COUNT };

// An opening on the footprint's outer edge: at `offset` tiles along its edge (5, 10 or 15), at most
// `max_width` wide (1-3), its throat `depth` tiles deep. The generator narrows the throat to the
// socket's width or fills it with rock (a blind heading).
struct Stub {
	lb::core::world::Coord cell; // within the footprint
	Edge edge = Edge::NORTH;
	int32_t offset = 10;
	int32_t max_width = 3;
	int32_t depth = 2;
	bool door = false; // a point of interest's door
};

// A rib edge's art offset (thousandths of a tile), on a solid tile beside floor.
struct RibOffset {
	lb::core::world::Coord cell;
	uint16_t index = 0;
	uint32_t milli = 0;
};

struct Template {
	std::string id;
	TemplateKind kind = TemplateKind::BIOME_CELL;
	std::string biome;
	int32_t footprint_w = 1;
	int32_t footprint_h = 1;
	std::string poi_kind;
	// GEN-07: a main-road template's shape, drawn east to west: "straight", "bend_5", "bend_10",
	// "bend_15" or "crossing"; old_fall for a straight road choked at its middle.
	std::string shape;
	bool old_fall = false;
	double weight = 1.0;
	uint32_t author_version = 1;
	std::vector<lb::core::world::Cell> cells; // coords (0, 0) .. (w - 1, h - 1)
	std::vector<Stub> stubs;
	std::vector<RibOffset> rib;
};

// The numbers the rules read (tuning, GEN-06's biome table and GEN-09's contents table).
struct ValidateParams {
	int32_t road_width_min = 1;
	int32_t road_width_max = 3;
	int32_t chamber_min = 5;
	int32_t chamber_max = 8;
	int32_t chamber_forbidden_width = 4;
	uint32_t rib_wander_max_milli = 250;
	uint32_t tapper_reach_milli = 1500;
	int32_t hook_reach_tiles = 4;
	int32_t rubble_min = 1;
	int32_t rubble_max = 2;
	int32_t rich_rock_min_thickness = 4;
	int32_t gas_area_min = 3;
	int32_t gas_area_max = 8;
	int32_t gas_dead_end_min = 3;
	int32_t gas_dead_end_max = 6;
	int32_t collapse_length_max = 3;
	int32_t biome_stub_width_max = 3; // GEN-06's per-biome maximum, until it lands
	std::map<std::string, int32_t> poi_slots; // point-of-interest kind -> contents lines (GEN-09)
	std::set<std::string> poi_phone_kinds; // kinds with a pit phone (LFT-12)
	std::string lair_kind = "lair";
	int32_t main_road_width = 3; // mine.main_road_width_tiles (GEN-07)
	int32_t main_road_offset = 10; // mine.main_road_edge_offset_tiles
	int32_t bend_reach = 2; // mine.main_road_bend_reach_tiles: no sight line spans the bend +/- this
};

struct Problem {
	std::string rule;
	lb::core::world::Coord cell;
	int32_t x = -1; // local tile, -1 for none
	int32_t y = -1;
	std::string message;
};

const char *kind_name(TemplateKind k);
std::optional<TemplateKind> kind_from(const std::string &name);

// Every rule's problems, in rule order (empty: valid).
std::vector<Problem> validate(const Template &t, const ValidateParams &p);
std::string describe(const Template &t, const Problem &problem); // "template <id>: <rule>: cell (x, y) tile (x, y): ..."

// GEN-07: a one-cell template turned about its main diagonal ((x, y) -> (y, x)): tiles, anchors,
// barriers, collapses and rib art; north stubs become west ones and south east ones at the same
// offsets, so an east-west main road serves north-south lines. Zones and portals are cut again.
Template transpose(const Template &t);

// The throat tiles of a stub at `width`, as footprint-global tiles: along its edge from
// offset - floor(width / 2) (GEN-05's opening rule), `depth` tiles in.
std::vector<lb::core::world::Coord> throat(const Template &t, const Stub &s, int32_t width);

// GEN-04's zone cutter, the grey box's rule (GEN-03) generalised, so templates carry pre-cut zones:
//  - each chamber anchor's floor is a zone (`room` kind: chamber, or poi in a point of interest);
//  - each 4-connected run of floor outside a chamber that touches it is an opening portal to the
//    zone on its other side;
//  - each remaining 4-connected floor region is a road zone (base_camp in base camp);
//  - each 4-connected run of door or gate tiles is a barrier and its air_door or gate portal.
// Barrier portals are numbered first, so they keep their ids in every collapse's fallen cut.
// Rewrites the cell's tile zones, barriers and Road Graph block.
void cut_zones(lb::core::world::Cell &cell, uint8_t room_kind, bool base_camp);
// Each collapse alternate's fallen state cut the same way: its changed tiles' zones and the cell's
// whole block with that collapse fallen (the others standing).
void cut_collapses(lb::core::world::Cell &cell, uint8_t room_kind, bool base_camp);

// The packed binary (data/templates/packs/<set_version>.lbtp): "LBTP", u16 format, the set
// version, then each template with its cells. Little-endian, canonical.
constexpr uint16_t PACK_FORMAT = 2; // 2 adds GEN-07's shape and old_fall; format 1 packs still load
std::vector<uint8_t> encode_pack(const std::string &set_version, const std::vector<Template> &templates);
struct Pack {
	std::string set_version;
	std::vector<Template> templates;
};
std::optional<Pack> decode_pack(const std::vector<uint8_t> &bytes);

// A cell's canonical bytes and back (the pack's cell record).
void encode_cell(std::vector<uint8_t> &out, const lb::core::world::Cell &cell);
bool decode_cell(const std::vector<uint8_t> &in, size_t &at, lb::core::world::Cell &cell);

} // namespace lb::core::gen

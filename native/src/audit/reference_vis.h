#pragma once
// NET-08's reference visibility: an independent recomputation of what a miner may perceive, for
// the stream audit. It shares no code with VIS-02 (light), VIS-03 (seen sets) or VIS-04 (margin):
// only the design's definitions, the tuning values and the mine's geometry (through the opacity
// callbacks) are common. Written from the definitions, not the production source:
//   - line of sight: Albert Ford's symmetric shadowcasting (recursive, exact fractions), to 40 tiles;
//   - light: every source's falloff (peak, to 0.30 at 0.6 R, to 0.12 at R), summed and capped,
//     shadowed by the same symmetric casting from the source's tile; areas, spots and door spills;
//   - the 110° cone about the stamped facing, the detail rectangle, the edge glow's buckets;
//   - VIS-04's margin (2 tiles of geometry and 1 of entities beyond the own light's edge, dark
//     tiles in sight and cone only) and NET-12's turn band.
// Any disagreement with production is a finding, never absorbed by a tolerance. Dev and QA builds
// and the doctests only; never in a release library.

#include <cstdint>
#include <functional>
#include <map>
#include <set>
#include <utility>
#include <vector>

namespace lb::audit {

struct Pos {
	int64_t x = 0;
	int64_t y = 0;
	bool operator<(const Pos &o) const { return y != o.y ? y < o.y : x < o.x; }
	bool operator==(const Pos &o) const { return x == o.x && y == o.y; }
};

using Blocks = std::function<bool(Pos)>;

// Every tile visible from `origin` within `depth` rows of each quadrant (Ford's symmetric
// shadowcasting): floor tiles whose centre slope lies in the open part of a row, and every wall reached.
std::set<Pos> symmetric_fov(Pos origin, int64_t depth, const Blocks &blocks);

enum Shape : uint8_t {
	POINT = 0,
	AREA = 1,
	SPILL = 2,
	SPOT = 3,
};

struct Source {
	uint32_t id = 0;
	uint8_t shape = POINT;
	uint8_t colour = 0;
	uint32_t owner = 0;
	double radius = 0.0;
	double radius_mult = 1.0;
	double peak = 1.0;
	double end_value = 0.0;
	double x = 0.0;
	double y = 0.0;
	std::vector<Pos> tiles; // area: lit tiles; spill: doorway tiles
	Pos dir; // spill: outward direction
	Pos spot; // spot: the tile
};

struct LightDefs {
	double core_fraction = 0.6;
	double core_value = 0.30;
	double edge_value = 0.12;
	double cap = 1.0;
	int64_t scale = 1000;
};

struct TileLight {
	int64_t value = 0; // thousandths
	uint8_t colour = 0;
};

// The light of every tile in [x0, x1] x [y0, y1] from these sources. `blocks` stops light (a
// missing or opaque tile); `exists` says a tile can hold light.
std::map<Pos, TileLight> light_window(const std::vector<Source> &sources, const LightDefs &defs, const Blocks &blocks,
		const std::function<bool(Pos)> &exists, int64_t x0, int64_t y0, int64_t x1, int64_t y1);

struct VisionDefs {
	double cone_deg = 110.0;
	int64_t seen_min = 120;
	int64_t identity_min = 300;
	int64_t small_min = 300;
	int64_t trail_min = 120;
	int64_t range = 40;
	double view_w = 30.0;
	double view_h = 16.875;
	double squint_lead = 8.0;
	double detail_widen = 2.0;
	double bucket_deg = 5.0;
	double margin_geometry = 2.0;
	double margin_entity = 1.0;
};

enum Size : uint8_t {
	SIZE_NONE = 0,
	SIZE_MINER = 1,
	SIZE_LARGE = 2,
	SIZE_LARGE_MOTIONLESS = 3,
	SIZE_SMALL = 4,
};

struct Entity {
	uint32_t id = 0;
	uint8_t size = SIZE_NONE; // the kind's base size class
	uint8_t token_class = 0; // what a token of it shows (motionless folded in)
	int64_t footprint = 1;
	int64_t identity_min = -1; // thousandths; -1: the default for its size
	double x = 0.0;
	double y = 0.0;
};

struct Observer {
	uint32_t self = 0;
	double x = 0.0;
	double y = 0.0;
	uint32_t facing = 0; // 65536 to the turn, 0 = +x, a quarter = +y
	bool blinded = false;
	double clamp = 0.0;
	double turn_band = 0.0;
	std::set<Pos> bite;
	std::vector<std::pair<std::pair<double, double>, double>> own_lights; // ((x, y), radius)
};

enum State : uint8_t {
	SEEN = 0,
	DARK = 1,
	OUTSIDE_CONE = 2,
	BITE = 3,
	NO_LOS = 4,
	BEYOND_RANGE = 5,
	BLINDED = 6,
	UNKNOWN = 7,
};

enum Level : uint8_t {
	LEVEL_NONE = 0,
	LEVEL_TOKEN = 1,
	LEVEL_IDENTITY = 2,
	LEVEL_MARGIN = 3,
};

struct Expected {
	bool blinded = false;
	// Seen tiles inside the detail rectangle: what a frame may carry as tile records.
	std::map<Pos, TileLight> detail;
	// Dark tiles in VIS-04's margin band (geometry only).
	std::set<Pos> margin;
	// One per bucket, left edge first: present and its colour class.
	std::vector<std::pair<bool, uint8_t>> glow;
	// Entity id -> (level, class): identity carries no class here; tokens and margin their class.
	std::map<uint32_t, std::pair<uint8_t, uint8_t>> entities;
};

// What one observer may perceive, from the light field (light_window over its range) and the
// opacity of line of sight.
Expected evaluate(const Observer &o, const VisionDefs &defs, const std::map<Pos, TileLight> &light,
		const Blocks &opaque, const std::vector<Entity> &entities);

// The cone test and the glow bucket of a point, for the rules and the doctests.
bool in_cone(double ax, double ay, uint32_t facing, double cone_deg, double px, double py);
int64_t glow_bucket(const Observer &o, const VisionDefs &defs, double px, double py);

} // namespace lb::audit

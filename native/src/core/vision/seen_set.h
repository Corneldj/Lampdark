#pragma once
// VIS-03's seen sets: every tick, exactly what each miner perceives. A tile or entity is seen
// only in line of sight, inside the cone and lit to the seen threshold; an entity carries
// identity only at the identity threshold, and otherwise arrives as an anonymous token by size
// class (small things never). Seen tiles outside the detail region (the full-squint view, widened)
// become an edge glow by bearing; nothing beyond the range is ever in a frame. Engine-free.

#include "core/light/light_grid.h"
#include "core/sim/entity_mirror.h"
#include "core/vision/cone.h"
#include "core/vision/los_field.h"
#include "core/vision/perception_table.h"
#include "core/vision/shadow_tell.h"
#include "core/world/mine_map.h"

#include <array>
#include <cstdint>
#include <map>
#include <set>
#include <vector>

namespace lb::core::vision {

struct VisionParams {
	double cone_deg = 110.0;
	int64_t seen_min = 120;      // thousandths
	int64_t identity_min = 300;
	int64_t small_min = 300;
	int64_t trail_min = 120;
	int64_t range = 40;          // line of sight and edge glow, tiles
	double view_w = 30.0;        // VIS-01's view, tiles
	double view_h = 16.875;
	double squint_lead = 8.0;    // VIS-01's full-squint offset along the facing
	double detail_widen = 2.0;
	double bucket_deg = 5.0;
	double margin_geometry = 2.0; // VIS-04: tiles beyond the own light's edge
	double margin_entity = 1.0;
};

// Decal bits on a tile (blood trails at the trail threshold; chalk and line numbers at the
// small-thing threshold).
enum Decal : uint8_t { DECAL_BLOOD = 1, DECAL_CHALK = 2, DECAL_LINE_NUMBER = 4 };
// VIS-10: a blood trail's direction, one of 8 (0 east, then clockwise with +y down), in bits 3-5;
// sent only with DECAL_BLOOD.
constexpr uint8_t DECAL_DIR_SHIFT = 3;
constexpr uint8_t DECAL_DIR_MASK = 0x38;
// VIS-10: a seen tile's colour byte carries this bit when its brightest source is an egg-glow with
// the hatch tell raised (light::flag::HATCH_TELL): a boolean, never a time.
constexpr uint8_t COLOUR_HATCH_BIT = 0x80;

enum class Unseen : uint8_t { SEEN = 0, DARK = 1, OUTSIDE_CONE = 2, BITE = 3, NO_LOS = 4, BEYOND_RANGE = 5, BLINDED = 6, UNKNOWN = 7 };

// Perception levels for one entity.
enum class Level : uint8_t { NONE = 0, TOKEN = 1, IDENTITY = 2 };

// MNR-10: a floor tile's chalk, one glyph byte per surface: the floor (byte 0), then the rib
// faces bordering it to the north, east, south and west (bytes 1-4); 0 is none. A glyph byte is
// CHALK_PRESENT | kind (bits 0-3) | arrow direction (bits 4-6). Sent only with DECAL_CHALK, which
// needs the small-thing threshold (0.30).
constexpr size_t CHALK_SURFACES = 5;
constexpr uint8_t CHALK_PRESENT = 0x80;

struct FrameTile {
	world::Coord tile;
	uint8_t light = 0;   // quantised 0-255 from 0-1000
	uint8_t colour = 0;  // light::ColourClass
	uint8_t decals = 0;
	uint64_t chalk = 0; // MNR-10: CHALK_SURFACES glyph bytes, byte i at bits 8i
};

struct FrameToken {
	SizeClass size = SizeClass::NONE;
	double x = 0.0;
	double y = 0.0;
	// The entity behind the token, for NET-04's per-client token map only. Never encoded, never
	// exposed by the binding, and not part of equality: two tokens compare by what a client sees.
	uint32_t entity = 0;
	bool operator==(const FrameToken &o) const { return size == o.size && x == o.x && y == o.y; }
};

struct GlowBucket {
	bool present = false;
	uint8_t colour = 0;
};

struct PerceptionFrame {
	std::vector<FrameTile> tiles;       // detail, row-major
	std::vector<FrameToken> tokens;     // in ascending entity order (no IDs)
	std::vector<uint32_t> identified;   // entity IDs, ascending (NET-04 maps them)
	std::vector<GlowBucket> glow;       // one per bucket across the cone, left edge first
	// VIS-04's hidden margin: dark tiles in sight and cone just beyond the edge of the miner's
	// own light (geometry only), and the entities standing within its entity band (fringe form
	// only). Never the blind area, a bite tile, anything on one, or anything already seen.
	std::vector<world::Coord> margin_tiles;
	std::vector<FrameToken> margin_tokens;
	bool blinded = false;
};

class Vision {
public:
	Vision(const world::MineMap &map, const light::LightGrid &light) : map_(map), light_(light) {}

	VisionParams params;
	PerceptionTable table;
	ShadowParams shadow;

	// VIS-09: this tick's shadow shading, from the light grid and the entities; frames fold it into
	// their seen tiles' decal bits (SHADE_SHIFT). Call once a tick before compute().
	void update_shadows(const std::vector<sim::MirrorEntity> &entities);
	uint8_t shade_at(world::Coord tile) const {
		auto it = shadows_.find(tile);
		return it == shadows_.end() ? 0 : it->second;
	}

	// Observers: one per miner, keyed by a caller id (the slot). `self` is the miner's own entity,
	// never in its own frame.
	void set_observer(uint32_t id, uint32_t self, double x, double y, uint32_t facing_u16);
	void remove_observer(uint32_t id);
	bool has_observer(uint32_t id) const { return observers_.count(id) != 0; }
	void set_blinded(uint32_t id, bool on);
	void set_radius_clamp(uint32_t id, double tiles); // <= 0 clears it
	// NET-12's turn band (degrees, each side): the miner can turn this far before a frame computed
	// now reaches its client, so entities lit and in sight within the cone widened by it are sent as
	// hidden margin tokens, drawn only when the client's own predicted cone and light reach them.
	void set_turn_band(uint32_t id, double degrees);
	void set_bite_tiles(uint32_t id, std::set<world::Coord> tiles);
	void set_identity_threshold(uint32_t entity, int64_t thousandths); // < 0 clears it
	void set_decals(world::Coord tile, uint8_t bits);
	// MNR-10: a floor tile's chalk glyphs (FrameTile::chalk's packing); 0 clears them. The tile's
	// DECAL_CHALK bit (set_decals) says whether there is any.
	void set_chalk(world::Coord tile, uint64_t glyphs);

	// GEN-01 changed tiles: recast every field whose window touches the rectangle.
	void on_tiles_changed(int64_t x0, int64_t y0, int64_t x1, int64_t y1);

	// The frame for one observer, from the current light grid and entity mirror.
	PerceptionFrame compute(uint32_t id, const std::vector<sim::MirrorEntity> &entities);

	// Queries.
	bool in_cone(uint32_t id, double x, double y) const;
	bool tile_seen(uint32_t id, world::Coord tile);
	Level sees_entity(uint32_t id, const sim::MirrorEntity &e);
	Unseen unseen_reason(uint32_t id, const sim::MirrorEntity &e);
	bool is_seen_by_any(world::Coord tile);
	// VIS-10: whether the last frame left out a bitten tile this observer would otherwise have seen
	// (DIR-01's "seeing a creature").
	bool bite_seen(uint32_t id) const {
		auto it = observers_.find(id);
		return it != observers_.end() && it->second.bite_seen;
	}
	// DIR-01: how far, in tiles, from the observer to the centre of the nearest such tile; -1 if none.
	double bite_seen_at(uint32_t id) const {
		auto it = observers_.find(id);
		return it != observers_.end() && it->second.bite_seen ? it->second.bite_seen_at : -1.0;
	}
	// VIS-04: seen by any miner, or in any miner's margin (CRT-01's spawn guard).
	bool is_seen_or_margin_of_any(world::Coord tile);
	// The band a tile falls in for an observer's own lights: 0 none, 1 geometry only, 2 entities too.
	int margin_band(uint32_t id, world::Coord tile);
	size_t recasts() const { return recasts_; }
	// Nanoseconds spent building margins since the start (VIS-04's budget probe; never state).
	int64_t margin_nanos() const { return margin_nanos_; }
	// The frame compute() last produced for an observer (NET-04 encodes it), or null.
	const PerceptionFrame *last_frame(uint32_t id) const {
		auto it = last_.find(id);
		return it == last_.end() ? nullptr : &it->second;
	}

	// CRT-04: what an awake Moth sees from a tile: every tile in line of sight (no cone) within
	// `range` by centre distance, lit to `min_value` or more, or glowing with egg-glow at any level,
	// with its light (without the `excluded` sources), the brightest remaining source and its
	// colour class. Row-major order.
	struct SightTile {
		world::Coord tile;
		int64_t value = 0;
		uint32_t source = 0;
		uint8_t colour = 0;
	};
	std::vector<SightTile> lit_in_sight(world::Coord from, double range, int64_t min_value,
			const std::vector<uint32_t> &excluded) const;

	// The detail region's rectangle (x0, y0, x1, y1) for an observer.
	std::array<double, 4> detail_rect(uint32_t id) const;
	// The glow bucket of a point, or -1 outside the cone.
	int64_t glow_bucket(uint32_t id, double x, double y) const;

private:
	struct Observer {
		uint32_t self = 0;
		double x = 0.0;
		double y = 0.0;
		uint32_t facing = 0;
		bool blinded = false;
		double clamp = 0.0;
		double turn_band = 0.0;
		std::set<world::Coord> bite;
		bool bite_seen = false;
		double bite_seen_at = -1.0;
		LosField los;
	};

	const world::MineMap &map_;
	const light::LightGrid &light_;
	std::map<uint32_t, Observer> observers_;
	std::map<uint32_t, int64_t> identity_override_;
	std::map<world::Coord, uint8_t> decals_;
	std::map<world::Coord, uint64_t> chalk_;
	std::map<world::Coord, uint8_t> shadows_;
	size_t recasts_ = 0;
	int64_t margin_nanos_ = 0;
	std::map<uint32_t, PerceptionFrame> last_;

	Observer *observer(uint32_t id);
	PerceptionFrame compute_frame(uint32_t id, const std::vector<sim::MirrorEntity> &entities);
	void ensure_los(Observer &o);
	Cone cone_of(const Observer &o) const;
	// Why a tile is not seen, or SEEN, and its light.
	Unseen tile_state(Observer &o, const Cone &cone, world::Coord tile, int64_t &light) const;
	int64_t entity_light(Observer &o, const Cone &cone, const sim::MirrorEntity &e, Unseen &why) const;
	int64_t bucket_count() const;
};

} // namespace lb::core::vision

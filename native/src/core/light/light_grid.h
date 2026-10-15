#pragma once
// The authoritative light grid (VIS-02, Gameplay §5.2): a value in thousandths for every tile
// of every loaded cell, the sum of every registered source capped at the light cap. Sources
// cache their contribution over a bounding box; only boxes made dirty by a source change or
// an opacity change (GEN-01's tiles_changed) are re-summed. Server-only; tick thread only.

#include "core/light/falloff.h"
#include "core/light/shadowcast.h"
#include "core/world/mine_map.h"

#include <array>
#include <map>
#include <optional>
#include <string>
#include <vector>

namespace lb::core::light {

using lb::core::world::CELL_AREA;
using lb::core::world::MineMap;

enum class Shape : uint8_t { POINT, AREA, SPILL, SPOT };
enum class ColourClass : uint8_t { NONE, AMBER, PALE_AMBER, WHITE, EGG_GLOW, GOB_ORANGE };

namespace flag {
constexpr uint32_t FLAME = 1;            // a flame, even at radius 0 (MNR-06)
constexpr uint32_t CARRIED = 2;          // held by its owner
constexpr uint32_t UNHELD = 4;           // set down or hung (CRT-04)
constexpr uint32_t CANNOT_TAKE = 8;      // the Moth cannot take it (gob fire, electric lamp)
constexpr uint32_t NO_FLAME_STATES = 16; // shows no flame states (flare)
constexpr uint32_t BEYOND_SNUFF = 32;    // the Stythe cannot snuff it
} // namespace flag

struct SourceDesc {
	Shape shape = Shape::POINT;
	std::string kind; // gauze_lamp, candle, flare, muzzle_flash, electric_lamp, emergency, ...
	ColourClass colour = ColourClass::AMBER;
	uint32_t owner = 0;          // owner entity (0: none)
	int64_t lifetime_ticks = 0;  // 0: until removed
	uint32_t flags = 0;
	double radius = 0.0;         // point: R; spill: length in tiles
	double peak = 1.0;           // point: centre light; area, spot, spill: the value
	double end_value = 0.0;      // spill: value at its far end
	double x = 0.0, y = 0.0;     // point: position in tile units
	std::vector<Coord> tiles;    // area: lit tiles; spill: the doorway tiles
	Coord dir{0, 0};             // spill: outward direction (unit, cardinal)
	Coord spot{0, 0};            // spot: the tile
};

struct LightEvent {
	enum class Type : uint8_t { ADDED, REMOVED, CHANGED } type;
	uint32_t id;
	std::string kind;
	std::string cause;
	double x, y;
};

// Thousandths of light to the frames' byte (VIS-03's tiles, NET-07's record): 0-255, rounded.
inline uint8_t quantise_u8(int64_t thousandths) {
	const int64_t v = (thousandths * 255 + 500) / 1000;
	return static_cast<uint8_t>(v < 0 ? 0 : (v > 255 ? 255 : v));
}

struct TileLight {
	int64_t value = 0;
	ColourClass colour = ColourClass::NONE;
	uint32_t brightest = 0; // source with the largest contribution (ties: lowest id)
};

class LightGrid {
public:
	explicit LightGrid(const MineMap &mine) : mine_(mine) {}

	LightParams params;

	// Registry.
	uint32_t add_source(const SourceDesc &desc);
	bool update_point(uint32_t id, double x, double y, double radius, double peak);
	// Multiplies the radius (guttering 0.7; blackdamp's shrink). The core stays at the
	// core fraction of the modified radius.
	bool set_radius_modifier(uint32_t id, double multiplier, const std::string &cause);
	bool set_flags(uint32_t id, uint32_t flags);
	bool remove_source(uint32_t id);
	bool has_source(uint32_t id) const { return sources_.count(id) != 0; }
	size_t source_count() const { return sources_.size(); }
	std::optional<SourceDesc> source(uint32_t id) const;
	// Every registered source's id, ascending (NET-08's audit snapshots the descriptions).
	std::vector<uint32_t> source_ids() const;
	// The radius multiplier in force (VIS-08's guttering and shrinking), 1 for none or no source.
	double radius_mult(uint32_t id) const;
	// A miner's own point lights (lamp in hand or on the hook, candle, flare) and their radius
	// after modifiers (guttering, blackdamp); radius 0 (shuttered, slotted) means no light edge.
	struct OwnLight {
		double x = 0.0, y = 0.0, radius = 0.0;
	};
	std::vector<OwnLight> owned_lights(uint32_t owner) const;
	std::pair<double, double> velocity(uint32_t id) const;

	// World changes.
	void on_cell_loaded(Coord cell);
	void on_cell_unloading(Coord cell);
	void on_tiles_changed(int64_t x0, int64_t y0, int64_t x1, int64_t y1);

	// Once per tick, before the first update: lifetimes and velocities (tiles a second at
	// tick_hz). A source with a lifetime of n ticks is in the grid for exactly n ticks,
	// counted from the first update that includes it, whenever in a tick it was added.
	void begin_tick(double tick_hz);
	// Recomputes dirty sources and re-sums dirty regions.
	void update();

	// Queries, in thousandths.
	int64_t value(Coord tile) const;
	int64_t value_at(double x, double y) const;
	int64_t value_from(Coord tile, const std::vector<uint32_t> &owners) const;
	// CRT-04: a tile's light without some sources (a Moth's searched lights), capped like value(),
	// and the brightest of the rest (0 if none).
	std::pair<int64_t, uint32_t> value_excluding(Coord tile, const std::vector<uint32_t> &excluded) const;
	TileLight tile_light(Coord tile) const;
	std::vector<Coord> tiles_at_or_above(int64_t threshold, int64_t x0, int64_t y0, int64_t x1, int64_t y1) const;
	std::vector<uint32_t> flame_sources(double x0, double y0, double x1, double y1) const;
	// NET-07: every tile of a w x h rectangle from (x0, y0), row by row, as quantise_u8 bytes.
	std::vector<uint8_t> light_bytes(int64_t x0, int64_t y0, int64_t w, int64_t h) const;
	std::vector<LightEvent> take_events();

	uint64_t digest() const;
	// Every loaded tile's value, computed from scratch without the caches (for tests).
	std::map<Coord, std::array<int64_t, CELL_AREA>> reference_values() const;
	std::map<Coord, std::array<int64_t, CELL_AREA>> current_values() const;

	// Timing of the last update, µs (for NET-01's timer and the budget).
	int64_t last_update_usec = 0;

private:
	struct Box {
		int64_t x0 = 0, y0 = 0, w = 0, h = 0;
		bool contains(Coord t) const { return t.x >= x0 && t.y >= y0 && t.x < x0 + w && t.y < y0 + h; }
		bool empty() const { return w <= 0 || h <= 0; }
	};
	struct Source {
		uint32_t id = 0;
		SourceDesc desc;
		double radius_mult = 1.0;
		double prev_x = 0.0, prev_y = 0.0, vx = 0.0, vy = 0.0;
		int64_t ticks_shown = 0;     // ticks in which an update included it
		bool shown_this_tick = false;
		Box box;
		std::vector<uint16_t> contrib;
		bool dirty = true;
	};
	struct CellLight {
		std::array<TileLight, CELL_AREA> tiles{};
	};

	const MineMap &mine_;
	std::map<uint32_t, Source> sources_;
	std::map<Coord, CellLight> cells_;
	std::vector<Box> dirty_boxes_;
	std::vector<LightEvent> events_;
	uint32_t next_id_ = 1;

	bool blocks(Coord tile) const;
	void contribution(const Source &s, Box &box, std::vector<uint16_t> &out) const;
	void mark_dirty(Source &s);
	void resum(const Box &box);
	TileLight sum_at(Coord tile) const;
	TileLight *tile_mut(Coord tile);
};

} // namespace lb::core::light

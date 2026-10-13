#pragma once
// The tile material property table (GEN-01). FND-07 owns the enum and the design's facts;
// GEN-01 owns the full table, mirrored from data/world/materials.json (C++ never opens files).
// An open STEEL gate or WOODEN_DOOR air door behaves as FLOOR for every rule.

#include "core/generated/world_ids.h"

#include <array>
#include <cstdint>
#include <string>

namespace lb::core::world {

// Tile state bits: bit 0 is FND-07's open bit; GEN-01 adds rail and sump mud.
constexpr uint8_t STATE_OPEN = static_cast<uint8_t>(TILE_STATE_OPEN);
constexpr uint8_t STATE_RAIL = 1 << 1;
constexpr uint8_t STATE_MUD = 1 << 2;

struct MaterialProps {
	bool solid = false;         // blocks bodies
	bool opaque = false;        // blocks light and sight
	bool tapper_moves = false;  // the Tapper may move through it
	bool tapper_face = false;   // a face of it may host a strike, taps or an illusion
	bool voice_crosses = false; // voice crosses 2 tiles or less of it at half range
	bool taps_cross = false;    // rock taps carry through it
	std::string caption_key;
};

constexpr size_t MATERIAL_COUNT = 7;

class MaterialTable {
public:
	// GEN-01's table (Proposed rows included), identical to data/world/materials.json.
	static MaterialTable defaults();

	const MaterialProps &get(TileMaterial material) const { return props_[static_cast<size_t>(material)]; }
	void set(TileMaterial material, MaterialProps props) { props_[static_cast<size_t>(material)] = std::move(props); }

	// The material a tile behaves as: an open gate or door is FLOOR.
	static TileMaterial effective(TileMaterial material, uint8_t state) {
		if ((material == TileMaterial::STEEL || material == TileMaterial::WOODEN_DOOR) && (state & STATE_OPEN) != 0) {
			return TileMaterial::FLOOR;
		}
		return material;
	}

private:
	std::array<MaterialProps, MATERIAL_COUNT> props_{};
};

} // namespace lb::core::world

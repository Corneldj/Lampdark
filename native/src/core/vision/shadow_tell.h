#pragma once
// VIS-09's shadow tell (Gameplay §5.8): bodies of miner size and up, lit to light.shadow_min_light
// (0.30), cast a shadow away from the brightest light on them, as long as that light's radius after
// modifiers, stopping at the first opaque tile, as 2-bit shading on lit tiles: 3 next to the body
// falling to 1 at the end, 1 tile wide for every caster (a shadow never tells what cast it), the
// greatest where shadows overlap. Some kinds never cast (the Stythe). No rule reads it: it only
// rides in frames, on tiles the viewer sees, whether or not the caster is seen. Engine-free.

#include "core/light/light_grid.h"
#include "core/sim/entity_mirror.h"
#include "core/vision/perception_table.h"
#include "core/world/mine_map.h"

#include <cstdint>
#include <map>
#include <set>
#include <vector>

namespace lb::core::vision {

// The shading's bits in a frame tile's decal byte (bits 6 and 7; 0 = none).
constexpr uint8_t SHADE_SHIFT = 6;
constexpr uint8_t SHADE_MASK = 0xC0;

struct ShadowParams {
	bool enabled = true;
	int64_t min_light = 300;  // thousandths, on the caster's tile
	int64_t lit_min = 120;    // a shaded tile must be lit to this
	int levels = 4;           // 2-bit: 0 none, 1-3
	double width = 1.0;       // tiles (1: one tile across)
	std::set<uint16_t> never_cast;
};

std::map<world::Coord, uint8_t> compute_shadows(const world::MineMap &map, const light::LightGrid &light, const PerceptionTable &table,
		const std::vector<sim::MirrorEntity> &entities, const ShadowParams &p);

} // namespace lb::core::vision

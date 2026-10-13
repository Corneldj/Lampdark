#pragma once
// Symmetric shadowcasting (VIS-02): every tile visible from an origin tile within a depth,
// with hard shadows. Exact integer fractions, so every platform agrees. Pure; the opacity
// test is the caller's (GEN-01's opacity on the server, held geometry on the client).
// Opaque tiles that are reached are reported too (a lit rib face) but pass no light on.

#include "core/world/coords.h"

#include <cstdint>
#include <functional>

namespace lb::core::light {

using lb::core::world::Coord;

// Calls visit(tile) once per visible tile, the origin first. blocks(tile) says whether a tile
// stops light. Reaches tiles up to `depth` rows from the origin in each quadrant.
void shadowcast(Coord origin, int64_t depth, const std::function<bool(Coord)> &blocks,
		const std::function<void(Coord)> &visit);

} // namespace lb::core::light

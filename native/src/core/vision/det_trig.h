#pragma once
// Deterministic sine and cosine for VIS-03's cone (FND-06 rule 3: no libm transcendentals in
// the core). Only +, - and * on doubles, so with -ffp-contract=off every platform computes the
// same bits. Accurate to about 1e-15 over the whole circle.

#include <cstdint>

namespace lb::core::vision {

struct Vec2 {
	double x = 0.0;
	double y = 0.0;
};

// The unit vector at an angle in turns (1.0 = 360°); 0 is +x, a quarter turn is +y.
Vec2 unit_at_turns(double turns);

// The unit vector of a 16-bit facing (65536 per turn, as NET-03's input record carries it).
Vec2 unit_at_facing(uint32_t facing_u16);

// cos of an angle in degrees.
double cos_deg(double degrees);

} // namespace lb::core::vision

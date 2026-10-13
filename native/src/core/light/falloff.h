#pragma once
// The design's light falloff (VIS-02, Gameplay §5.2). Pure functions, shared by the server's
// grid and the client's own-lamp prediction (NET-05, VIS-06), so both compute the same
// values. Light is held in fixed-point thousandths (0-1000).
//
// A source of radius R and peak P (1.0 for most) gives, by distance d from its position:
//   P at 0, falling linearly to core_value at core_fraction * R, then to edge_value at R,
//   and 0 beyond R. A peak at or below core_value (egg-glow's 0.2) falls linearly from P to
//   edge_value over R (Proposed).

#include <cmath>
#include <cstdint>

namespace lb::core::light {

struct LightParams {
	double core_fraction = 0.6; // light.core_fraction
	double core_value = 0.30;   // light.core_value
	double edge_value = 0.12;   // light.edge_value
	double cap = 1.0;           // light.cap
	int64_t scale = 1000;       // light.value_scale
};

// Light at distance d, as a double in [0, peak].
inline double falloff(double d, double radius, double peak, const LightParams &p) {
	if (radius <= 0.0 || d > radius || d < 0.0) {
		return 0.0;
	}
	if (peak <= p.core_value) {
		return peak + (p.edge_value - peak) * (d / radius);
	}
	const double core = p.core_fraction * radius;
	if (d <= core) {
		return peak + (p.core_value - peak) * (d / core);
	}
	return p.core_value + (p.edge_value - p.core_value) * ((d - core) / (radius - core));
}

// The same, rounded to thousandths.
inline int64_t falloff_milli(double d, double radius, double peak, const LightParams &p) {
	return std::llround(falloff(d, radius, peak, p) * static_cast<double>(p.scale));
}

// The distance at which a full-peak source falls to `level` (inverse of falloff), for checks
// such as the 0.60 reach.
inline double reach_of(double level, double radius, double peak, const LightParams &p) {
	const double core = p.core_fraction * radius;
	if (level >= p.core_value) {
		return core * (peak - level) / (peak - p.core_value);
	}
	return core + (radius - core) * (p.core_value - level) / (p.core_value - p.edge_value);
}

} // namespace lb::core::light

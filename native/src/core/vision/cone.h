#pragma once
// VIS-03's vision cone: everything whose point lies within ±half the cone angle of the facing,
// with straight edges from the apex. Points within 0.5 tile of the apex count as inside, so the
// floor underfoot shows when lit (Proposed). No trig: a dot-product test against the cosine of half the angle.

#include "core/vision/det_trig.h"

namespace lb::core::vision {

struct Cone {
	double ax = 0.0; // apex: the miner's position
	double ay = 0.0;
	Vec2 facing{1.0, 0.0};
	double cos_half = 0.57357643635104609611; // cos 55°
	double apex_radius = 0.5;

	static Cone make(double ax, double ay, uint32_t facing_u16, double cone_deg) {
		Cone c;
		c.ax = ax;
		c.ay = ay;
		c.facing = unit_at_facing(facing_u16);
		c.cos_half = cos_deg(cone_deg * 0.5);
		return c;
	}

	bool contains(double px, double py) const {
		const double vx = px - ax;
		const double vy = py - ay;
		const double len2 = vx * vx + vy * vy;
		if (len2 <= apex_radius * apex_radius) {
			return true;
		}
		const double dot = vx * facing.x + vy * facing.y;
		if (cos_half >= 0.0) {
			return dot >= 0.0 && dot * dot >= cos_half * cos_half * len2;
		}
		return dot >= 0.0 || dot * dot <= cos_half * cos_half * len2;
	}

	// Tiles are tested at their centres.
	bool contains_tile(int64_t tx, int64_t ty) const {
		return contains(static_cast<double>(tx) + 0.5, static_cast<double>(ty) + 0.5);
	}
};

} // namespace lb::core::vision

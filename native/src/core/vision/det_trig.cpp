#include "core/vision/det_trig.h"

namespace lb::core::vision {

namespace {

constexpr double QUARTER_PI = 0.78539816339744830962;

// Taylor series on [-pi/4, pi/4]; the next terms are below 1e-16 there.
double sin_small(double x) {
	const double x2 = x * x;
	double t = x;
	double sum = x;
	for (int n = 1; n <= 9; n++) {
		t = -t * x2 / static_cast<double>((2 * n) * (2 * n + 1));
		sum = sum + t;
	}
	return sum;
}

double cos_small(double x) {
	const double x2 = x * x;
	double t = 1.0;
	double sum = 1.0;
	for (int n = 1; n <= 9; n++) {
		t = -t * x2 / static_cast<double>((2 * n - 1) * (2 * n));
		sum = sum + t;
	}
	return sum;
}

} // namespace

Vec2 unit_at_turns(double turns) {
	// Reduce to eighths of a turn: octant k and a remainder in [-1/16, 1/16] of a turn.
	double t = turns - static_cast<double>(static_cast<int64_t>(turns));
	if (t < 0.0) {
		t = t + 1.0;
	}
	const double eighths = t * 8.0;
	int64_t k = static_cast<int64_t>(eighths + 0.5);
	const double rem = (eighths - static_cast<double>(k)) * QUARTER_PI; // radians in [-pi/8, pi/8]
	k = k % 8;
	const double s = sin_small(rem);
	const double c = cos_small(rem);
	// Rotate (c, s) by k eighths of a turn using exact octant vectors.
	constexpr double R = 0.70710678118654752440; // sqrt(2) / 2
	switch (k) {
		case 0: return {c, s};
		case 1: return {R * (c - s), R * (c + s)};
		case 2: return {-s, c};
		case 3: return {-R * (c + s), R * (c - s)};
		case 4: return {-c, -s};
		case 5: return {R * (s - c), -R * (c + s)};
		case 6: return {s, -c};
		default: return {R * (c + s), R * (s - c)};
	}
}

Vec2 unit_at_facing(uint32_t facing_u16) {
	return unit_at_turns(static_cast<double>(facing_u16 & 0xFFFFu) / 65536.0);
}

double cos_deg(double degrees) {
	return unit_at_turns(degrees / 360.0).x;
}

} // namespace lb::core::vision

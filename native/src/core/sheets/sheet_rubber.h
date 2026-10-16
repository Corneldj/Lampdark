#pragma once
// LFT-14's rubber (Proposed: partial), the server's hot path: a sheet stroke's polyline after the
// rubber's circles, in turn. What lies strictly inside a circle goes; a step crossing a circle's
// edge is cut there (cut points rounded to whole sheet units), so one stroke may leave several
// pieces of two points or more. A one-point stroke (a dot) goes whole when inside a circle. A
// point on the edge counts as outside, and a tangent touch takes nothing. Engine-free.

#include <vector>

namespace lb::core::sheets {

struct Pt {
	double x = 0.0;
	double y = 0.0;
	bool operator==(const Pt &o) const { return x == o.x && y == o.y; }
};

struct RubResult {
	bool touched = false;
	std::vector<std::vector<Pt>> pieces; // untouched: the polyline itself
};

RubResult rub(const std::vector<Pt> &points, const std::vector<Pt> &centres, double radius);

} // namespace lb::core::sheets

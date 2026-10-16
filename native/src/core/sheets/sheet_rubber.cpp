#include "core/sheets/sheet_rubber.h"

#include <algorithm>
#include <cmath>

namespace lb::core::sheets {

namespace {

struct Box {
	double x0, y0, x1, y1;
	bool has(const Pt &p) const { return p.x >= x0 && p.x <= x1 && p.y >= y0 && p.y <= y1; }
};

Box grown_box(const std::vector<Pt> &pts, double r) {
	Box b{pts[0].x, pts[0].y, pts[0].x, pts[0].y};
	for (const Pt &p : pts) {
		b.x0 = std::min(b.x0, p.x);
		b.y0 = std::min(b.y0, p.y);
		b.x1 = std::max(b.x1, p.x);
		b.y1 = std::max(b.y1, p.y);
	}
	return Box{b.x0 - r, b.y0 - r, b.x1 + r, b.y1 + r};
}

double dist2(const Pt &a, const Pt &b) {
	return (a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y);
}

// The part of a-b strictly inside the circle as [t0, t1); t0 >= t1 when none.
void inside_span(const Pt &a, const Pt &b, const Pt &c, double r, double &t0, double &t1) {
	const double dx = b.x - a.x;
	const double dy = b.y - a.y;
	const double fx = a.x - c.x;
	const double fy = a.y - c.y;
	const double qa = dx * dx + dy * dy;
	const double r2 = r * r;
	if (qa == 0.0) {
		const bool in = fx * fx + fy * fy < r2;
		t0 = in ? 0.0 : 1.0;
		t1 = in ? 1.0 : 0.0;
		return;
	}
	const double qb = 2.0 * (fx * dx + fy * dy);
	const double qc = fx * fx + fy * fy - r2;
	const double disc = qb * qb - 4.0 * qa * qc;
	if (disc <= 0.0) {
		t0 = 1.0;
		t1 = 0.0;
		return;
	}
	const double s = std::sqrt(disc);
	t0 = std::max((-qb - s) / (2.0 * qa), 0.0);
	t1 = std::min((-qb + s) / (2.0 * qa), 1.0);
	if (t0 >= t1) {
		t0 = 1.0;
		t1 = 0.0;
	}
}

Pt whole(const Pt &a, const Pt &b, double t) {
	return Pt{std::round(a.x + (b.x - a.x) * t), std::round(a.y + (b.y - a.y) * t)};
}

void push(std::vector<Pt> &cur, const Pt &p) {
	if (cur.empty() || !(cur.back() == p)) {
		cur.push_back(p);
	}
}

void close(std::vector<std::vector<Pt>> &pieces, std::vector<Pt> &cur) {
	if (cur.size() >= 2) {
		pieces.push_back(std::move(cur));
	}
	cur.clear();
}

bool touches(const std::vector<Pt> &pts, const Pt &c, double r) {
	for (size_t i = 1; i < pts.size(); i++) {
		const Pt &a = pts[i - 1];
		const Pt &b = pts[i];
		if (std::max(a.x, b.x) < c.x - r || std::min(a.x, b.x) > c.x + r || std::max(a.y, b.y) < c.y - r ||
				std::min(a.y, b.y) > c.y + r) {
			continue;
		}
		double t0 = 0.0;
		double t1 = 0.0;
		inside_span(a, b, c, r, t0, t1);
		if (t0 < t1) {
			return true;
		}
	}
	return false;
}

// One circle over one piece: false (and nothing added) when untouched.
bool clip(const std::vector<Pt> &pts, const Pt &c, double r, std::vector<std::vector<Pt>> &out) {
	const double r2 = r * r;
	if (pts.size() == 1) {
		if (dist2(pts[0], c) < r2) {
			return true;
		}
		return false;
	}
	if (!touches(pts, c, r)) {
		return false;
	}
	std::vector<Pt> cur;
	if (dist2(pts[0], c) >= r2) {
		cur.push_back(pts[0]);
	}
	for (size_t i = 1; i < pts.size(); i++) {
		const Pt &a = pts[i - 1];
		const Pt &b = pts[i];
		double t0 = 0.0;
		double t1 = 0.0;
		inside_span(a, b, c, r, t0, t1);
		if (t0 >= t1) {
			push(cur, b);
			continue;
		}
		if (t0 > 0.0) {
			push(cur, whole(a, b, t0));
		}
		close(out, cur);
		if (t1 < 1.0) {
			cur.push_back(whole(a, b, t1));
			push(cur, b);
		}
	}
	close(out, cur);
	return true;
}

} // namespace

RubResult rub(const std::vector<Pt> &points, const std::vector<Pt> &centres, double radius) {
	RubResult result;
	if (points.empty()) {
		return result;
	}
	std::vector<std::vector<Pt>> pieces{points};
	std::vector<Box> boxes{grown_box(points, radius)};
	for (const Pt &c : centres) {
		std::vector<std::vector<Pt>> next;
		std::vector<Box> next_boxes;
		for (size_t k = 0; k < pieces.size(); k++) {
			std::vector<std::vector<Pt>> parts;
			if (!boxes[k].has(c) || !clip(pieces[k], c, radius, parts)) {
				next.push_back(std::move(pieces[k]));
				next_boxes.push_back(boxes[k]);
				continue;
			}
			result.touched = true;
			for (std::vector<Pt> &part : parts) {
				next_boxes.push_back(grown_box(part, radius));
				next.push_back(std::move(part));
			}
		}
		pieces = std::move(next);
		boxes = std::move(next_boxes);
	}
	result.pieces = std::move(pieces);
	return result;
}

} // namespace lb::core::sheets

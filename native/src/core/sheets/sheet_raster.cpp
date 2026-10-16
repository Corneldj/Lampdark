#include "core/sheets/sheet_raster.h"

#include <algorithm>
#include <cmath>

namespace lb::core::sheets {

namespace {

constexpr int32_t SIDE_MAX = 8192;

double channel(uint32_t rgba, int shift) {
	return static_cast<double>((rgba >> shift) & 0xFFu);
}

// One segment's coverage (pixel space) into `cov`, keeping each pixel's strongest.
void segment(std::vector<uint8_t> &cov, int32_t w, int32_t h, double ax, double ay, double bx, double by, double half) {
	const double pad = half + 1.0;
	const int32_t x0 = std::max<int32_t>(0, static_cast<int32_t>(std::floor(std::min(ax, bx) - pad)));
	const int32_t x1 = std::min<int32_t>(w - 1, static_cast<int32_t>(std::ceil(std::max(ax, bx) + pad)));
	const int32_t y0 = std::max<int32_t>(0, static_cast<int32_t>(std::floor(std::min(ay, by) - pad)));
	const int32_t y1 = std::min<int32_t>(h - 1, static_cast<int32_t>(std::ceil(std::max(ay, by) + pad)));
	if (x0 > x1 || y0 > y1) {
		return;
	}
	const double dx = bx - ax;
	const double dy = by - ay;
	const double len2 = dx * dx + dy * dy;
	for (int32_t y = y0; y <= y1; y++) {
		const double py = y + 0.5;
		for (int32_t x = x0; x <= x1; x++) {
			const double px = x + 0.5;
			const double t = len2 > 0.0 ? std::clamp(((px - ax) * dx + (py - ay) * dy) / len2, 0.0, 1.0) : 0.0;
			const double qx = ax + t * dx - px;
			const double qy = ay + t * dy - py;
			const double c = std::clamp(half + 0.5 - std::sqrt(qx * qx + qy * qy), 0.0, 1.0);
			if (c > 0.0) {
				const size_t i = static_cast<size_t>(y) * static_cast<size_t>(w) + static_cast<size_t>(x);
				cov[i] = std::max(cov[i], static_cast<uint8_t>(std::lround(c * 255.0)));
			}
		}
	}
}

} // namespace

std::vector<uint8_t> render(const View &view, uint32_t paper_rgba, const std::vector<Layer> &layers) {
	const int32_t w = view.width;
	const int32_t h = view.height;
	if (w <= 0 || h <= 0 || w > SIDE_MAX || h > SIDE_MAX) {
		return {};
	}
	const size_t n = static_cast<size_t>(w) * static_cast<size_t>(h);
	std::vector<uint8_t> out(n * 4);
	for (size_t i = 0; i < n; i++) {
		out[i * 4 + 0] = static_cast<uint8_t>(paper_rgba >> 24);
		out[i * 4 + 1] = static_cast<uint8_t>(paper_rgba >> 16);
		out[i * 4 + 2] = static_cast<uint8_t>(paper_rgba >> 8);
		out[i * 4 + 3] = static_cast<uint8_t>(paper_rgba);
	}
	std::vector<uint8_t> cov(n);
	for (const Layer &layer : layers) {
		std::fill(cov.begin(), cov.end(), uint8_t{0});
		const double half = std::max(0.5, layer.width_px * 0.5);
		const size_t pairs = layer.xy.size() / 2;
		for (size_t k = 0; k < layer.starts.size(); k++) {
			const size_t s = static_cast<size_t>(std::max<int32_t>(0, layer.starts[k]));
			const size_t e = k + 1 < layer.starts.size() ? static_cast<size_t>(layer.starts[k + 1]) : pairs;
			if (s >= e || e > pairs) {
				continue;
			}
			auto px = [&](size_t p) { return (layer.xy[p * 2] - view.origin_x) * view.scale; };
			auto py = [&](size_t p) { return (layer.xy[p * 2 + 1] - view.origin_y) * view.scale; };
			if (e - s == 1) {
				segment(cov, w, h, px(s), py(s), px(s), py(s), half);
				continue;
			}
			for (size_t p = s; p + 1 < e; p++) {
				segment(cov, w, h, px(p), py(p), px(p + 1), py(p + 1), half);
			}
		}
		const double r = channel(layer.rgba, 24);
		const double g = channel(layer.rgba, 16);
		const double b = channel(layer.rgba, 8);
		const double a = channel(layer.rgba, 0) / 255.0;
		for (size_t i = 0; i < n; i++) {
			if (cov[i] == 0) {
				continue;
			}
			const double k = a * (cov[i] / 255.0);
			out[i * 4 + 0] = static_cast<uint8_t>(std::lround(out[i * 4 + 0] * (1.0 - k) + r * k));
			out[i * 4 + 1] = static_cast<uint8_t>(std::lround(out[i * 4 + 1] * (1.0 - k) + g * k));
			out[i * 4 + 2] = static_cast<uint8_t>(std::lround(out[i * 4 + 2] * (1.0 - k) + b * k));
		}
	}
	return out;
}

} // namespace lb::core::sheets

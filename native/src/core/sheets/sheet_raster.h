#pragma once
// LFT-14's map card: a sheet's polylines rasterised onto survey paper, on the CPU, the same bytes on
// every machine for the same strokes (no GPU, no font). Lines are anti-aliased by their distance
// to each segment; a layer takes, per pixel, its strongest coverage, so a line crossing itself
// never darkens twice. Layers are composited in order over the paper. Engine-free.

#include <cstdint>
#include <vector>

namespace lb::core::sheets {

// One layer of polylines in sheet units: xy holds x, y pairs; starts holds each polyline's first
// pair index, ascending. A polyline of one point is a dot.
struct Layer {
	std::vector<int32_t> xy;
	std::vector<int32_t> starts;
	uint32_t rgba = 0x000000FFu; // straight alpha
	double width_px = 3.0;
};

// Sheet units to pixels: px = (unit - origin) * scale.
struct View {
	double origin_x = 0.0;
	double origin_y = 0.0;
	double scale = 1.0;
	int32_t width = 0;
	int32_t height = 0;
};

// RGBA8 rows, top to bottom: the paper colour, then each layer over it. Empty if the view is
// empty or over 8192 px a side.
std::vector<uint8_t> render(const View &view, uint32_t paper_rgba, const std::vector<Layer> &layers);

} // namespace lb::core::sheets

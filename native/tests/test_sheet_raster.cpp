// LFT-14: the map card's rasteriser draws anti-aliased pencil on paper, a layer never darkening
// where it crosses itself, and gives the same bytes for the same strokes.
#include "doctest.h"

#include "core/sheets/sheet_raster.h"

using namespace lb::core::sheets;

namespace {

constexpr uint32_t PAPER = 0xDCD2B6FFu;
constexpr uint32_t PENCIL = 0x3C3C3CFFu;

View view(int32_t side) {
	View v;
	v.origin_x = 0.0;
	v.origin_y = 0.0;
	v.scale = 0.1; // 10 sheet units a pixel
	v.width = side;
	v.height = side;
	return v;
}

uint8_t red(const std::vector<uint8_t> &rgba, int32_t side, int32_t x, int32_t y) {
	return rgba[(static_cast<size_t>(y) * side + x) * 4];
}

Layer pencil(std::vector<int32_t> xy, std::vector<int32_t> starts) {
	Layer l;
	l.xy = std::move(xy);
	l.starts = std::move(starts);
	l.rgba = PENCIL;
	l.width_px = 3.0;
	return l;
}

} // namespace

TEST_CASE("LFT-14: a pencil line darkens the paper along it and nowhere else") {
	const View v = view(64);
	const std::vector<uint8_t> out = render(v, PAPER, {pencil({50, 300, 550, 300}, {0})});
	REQUIRE(out.size() == 64u * 64u * 4u);
	CHECK(red(out, 64, 30, 30) == 0x3C); // on the line, full coverage
	CHECK(red(out, 64, 30, 33) == 0xDC); // well off it: paper
	CHECK(red(out, 64, 60, 30) == 0xDC); // beyond its end
	CHECK(red(out, 64, 30, 31) < 0xDC); // the line's edge, partly covered
	CHECK(out[3] == 0xFF); // opaque
}

TEST_CASE("LFT-14: a line crossing itself never darkens twice, and a dot draws") {
	const View v = view(64);
	const std::vector<uint8_t> once = render(v, PAPER, {pencil({50, 300, 550, 300}, {0})});
	const std::vector<uint8_t> crossed = render(v, PAPER, {pencil({50, 300, 550, 300, 300, 50, 300, 550}, {0, 2})});
	CHECK(red(crossed, 64, 30, 30) == red(once, 64, 30, 30));
	const std::vector<uint8_t> dot = render(v, PAPER, {pencil({200, 200}, {0})});
	CHECK(red(dot, 64, 20, 20) < 0xDC);
	CHECK(red(dot, 64, 25, 20) == 0xDC);
}

TEST_CASE("LFT-14: the same strokes give the same bytes; an empty or oversized view gives none") {
	const View v = view(48);
	const Layer a = pencil({0, 0, 127, 64, 254, 0, 381, 64}, {0});
	CHECK(render(v, PAPER, {a}) == render(v, PAPER, {a}));
	CHECK(render(view(0), PAPER, {a}).empty());
	CHECK(render(view(9000), PAPER, {a}).empty());
}

// LFT-14: the rubber cuts a stroke where its circle's edge crosses it, takes a dot inside whole,
// leaves a stroke it misses (or only grazes) as it was, and works its circles in turn.
#include "doctest.h"

#include "core/sheets/sheet_rubber.h"

using namespace lb::core::sheets;

namespace {

std::vector<Pt> line(double x0, double x1, int steps, double y = 0.0) {
	std::vector<Pt> out;
	for (int i = 0; i <= steps; i++) {
		out.push_back(Pt{x0 + (x1 - x0) * i / steps, y});
	}
	return out;
}

} // namespace

TEST_CASE("LFT-14: a circle through a stroke's middle leaves two pieces cut at its edge") {
	const RubResult r = rub(line(0, 1000, 10), {Pt{500, 0}}, 48.0);
	CHECK(r.touched);
	REQUIRE(r.pieces.size() == 2);
	CHECK(r.pieces[0].front() == Pt{0, 0});
	CHECK(r.pieces[0].back() == Pt{452, 0});
	CHECK(r.pieces[1].front() == Pt{548, 0});
	CHECK(r.pieces[1].back() == Pt{1000, 0});
}

TEST_CASE("LFT-14: a step is cut with no point under the rubber; a graze or a miss changes nothing") {
	const RubResult cut = rub({Pt{0, 0}, Pt{127, 0}}, {Pt{63, 10}}, 20.0);
	REQUIRE(cut.pieces.size() == 2);
	CHECK(cut.pieces[0].back() == Pt{46, 0});
	CHECK(cut.pieces[1].front() == Pt{80, 0});
	const RubResult graze = rub(line(0, 1000, 10), {Pt{500, 48}}, 48.0);
	CHECK_FALSE(graze.touched);
	REQUIRE(graze.pieces.size() == 1);
	CHECK(graze.pieces[0].size() == 11);
	const RubResult miss = rub(line(0, 1000, 10), {Pt{2000, 0}}, 48.0);
	CHECK_FALSE(miss.touched);
}

TEST_CASE("LFT-14: a dot inside goes whole; circles work in turn along the rubber's path") {
	const RubResult dot = rub({Pt{10, 10}}, {Pt{0, 0}}, 48.0);
	CHECK(dot.touched);
	CHECK(dot.pieces.empty());
	const RubResult end = rub(line(0, 1000, 10), {Pt{0, 0}, Pt{24, 0}, Pt{48, 0}}, 48.0);
	CHECK(end.touched);
	REQUIRE(end.pieces.size() == 1);
	CHECK(end.pieces[0].front() == Pt{96, 0});
	CHECK(end.pieces[0].back() == Pt{1000, 0});
	const RubResult all = rub(line(0, 100, 2), {Pt{0, 0}, Pt{50, 0}, Pt{100, 0}}, 48.0);
	CHECK(all.touched);
	CHECK(all.pieces.empty());
}

// CRT-04: the awake Moth's sight (Vision::lit_in_sight): line of sight with no cone, within a
// range by centre distance, lit to the threshold or glowing with egg-glow, searched sources left out.
#include "doctest.h"

#include "vision_fixture.h"

#include <map>

using namespace vision_fixture;

namespace {

std::map<Coord, Vision::SightTile> by_tile(const std::vector<Vision::SightTile> &v) {
	std::map<Coord, Vision::SightTile> out;
	for (const Vision::SightTile &t : v) {
		out[t.tile] = t;
	}
	return out;
}

} // namespace

TEST_CASE("lit tiles in sight, all round, within range, never through rock") {
	std::vector<std::string> rows(20, std::string(20, '.'));
	for (int64_t y = 0; y < 20; y++) {
		rows[y][14] = '#'; // a wall: x = 15..19 lie behind it
	}
	World w(1, rows);
	w.area({0, 0}, {19, 19}, 0.5);
	w.spot({2, 10}, 0.25);
	w.settle();
	const auto seen = by_tile(w.vision->lit_in_sight({10, 10}, 6.0, 300, {}));
	CHECK(seen.count({10, 10}) == 1);
	CHECK(seen.count({4, 10}) == 1); // behind it: no cone
	CHECK(seen.count({10, 4}) == 1);
	CHECK(seen.count({3, 10}) == 0); // 7 tiles: out of range
	CHECK(seen.count({16, 10}) == 0); // behind the wall
	for (const auto &[t, s] : seen) {
		const double dx = static_cast<double>(t.x - 10), dy = static_cast<double>(t.y - 10);
		CHECK(dx * dx + dy * dy <= 36.0);
		CHECK(s.value >= 300);
	}
}

TEST_CASE("below the threshold is unseen unless it is egg-glow; searched sources drop out") {
	World w(1);
	w.spot({12, 10}, 0.25);
	const uint32_t egg = w.spot({8, 10}, 0.05, ColourClass::EGG_GLOW);
	const uint32_t lamp = w.spot({10, 12}, 0.8);
	const uint32_t emergency = w.area({9, 8}, {11, 8}, 0.6, ColourClass::WHITE);
	w.settle();
	auto seen = by_tile(w.vision->lit_in_sight({10, 10}, 10.0, 300, {}));
	CHECK(seen.count({12, 10}) == 0);
	REQUIRE(seen.count({8, 10}) == 1);
	CHECK(seen[{8, 10}].source == egg);
	CHECK(seen[{8, 10}].colour == static_cast<uint8_t>(ColourClass::EGG_GLOW));
	REQUIRE(seen.count({10, 12}) == 1);
	CHECK(seen[{10, 12}].source == lamp);
	CHECK(seen.count({10, 8}) == 1);
	seen = by_tile(w.vision->lit_in_sight({10, 10}, 10.0, 300, {emergency}));
	CHECK(seen.count({10, 8}) == 0); // the searched emergency light is gone
	CHECK(seen.count({10, 12}) == 1); // the lamp stays
	const auto pair = w.light->value_excluding({10, 8}, {emergency});
	CHECK(pair.first == 0);
	CHECK(pair.second == 0);
}

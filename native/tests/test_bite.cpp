// VIS-10: the Stythe's bite (thresholds, the Thin, floor only, entities taken, bite_seen), the blood
// trail's direction bits and the egg-glow hatch bit.
#include "doctest.h"

#include "core/vision/bite.h"
#include "vision_fixture.h"

#include <set>

using namespace vision_fixture;
namespace flag = lb::core::light::flag;

namespace {

std::set<Coord> frame_tiles(const PerceptionFrame &f) {
	std::set<Coord> out;
	for (const FrameTile &t : f.tiles) {
		out.insert(t.tile);
	}
	return out;
}

} // namespace

TEST_CASE("the bite: floor tiles in the 3x3 block lit below 0.30") {
	World w(1);
	w.area({11, 8}, {13, 10}, 0.2);
	w.spot({13, 10}, 0.15); // 0.35 in all: stays
	w.settle();
	const std::set<Coord> bite = bite_tiles(w.mine, *w.light, 12.5, 9.5, 1, 300);
	CHECK(bite.size() == 8);
	CHECK(bite.count({13, 10}) == 0);
	CHECK(bite.count({12, 9}) == 1);
	CHECK(bite.count({14, 9}) == 0); // beyond 1 tile
	// The Thin bites below 0.50: the 0.35 tile goes too.
	CHECK(bite_tiles(w.mine, *w.light, 12.5, 9.5, 1, 500).size() == 9);
}

TEST_CASE("the bite never takes rock") {
	std::vector<std::string> rows(lb::core::world::CELL_TILES, std::string(lb::core::world::CELL_TILES, '.'));
	rows[8] = std::string(lb::core::world::CELL_TILES, '#');
	World w(1, rows);
	w.settle();
	const std::set<Coord> bite = bite_tiles(w.mine, *w.light, 12.5, 9.5, 1, 300);
	CHECK(bite.size() == 6); // the row above is rock
	CHECK(bite.count({12, 8}) == 0);
}

TEST_CASE("a bitten tile leaves the seen set with anything on it; bite_seen says so") {
	World w(1);
	w.area({10, 8}, {16, 12}, 0.2);
	w.settle();
	Vision &v = *w.vision;
	v.set_observer(1, 1, 10.5, 10.5, EAST);
	v.set_observer(2, 2, 10.5, 10.5, WEST);
	const std::set<Coord> bite = bite_tiles(w.mine, *w.light, 13.5, 10.5, 1, 300);
	v.set_bite_tiles(1, bite);
	v.set_bite_tiles(2, bite);
	const PerceptionFrame f = v.compute(1, {entity(5, STYTHE, 13.5, 10.5), entity(6, MINER, 12.5, 10.5)});
	for (const Coord &t : bite) {
		CHECK(frame_tiles(f).count(t) == 0);
	}
	CHECK(frame_tiles(f).count({15, 10}) == 1); // beyond the bite, still seen
	CHECK(f.tokens.empty()); // the Stythe and the victim beside it, both gone
	CHECK(f.margin_tokens.empty());
	CHECK(v.bite_seen(1)); // it would have seen them
	v.compute(2, {});
	CHECK_FALSE(v.bite_seen(2)); // facing away: nothing taken from it
	v.set_bite_tiles(1, {});
	v.compute(1, {});
	CHECK_FALSE(v.bite_seen(1));
}

TEST_CASE("a trail's direction rides with the blood bit at 0.12, never below") {
	World w(1);
	w.spot({12, 10}, 0.12);
	w.spot({13, 10}, 0.11);
	w.settle();
	Vision &v = *w.vision;
	v.set_decals({12, 10}, static_cast<uint8_t>(DECAL_BLOOD | (5 << DECAL_DIR_SHIFT)));
	v.set_decals({13, 10}, static_cast<uint8_t>(DECAL_BLOOD | (2 << DECAL_DIR_SHIFT)));
	v.set_observer(1, 1, 10.5, 10.5, EAST);
	bool found = false;
	for (const FrameTile &t : v.compute(1, {}).tiles) {
		if (t.tile == Coord{12, 10}) {
			CHECK((t.decals & DECAL_BLOOD) != 0);
			CHECK(((t.decals & DECAL_DIR_MASK) >> DECAL_DIR_SHIFT) == 5);
			found = true;
		}
		CHECK(t.tile != Coord{13, 10}); // 0.11: not even seen
	}
	CHECK(found);
}

TEST_CASE("the hatch bit marks egg-glow tiles only while the hatch tell is raised") {
	World w(1);
	const uint32_t glow = w.spot({12, 10}, 0.2, ColourClass::EGG_GLOW);
	w.spot({13, 10}, 0.2, ColourClass::AMBER);
	w.settle();
	Vision &v = *w.vision;
	v.set_observer(1, 1, 10.5, 10.5, EAST);
	auto colour_at = [&](Coord c) {
		for (const FrameTile &t : v.compute(1, {}).tiles) {
			if (t.tile == c) {
				return static_cast<int>(t.colour);
			}
		}
		return -1;
	};
	CHECK(colour_at({12, 10}) == static_cast<int>(ColourClass::EGG_GLOW));
	w.light->set_flags(glow, flag::HATCH_TELL);
	w.settle();
	CHECK(colour_at({12, 10}) == (static_cast<int>(ColourClass::EGG_GLOW) | COLOUR_HATCH_BIT));
	CHECK(colour_at({13, 10}) == static_cast<int>(ColourClass::AMBER)); // amber never carries it
}

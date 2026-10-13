// VIS-04: the hidden margin beyond a miner's own light: the bands, the cone, the bite,
// modifiers, no light, and a property test that wider margins never reach the blind area.
#include "doctest.h"

#include "vision_fixture.h"

#include <cmath>
#include <set>

using namespace vision_fixture;

namespace {

// A miner (entity 1) at (10.5, 10.5) facing east, carrying a lamp of radius r.
uint32_t lamp_for(World &w, double radius) {
	SourceDesc d;
	d.shape = Shape::POINT;
	d.kind = "gauze_lamp";
	d.owner = 1;
	d.radius = radius;
	d.peak = 1.0;
	d.x = 10.5;
	d.y = 10.5;
	return w.light->add_source(d);
}

std::set<Coord> margin_of(const PerceptionFrame &f) {
	return std::set<Coord>(f.margin_tiles.begin(), f.margin_tiles.end());
}

double dist(Coord t) {
	return std::sqrt((t.x + 0.5 - 10.5) * (t.x + 0.5 - 10.5) + (t.y + 0.5 - 10.5) * (t.y + 0.5 - 10.5));
}

} // namespace

TEST_CASE("geometry 2 tiles and entities 1 tile beyond a normal lamp's edge, inside the cone") {
	World w(2);
	lamp_for(w, 4.0);
	w.settle();
	Vision &v = *w.vision;
	v.set_observer(1, 1, 10.5, 10.5, EAST);
	const std::vector<MirrorEntity> es = {entity(1, MINER, 10.5, 10.5), entity(2, MINER, 15.0, 10.5), entity(3, MINER, 16.0, 10.5),
		entity(4, MINER, 12.0, 10.5)};
	const PerceptionFrame f = v.compute(1, es);
	const std::set<Coord> m = margin_of(f);
	REQUIRE(!m.empty());
	for (const Coord &t : m) {
		CHECK(dist(t) > 4.0);
		CHECK(dist(t) <= 6.0);
		CHECK(Cone::make(10.5, 10.5, EAST, 110.0).contains_tile(t.x, t.y));
	}
	CHECK(m.count({15, 10}) == 1); // 5.0 tiles
	CHECK(m.count({16, 10}) == 1); // 6.0
	CHECK(m.count({17, 10}) == 0); // 7.0: nothing farther
	CHECK(m.count({13, 10}) == 0); // inside the pool: seen, not margin
	REQUIRE(f.margin_tokens.size() == 1);
	CHECK(f.margin_tokens[0].entity == 2); // 4.5 tiles: inside the entity band
	CHECK(f.margin_tokens[0].size == SizeClass::MINER); // fringe form only
	CHECK(f.identified == std::vector<uint32_t>{4}); // the one in the pool is seen as usual
}

TEST_CASE("never the blind area, a bite tile or anything on one") {
	World w(2);
	lamp_for(w, 4.0);
	w.settle();
	Vision &v = *w.vision;
	v.set_observer(1, 1, 10.5, 10.5, EAST);
	v.set_bite_tiles(1, {Coord{15, 10}});
	const PerceptionFrame f = v.compute(1, {entity(1, MINER, 10.5, 10.5), entity(2, MINER, 15.5, 10.5), entity(3, MINER, 5.5, 10.5)});
	for (const Coord &t : margin_of(f)) {
		CHECK(Cone::make(10.5, 10.5, EAST, 110.0).contains_tile(t.x, t.y));
		CHECK_FALSE(t == Coord{15, 10});
	}
	CHECK(f.margin_tokens.empty()); // one stands in the bite, the other behind the miner
}

TEST_CASE("guttered, the margin starts at the shrunken edge") {
	World w(2);
	const uint32_t id = lamp_for(w, 4.0);
	w.light->set_radius_modifier(id, 0.7, "guttering");
	w.settle();
	Vision &v = *w.vision;
	v.set_observer(1, 1, 10.5, 10.5, EAST);
	const std::set<Coord> m = margin_of(v.compute(1, {}));
	for (const Coord &t : m) {
		CHECK(dist(t) > 2.8);
		CHECK(dist(t) <= 4.8);
	}
	CHECK(m.count({13, 10}) == 1); // 3.0: margin once guttered
}

TEST_CASE("no light of your own, no margin") {
	World w(2);
	w.area({0, 0}, {39, 39}, 0.05); // dim, so the tiles are dark but in sight
	w.settle();
	Vision &v = *w.vision;
	v.set_observer(1, 1, 10.5, 10.5, EAST);
	CHECK(v.compute(1, {}).margin_tiles.empty());
	SourceDesc shut;
	shut.shape = Shape::POINT;
	shut.owner = 1;
	shut.radius = 0.0; // shuttered
	shut.x = 10.5;
	shut.y = 10.5;
	w.light->add_source(shut);
	w.settle();
	CHECK(v.compute(1, {}).margin_tiles.empty());
}

TEST_CASE("property: raising the margin keys never adds a blind-area or bite record") {
	for (double widen = 1.0; widen <= 12.0; widen += 1.0) {
		World w(2);
		lamp_for(w, 4.0);
		w.settle();
		Vision &v = *w.vision;
		v.params.margin_geometry = widen;
		v.params.margin_entity = widen;
		for (uint32_t facing : {EAST, SOUTH, 12345u, 50000u}) {
			v.set_observer(1, 1, 10.5, 10.5, facing);
			v.set_bite_tiles(1, {Coord{13, 13}, Coord{8, 12}});
			std::vector<MirrorEntity> es = {entity(1, MINER, 10.5, 10.5)};
			for (uint32_t i = 0; i < 40; i++) {
				es.push_back(entity(10 + i, MINER, 2.5 + (i % 8) * 2.0, 2.5 + (i / 8) * 4.0));
			}
			const PerceptionFrame f = v.compute(1, es);
			const Cone cone = Cone::make(10.5, 10.5, facing, 110.0);
			for (const Coord &t : f.margin_tiles) {
				CHECK(cone.contains_tile(t.x, t.y));
				CHECK_FALSE((t == Coord{13, 13} || t == Coord{8, 12}));
			}
			for (const FrameToken &tk : f.margin_tokens) {
				CHECK(cone.contains(tk.x, tk.y));
			}
		}
	}
}

TEST_CASE("is_seen_or_margin_of_any covers every margin tile of every miner") {
	World w(2);
	lamp_for(w, 4.0);
	w.settle();
	Vision &v = *w.vision;
	v.set_observer(1, 1, 10.5, 10.5, EAST);
	const PerceptionFrame f = v.compute(1, {});
	REQUIRE(!f.margin_tiles.empty());
	for (const Coord &t : f.margin_tiles) {
		CHECK(v.is_seen_or_margin_of_any(t));
	}
	CHECK_FALSE(v.is_seen_or_margin_of_any({0, 10})); // behind the miner
	CHECK_FALSE(v.is_seen_or_margin_of_any({20, 10})); // beyond the margin
}

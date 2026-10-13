// VIS-03: size classes, the shared motionless class, small things and footprints.
#include "doctest.h"

#include "vision_fixture.h"

using namespace vision_fixture;

TEST_CASE("a heap of coats and a sleeping Moth in the same fringe give identical tokens") {
	World w(1);
	w.spot({13, 10}, 0.2);
	w.spot({13, 12}, 0.2);
	w.settle();
	Vision &v = *w.vision;
	v.set_observer(1, 1, 10.5, 11.5, EAST);
	const PerceptionFrame heap = v.compute(1, {entity(7, COAT_HEAP, 13.5, 10.5)});
	const PerceptionFrame moth = v.compute(1, {entity(9, MOTH, 13.5, 10.5, 1)}); // motionless flag: asleep
	REQUIRE(heap.tokens.size() == 1);
	REQUIRE(moth.tokens.size() == 1);
	CHECK(heap.tokens[0] == moth.tokens[0]);
	CHECK(heap.tokens[0].size == SizeClass::LARGE_MOTIONLESS);
	const PerceptionFrame awake = v.compute(1, {entity(9, MOTH, 13.5, 10.5, 0)});
	CHECK(awake.tokens[0].size == SizeClass::LARGE);
}

TEST_CASE("small things: absent at 0.29, shown at 0.30, never a token") {
	World w(1);
	w.spot({12, 10}, 0.29);
	w.spot({12, 11}, 0.30);
	w.settle();
	Vision &v = *w.vision;
	v.set_observer(1, 1, 10.5, 10.5, EAST);
	const PerceptionFrame f = v.compute(1, {entity(2, ITEM, 12.5, 10.5), entity(3, ITEM, 12.5, 11.5)});
	CHECK(f.tokens.empty());
	CHECK(f.identified == std::vector<uint32_t>{3});
}

TEST_CASE("a large entity takes the brightest tile under its footprint") {
	World w(1);
	w.spot({13, 10}, 0.35);
	w.settle();
	Vision &v = *w.vision;
	PerceptionClass big;
	big.size = SizeClass::LARGE;
	big.footprint = 2;
	v.table.set(MOTH, big);
	v.set_observer(1, 1, 10.5, 10.5, EAST);
	// Centred on the corner of (12..13, 10..11): one bright tile under it.
	CHECK(v.sees_entity(1, entity(2, MOTH, 13.0, 11.0)) == Level::IDENTITY);
	CHECK(v.sees_entity(1, entity(2, MINER, 13.0, 11.0)) == Level::NONE); // a 1-tile miner stands in (13, 11): dark
}

TEST_CASE("an identity threshold override (the Thin Stythe's hook)") {
	World w(1);
	w.spot({12, 10}, 0.4);
	w.settle();
	Vision &v = *w.vision;
	v.set_observer(1, 1, 10.5, 10.5, EAST);
	const MirrorEntity s = entity(5, STYTHE, 12.5, 10.5);
	CHECK(v.sees_entity(1, s) == Level::IDENTITY);
	v.set_identity_threshold(5, 500);
	CHECK(v.sees_entity(1, s) == Level::TOKEN);
	v.set_identity_threshold(5, -1);
	CHECK(v.sees_entity(1, s) == Level::IDENTITY);
}

TEST_CASE("a NONE kind is never perceived as an entity") {
	World w(1);
	w.spot({12, 10}, 1.0);
	w.settle();
	w.vision->set_observer(1, 1, 10.5, 10.5, EAST);
	CHECK(w.vision->sees_entity(1, entity(2, 8, 12.5, 10.5)) == Level::NONE); // a gate
}

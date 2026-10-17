// GEN-12: each of the validator's rules and supporting checks rejects its failing fixture with its
// number and the offending tile, and passes its passing one.

#include "validate_fixture.h"

#include <doctest.h>

using namespace validate_fixture;
using lb::core::world::Coord;

namespace {

void set(Spec &s, int x, int y, char ch) {
	s.rows[static_cast<size_t>(y)][static_cast<size_t>(x)] = ch;
}

Verdict layout_verdict(const Layout &l, const CellClass &cls = biome_class(), const ValidatorParams &p = params()) {
	return validate_layout(l, cls, p);
}

// GEN-10's fixture world, every cell GEN-04's base cell fitted to the sockets its stubs cover.
struct Fixture {
	place_fixture::World world;
	PlacementParams pp;
	ValidatorParams vp;
	Fixture() {
		world.head = layout_fixture::header(17);
		world.proto = place_fixture::prototype();
		world.proto.sockets = base_sockets();
	}
	PlacementContext context(Coord cell) const { return placement_context(world, pp, vp, cell); }
};

Placement area(PlacedKind kind, Coord tile, int32_t w, int32_t h, const std::string &source = "test") {
	Placement x;
	x.kind = kind;
	x.tile = tile;
	x.w = w;
	x.h = h;
	x.source = source;
	return x;
}

Placement item(Coord tile, const std::string &thing, const std::string &source) {
	Placement x = area(PlacedKind::ITEM, tile, 1, 1, source);
	x.thing = thing;
	return x;
}

// A fixture world whose every cell is GEN-04's plain fallback (roads on every stub line), every
// socket open at 10, 3 wide: each gate road leads on.
place_fixture::World grid_world() {
	place_fixture::World w;
	w.head = layout_fixture::header(17);
	w.proto.cell = cell_of(fallback_spec());
	w.proto.template_id = "fixture_seam_fallback";
	for (int e = 0; e < 4; e++) {
		w.proto.sockets[static_cast<size_t>(e)] = open_socket(10, 3);
	}
	return w;
}

// GEN-04's base cell with a south throat at 10 through its chamber, open on all four sides.
Layout through_cell() {
	Spec s;
	s.anchors = place_fixture::place_anchors();
	s.rows[19][10] = '.';
	Layout l;
	l.template_id = s.id;
	l.cell = cell_of(s);
	l.sockets = base_sockets();
	l.sockets[static_cast<size_t>(Edge::SOUTH)] = open_socket(10, 1);
	return l;
}

// The base cell's collapse alternate (id 1, the north road's tile (10, 5)) armed in `cell`.
Placement collapse(Coord cell) {
	Placement x = area(PlacedKind::COLLAPSE, at(cell, 10, 5), 1, 1, "collapse");
	x.collapse = 1;
	return x;
}

} // namespace

TEST_CASE("GEN-12 phase 1 passes GEN-04's base cell fitted to its sockets") {
	const Verdict v = layout_verdict(fitted(Spec{}));
	CHECK_MESSAGE(v.ok(), describe(v));
	CHECK(describe(v) == "ok");
}

TEST_CASE("GEN-12 rule 4: chambers 5-8 across, never 4; roads 1-3") {
	Spec four;
	for (int y = 13; y <= 16; y++) {
		for (int x = 1; x <= 4; x++) {
			set(four, x, y, '.');
		}
	}
	set(four, 2, 12, '.');
	const Verdict v = layout_verdict(fitted(four));
	REQUIRE(v.check == Check::WIDTHS);
	CHECK(v.number() == 4);
	CHECK(v.tile.x >= at({3, 7}, 1, 13).x);
	CHECK(v.tile.x <= at({3, 7}, 4, 16).x);
	CHECK(v.tile.y >= at({3, 7}, 1, 13).y);
	CHECK(v.tile.y <= at({3, 7}, 4, 16).y);
	CHECK(describe(v).rfind("rule 4 (widths) at (", 0) == 0);
	Spec small;
	small.anchors[0] = anchor(AnchorType::CHAMBER, 7, 13, 4, 4);
	CHECK(layout_verdict(fitted(small)).check == Check::WIDTHS);
}

TEST_CASE("GEN-12 check 7: the floor one piece after stub fill") {
	Spec s;
	set(s, 2, 16, '.');
	const Verdict v = layout_verdict(fitted(s));
	REQUIRE(v.check == Check::CONNECTED);
	CHECK(v.number() == 7);
	CHECK(v.tile == at({3, 7}, 2, 16));
}

TEST_CASE("GEN-12 check 8: every open socket's throat as wide as the socket, no floor at a shut one") {
	Layout narrow = fitted(Spec{});
	narrow.sockets[static_cast<size_t>(Edge::EAST)].width = 1; // the throat stayed 3 wide
	Verdict v = layout_verdict(narrow);
	REQUIRE(v.check == Check::THROATS);
	CHECK(v.number() == 8);
	CHECK(v.tile == at({3, 7}, 19, 9));
	Layout shut = fitted(Spec{});
	shut.sockets[static_cast<size_t>(Edge::WEST)] = Socket{}; // floor left at a shut edge
	v = layout_verdict(shut);
	REQUIRE(v.check == Check::THROATS);
	CHECK(v.tile == at({3, 7}, 0, 9));
	Layout missing = fitted(Spec{});
	missing.sockets[static_cast<size_t>(Edge::SOUTH)] = open_socket(5, 1); // open where no floor is
	v = layout_verdict(missing);
	REQUIRE(v.check == Check::THROATS);
	CHECK(v.tile == at({3, 7}, 5, 19));
	// Fitted to a narrower socket, the throat narrows with it.
	CellSockets two = base_sockets();
	two[static_cast<size_t>(Edge::EAST)].width = 2;
	CHECK(layout_verdict(fitted(Spec{}, two)).ok());
}

TEST_CASE("GEN-12 check 9: every road tile within the Tapper's reach of a face, brick excepted") {
	Spec timber;
	for (int x = 1; x <= 7; x++) {
		set(timber, x, 8, 'T');
		set(timber, x, 12, 'T');
	}
	const Verdict v = layout_verdict(fitted(timber));
	REQUIRE(v.check == Check::TAPPER_REACH);
	CHECK(v.number() == 9);
	CHECK(v.tile.x >= at({3, 7}, 1, 9).x);
	CHECK(v.tile.x <= at({3, 7}, 7, 11).x);
	CHECK(v.tile.y >= at({3, 7}, 1, 9).y);
	CHECK(v.tile.y <= at({3, 7}, 7, 11).y);
	Spec brick;
	for (int x = 1; x <= 7; x++) {
		set(brick, x, 8, 'B');
		set(brick, x, 12, 'B');
	}
	CHECK(layout_verdict(fitted(brick)).ok());
}

TEST_CASE("GEN-12 check 10: exactly one landmark site") {
	Spec none;
	none.anchors.erase(std::remove_if(none.anchors.begin(), none.anchors.end(), [](const Anchor &a) { return a.type == AnchorType::LANDMARK; }),
			none.anchors.end());
	Verdict v = layout_verdict(fitted(none));
	REQUIRE(v.check == Check::LANDMARK);
	CHECK(v.number() == 10);
	Spec two;
	two.anchors.push_back(anchor(AnchorType::LANDMARK, 15, 10, 1, 1, "broken_tub"));
	v = layout_verdict(fitted(two));
	REQUIRE(v.check == Check::LANDMARK);
	CHECK(v.tile == at({3, 7}, 15, 10));
}

TEST_CASE("GEN-12 check 11: no door on the arch past base camp's gate") {
	Spec door;
	for (int y = 9; y <= 11; y++) {
		set(door, 4, y, 'D');
	}
	// The cell east of base camp: its west socket faces the gate.
	const Coord gate_cell{1, 0};
	ValidatorParams p;
	p.arch_reach[static_cast<size_t>(Edge::EAST)] = 8;
	const Layout l = fitted(door, base_sockets(), gate_cell);
	Verdict v = layout_verdict(l, biome_class(), p);
	REQUIRE(v.check == Check::ARCHES);
	CHECK(v.number() == 11);
	CHECK(v.tile == at(gate_cell, 4, 9));
	// The arch ends 4 tiles in: the door beyond it stands.
	p.arch_reach[static_cast<size_t>(Edge::EAST)] = 4;
	CHECK(layout_verdict(l, biome_class(), p).ok());
	// No arch runs into any other cell.
	p.arch_reach[static_cast<size_t>(Edge::EAST)] = 8;
	CHECK(layout_verdict(fitted(door), biome_class(), p).ok());
	CHECK(gate_arch_tiles(fitted(Spec{}, base_sockets(), gate_cell), p).size() > 3 * 7);
}

TEST_CASE("GEN-12 rule 5: a point of interest's door on an open socket, and the lair on its door's alone") {
	const Template pump = make(poi_spec());
	CellClass cls;
	cls.kind = TemplateKind::POI;
	cls.biome = "seam";
	cls.poi_template = &pump;
	CellSockets open{};
	open[static_cast<size_t>(Edge::NORTH)] = open_socket(10, 1);
	CHECK(layout_verdict(fitted(pump, open, {4, 4}), cls).ok());
	Verdict v = layout_verdict(fitted(pump, CellSockets{}, {4, 4}), cls);
	REQUIRE(v.check == Check::POI_SOCKETS);
	CHECK(v.number() == 5);
	CHECK(v.tile == at({4, 4}, 10, 0));
	// A lair with a second stub east (at 5, off its room): open, its blood trails would part.
	Spec lair_spec = poi_spec();
	lair_spec.id = "fixture_lair";
	lair_spec.poi_kind = "lair";
	for (int x = 13; x < 20; x++) {
		set(lair_spec, x, 5, '.');
	}
	lair_spec.stubs.push_back(stub(Edge::EAST, 5, 1));
	const Template lair = make(lair_spec);
	cls.poi_template = &lair;
	CellSockets two = open;
	two[static_cast<size_t>(Edge::EAST)] = open_socket(5, 1);
	v = layout_verdict(fitted(lair, two, {4, 4}), cls);
	REQUIRE(v.check == Check::POI_SOCKETS);
	CHECK(v.tile == at({4, 4}, 19, 5));
	CHECK(layout_verdict(fitted(lair, open, {4, 4}), cls).ok());
}

TEST_CASE("GEN-12 phase 2 passes GEN-10's placements") {
	Fixture f;
	for (Coord cell : {Coord{5, 3}, Coord{2, 2}, Coord{-4, 6}, Coord{9, -9}}) {
		const PlacementContext c = f.context(cell);
		const Verdict v = validate_placement(c, place_cell(f.world, f.pp, cell));
		CHECK_MESSAGE(v.ok(), describe(v));
	}
}

TEST_CASE("GEN-12 rule 1: no gas or trap in ring 0, no collapse point within 7 tiles by path of a phone or a door") {
	Fixture f;
	const Coord near{2, 2}; // ring 0
	REQUIRE(f.world.facts(near).ring == 0);
	PlacementContext c = f.context(near);
	for (PlacedKind kind : {PlacedKind::FIREDAMP, PlacedKind::BLACKDAMP, PlacedKind::MAN_TRAP, PlacedKind::STAPLE_PIT, PlacedKind::SUMP_MUD}) {
		const Verdict v = validate_placement(c, {area(kind, at(near, 7, 13), 1, 1)});
		REQUIRE(v.check == Check::NEAR_HOME);
		CHECK(v.number() == 1);
		CHECK(v.tile == at(near, 7, 13));
	}
	const Coord far{5, 3};
	REQUIRE(f.world.facts(far).ring >= 1);
	c = f.context(far);
	c.phones.clear();
	c.doors.clear();
	CHECK(validate_placement(c, {collapse(far)}).ok());
	c.phones = {at(far, 9, 7)}; // a wall fixture beside the north road, 3 steps from the fall
	Verdict v = validate_placement(c, {collapse(far)});
	REQUIRE(v.check == Check::NEAR_HOME);
	CHECK(v.tile == at(far, 9, 7));
	c.phones = {at(far, 9, 12)}; // 8 steps: along the road and onto the fixture
	CHECK(validate_placement(c, {collapse(far)}).ok());
	c.phones.clear();
	c.doors = {at(far, 10, 0)}; // a door 5 tiles up the road
	v = validate_placement(c, {collapse(far)});
	REQUIRE(v.check == Check::NEAR_HOME);
	CHECK(v.tile == at(far, 10, 0));
}

TEST_CASE("GEN-12 rule 2: no required item in gas, no gas on a spine, no remains in blackdamp") {
	Fixture f;
	const Coord cell{9, -9};
	PlacementContext c = f.context(cell);
	const Coord t = at(cell, 9, 15);
	const Placement gas = area(PlacedKind::FIREDAMP, at(cell, 7, 13), 6, 6);
	Verdict v = validate_placement(c, {item(t, "fuse", "poi"), gas});
	REQUIRE(v.check == Check::GAS);
	CHECK(v.number() == 2);
	CHECK(v.tile == t);
	CHECK(validate_placement(c, {gas, item(t, "revolver", "plan")}).check == Check::GAS);
	CHECK(validate_placement(c, {item(t, "flare", "remains"), gas}).ok()); // a man's own flare may lie in gas
	Placement man = area(PlacedKind::REMAINS, t, 1, 1, "remains");
	v = validate_placement(c, {man, area(PlacedKind::BLACKDAMP, at(cell, 7, 13), 6, 6)});
	REQUIRE(v.check == Check::GAS);
	CHECK(v.tile == t);
	CHECK(validate_placement(c, {man, gas}).ok()); // firedamp is no blackdamp
	f.world.spine = [cell](Coord x) { return x == cell; };
	c = f.context(cell);
	v = validate_placement(c, {gas});
	REQUIRE(v.check == Check::GAS);
	CHECK(v.tile == gas.tile);
}

TEST_CASE("GEN-12 check 12: collapse points 12 or more apart and beyond 20 tiles of base camp") {
	Fixture f;
	const Coord near{1, 1};
	PlacementContext c = f.context(near);
	c.neighbour_collapses.clear();
	c.phones.clear();
	c.doors.clear();
	Verdict v = validate_placement(c, {collapse(near)});
	REQUIRE(v.check == Check::COLLAPSE_SPACING);
	CHECK(v.number() == 12);
	CHECK(v.tile == at(near, 10, 5));
	const Coord far{5, 3};
	c = f.context(far);
	c.phones.clear();
	c.doors.clear();
	c.neighbour_collapses = {{at(far, 10, 5 - 11)}};
	v = validate_placement(c, {collapse(far)});
	REQUIRE(v.check == Check::COLLAPSE_SPACING);
	CHECK(v.tile == at(far, 10, 5));
	c.neighbour_collapses = {{at(far, 10, 5 - 12)}};
	CHECK(validate_placement(c, {collapse(far)}).ok());
}

TEST_CASE("GEN-12 check 13: no collapse point armed on a spine cell") {
	Fixture f;
	const Coord cell{5, 3};
	f.world.spine = [cell](Coord x) { return x == cell; };
	const Verdict v = validate_placement(f.context(cell), {collapse(cell)});
	REQUIRE(v.check == Check::SPINE_COLLAPSE);
	CHECK(v.number() == 13);
	CHECK(v.tile == at(cell, 10, 5));
}

TEST_CASE("GEN-12 check 14: nothing on an armed collapse point's tiles or in base camp") {
	Fixture f;
	const Coord cell{5, 3};
	PlacementContext c = f.context(cell);
	c.phones.clear();
	c.doors.clear();
	c.neighbour_collapses.clear();
	Verdict v = validate_placement(c, {collapse(cell), item(at(cell, 10, 5), "candle", "remains")});
	REQUIRE(v.check == Check::CLEAR_GROUND);
	CHECK(v.number() == 14);
	CHECK(v.tile == at(cell, 10, 5));
	CHECK(validate_placement(c, {item(at(cell, 10, 5), "candle", "remains"), collapse(cell)}).check == Check::CLEAR_GROUND);
	CHECK(validate_placement(c, {collapse(cell), item(at(cell, 10, 6), "candle", "remains")}).ok());
	const PlacementContext camp = f.context({0, 0});
	v = validate_placement(camp, {item({4, 4}, "candle", "loose")});
	REQUIRE(v.check == Check::CLEAR_GROUND);
	CHECK(v.tile == Coord{4, 4});
}

TEST_CASE("GEN-12 check 11 in phase 2: no air door on the arch past base camp's gate") {
	Fixture f;
	const Coord gate_cell{1, 0};
	f.vp.arch_reach[static_cast<size_t>(Edge::EAST)] = 8;
	const PlacementContext c = f.context(gate_cell);
	REQUIRE(!c.arch.empty());
	const Verdict v = validate_placement(c, {area(PlacedKind::AIR_DOOR, at(gate_cell, 5, 9), 1, 3, "door")});
	REQUIRE(v.check == Check::ARCHES);
	CHECK(v.number() == 11);
	CHECK(v.tile == at(gate_cell, 5, 9));
	CHECK(validate_placement(c, {area(PlacedKind::AIR_DOOR, at(gate_cell, 15, 9), 1, 3, "door")}).ok());
}

TEST_CASE("GEN-12 rule 3: base camp's three gates open onto three roads") {
	const place_fixture::World grid = grid_world();
	CHECK_MESSAGE(check_gates(grid).ok(), describe(check_gates(grid)));
	// All four sides open: no blind side.
	place_fixture::World four = grid;
	for (int e = 0; e < 4; e++) {
		four.head.forced.set(edge_of({0, 0}, static_cast<Edge>(e)), open_socket(10, 3));
	}
	Verdict v = check_gates(four);
	REQUIRE(v.check == Check::GATES);
	CHECK(v.number() == 3);
	CHECK(v.tile == at({0, 0}, 10, 10));
	// Roads that lead nowhere: every cell shut but toward base camp's east gate.
	place_fixture::World blind = grid;
	for (int e = 0; e < 4; e++) {
		blind.proto.sockets[static_cast<size_t>(e)] = static_cast<Edge>(e) == Edge::WEST ? open_socket(10, 3) : Socket{};
	}
	v = check_gates(blind);
	REQUIRE(v.check == Check::GATES);
	CHECK(v.number() == 3);
}

TEST_CASE("GEN-12 rule 6: every spine reaches its target") {
	const auto run = planned_run(11, 1);
	REQUIRE(run->head().plan.error.empty());
	REQUIRE(!run->head().plan.spines.empty());
	for (size_t i = 0; i < run->head().plan.spines.size(); i++) {
		const Verdict v = walk_spine(*run->world, run->pp, run->vp, run->head().plan, i);
		CHECK_MESSAGE(v.ok(), describe(v));
	}
	// A spine blocked by a collapse point armed on it: GEN-04's base cell everywhere, each north
	// road's alternate armed (a bug), and a spine east from the east gate then north through one.
	Fixture f;
	f.pp.collapse_ppm = 1000000;
	f.pp.phone_ring12_ppm = 0;
	f.pp.phone_beyond_ppm = 0;
	f.world.proto = through_cell();
	RunPlan plan;
	PlannedSite site;
	site.kind = PoiKind::STORES;
	site.door = {3, -2};
	site.door_side = Edge::SOUTH;
	site.cells = {site.door};
	plan.sites.push_back(site);
	Spine sp;
	sp.site = 0;
	sp.gate = Edge::EAST;
	sp.cells = {{1, 0}, {2, 0}, {3, 0}, {3, -1}};
	plan.spines.push_back(sp);
	const Verdict v = walk_spine(f.world, f.pp, f.vp, plan, 0);
	REQUIRE(v.check == Check::SPINE_REACH);
	CHECK(v.number() == 6);
	CHECK(lb::core::world::cell_of(v.tile) == Coord{3, 0});
	f.pp.collapse_ppm = 0;
	CHECK_MESSAGE(walk_spine(f.world, f.pp, f.vp, plan, 0).ok(), describe(walk_spine(f.world, f.pp, f.vp, plan, 0)));
	CHECK(walk_spine(f.world, f.pp, f.vp, plan, 0, true).check == Check::SPINE_REACH); // every alternate fallen
}

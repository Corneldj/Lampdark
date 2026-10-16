// GEN-04: the template validator (a passing and a failing fixture per rule) and the zone cutter.

#include "core/sound/road_graph.h"
#include "core/sound/zone_block.h"
#include "template_fixture.h"

#include <doctest.h>

#include <algorithm>
#include <memory>

using namespace template_fixture;
using lb::core::sound::CellBlock;
using lb::core::sound::PortalKind;
using lb::core::sound::RoadGraph;
using lb::core::sound::ZoneKind;

namespace {

std::vector<Problem> run(const Template &t, const ValidateParams &p = ValidateParams{}) {
	return validate(t, p);
}

std::vector<Problem> run(const Spec &s, const ValidateParams &p = ValidateParams{}) {
	return validate(make(s), p);
}

// The rule's first problem (rule "" when there is none).
Problem first(const std::vector<Problem> &problems, const std::string &rule) {
	for (const Problem &p : problems) {
		if (p.rule == rule) {
			return p;
		}
	}
	return Problem{};
}

bool has(const std::vector<Problem> &problems, const std::string &rule, const std::string &part = "") {
	for (const Problem &p : problems) {
		if (p.rule == rule && p.message.find(part) != std::string::npos) {
			return true;
		}
	}
	return false;
}

std::string all(const Template &t, const std::vector<Problem> &problems) {
	std::string out;
	for (const Problem &p : problems) {
		out += describe(t, p) + "\n";
	}
	return out;
}

void set(Spec &s, int x, int y, char ch) {
	s.rows[static_cast<size_t>(y)][static_cast<size_t>(x)] = ch;
}

void drop_anchor(Spec &s, AnchorType type, int x, int y) {
	s.anchors.erase(std::remove_if(s.anchors.begin(), s.anchors.end(),
							[&](const Anchor &a) { return a.type == type && a.x == x && a.y == y; }),
			s.anchors.end());
}

CellBlock block_of(const std::vector<uint8_t> &bytes) {
	std::optional<CellBlock> b = lb::core::sound::decode_block(bytes);
	REQUIRE(b.has_value());
	return *b;
}

} // namespace

TEST_CASE("GEN-04 the fixtures pass every rule") {
	const Template base = make(Spec{});
	const std::vector<Problem> problems = run(base);
	CHECK_MESSAGE(problems.empty(), all(base, problems));
	const Template poi = make(poi_spec());
	const std::vector<Problem> poi_problems = run(poi, poi_params());
	CHECK_MESSAGE(poi_problems.empty(), all(poi, poi_problems));
	const Template fallback = make(fallback_spec());
	const std::vector<Problem> fallback_problems = run(fallback);
	CHECK_MESSAGE(fallback_problems.empty(), all(fallback, fallback_problems));
}

TEST_CASE("GEN-04 a problem names the template, the rule and the tile") {
	Spec s;
	set(s, 2, 16, '.');
	const Template t = make(s);
	const std::vector<Problem> problems = run(t);
	const Problem p = first(problems, "connected_floor");
	REQUIRE(p.rule == "connected_floor");
	CHECK(p.x == 2);
	CHECK(p.y == 16);
	CHECK(describe(t, p) == "template fixture_seam_01: connected_floor: cell (0, 0) tile (2, 16): floor not 4-connected to the rest with every collapse standing");
}

TEST_CASE("GEN-04 footprint: a rectangle of 1 or 2 cells a side with a cell for each place") {
	Template t = make(Spec{});
	t.footprint_w = 2;
	CHECK(has(run(t), "footprint"));
	t.footprint_w = 3;
	t.cells.push_back(t.cells[0]);
	t.cells.push_back(t.cells[0]);
	CHECK(has(run(t), "footprint"));
}

TEST_CASE("GEN-04 connected floor") {
	Spec s;
	set(s, 2, 16, '.');
	CHECK(has(run(s), "connected_floor"));
	CHECK_FALSE(has(run(Spec{}), "connected_floor"));
}

TEST_CASE("GEN-04 widths: roads 1-3, chambers 5-8 inside a chamber anchor, never 4") {
	CHECK_FALSE(has(run(Spec{}), "widths"));
	Spec four;
	for (int y = 13; y <= 16; y++) {
		for (int x = 1; x <= 4; x++) {
			set(four, x, y, '.');
		}
	}
	set(four, 2, 12, '.');
	CHECK(has(run(four), "widths", "floor 4 across"));
	Spec small;
	small.anchors[0] = anchor(AnchorType::CHAMBER, 7, 13, 4, 4);
	CHECK(has(run(small), "widths", "chamber anchor 4x4"));
	Spec unanchored;
	unanchored.anchors.erase(unanchored.anchors.begin());
	CHECK(has(run(unanchored), "widths", "floor 6 across"));
}

TEST_CASE("GEN-04 rib art: at most 0.25 tile and never on floor") {
	CHECK_FALSE(has(run(Spec{}), "rib_art"));
	Spec wide;
	wide.rib[0].milli = 300;
	CHECK(has(run(wide), "rib_art", "0.3 tile exceeds 0.25"));
	Spec on_floor;
	on_floor.rib[0].index = static_cast<uint16_t>(Cell::index_of(5, 10));
	CHECK(has(run(on_floor), "rib_art", "on a floor tile"));
}

TEST_CASE("GEN-04 Tapper reach: every road tile within 1.5 tiles of a strike face, brick-lined excepted") {
	CHECK_FALSE(has(run(Spec{}), "tapper_reach"));
	Spec timber;
	for (int x = 1; x <= 7; x++) {
		set(timber, x, 8, 'T');
		set(timber, x, 12, 'T');
	}
	const std::vector<Problem> problems = run(timber);
	REQUIRE(has(problems, "tapper_reach"));
	const Problem p = first(problems, "tapper_reach"); // timber is no face: the rock behind it is not reached
	CHECK(p.x >= 1);
	CHECK(p.x <= 7);
	CHECK(p.y >= 9);
	CHECK(p.y <= 11);
	Spec brick;
	for (int x = 1; x <= 7; x++) {
		set(brick, x, 8, 'B');
		set(brick, x, 12, 'B');
	}
	CHECK_FALSE(has(run(brick), "tapper_reach"));
}

TEST_CASE("GEN-04 stubs: offsets 5, 10, 15; width within the maximum; floor throats") {
	CHECK_FALSE(has(run(Spec{}), "stubs"));
	Spec offset;
	offset.stubs[2].offset = 7;
	CHECK(has(run(offset), "stubs", "offset 7"));
	Spec wide;
	wide.stubs[0].max_width = 4;
	CHECK(has(run(wide), "stubs", "width 4"));
	ValidateParams narrow_biome;
	narrow_biome.biome_stub_width_max = 2;
	CHECK(has(run(Spec{}, narrow_biome), "stubs", "width 3"));
	Spec rock;
	rock.stubs.push_back(stub(Edge::NORTH, 5, 1));
	CHECK(has(run(rock), "stubs", "throat tile is not floor"));
	Spec stray; // floor reaching the south edge with no stub there
	set(stray, 10, 19, '.');
	CHECK(has(run(stray), "stubs", "floor on the outer edge outside every stub's throat"));
	Spec twice;
	twice.stubs.push_back(stub(Edge::NORTH, 10, 1));
	CHECK(has(run(twice), "stubs", "two stubs at one edge position"));
	Spec shallow;
	shallow.stubs[2].depth = 0;
	CHECK(has(run(shallow), "stubs", "stub throat depth 0"));
}

TEST_CASE("GEN-04 stubs: filling any subset and narrowing any throat keep the floor connected") {
	Spec bridge; // a side road that hangs off the west throat
	for (int y = 6; y <= 8; y++) {
		set(bridge, 1, y, '.');
	}
	CHECK(has(run(bridge), "stubs", "filling stubs"));
	Spec pinch; // the throat's middle reaches the road only through its sides
	set(pinch, 2, 10, '#');
	const std::vector<Problem> problems = run(pinch);
	CHECK(has(problems, "stubs", "narrowing a stub to 1"));
	CHECK_FALSE(has(problems, "stubs", "filling stubs"));
}

TEST_CASE("GEN-04 zones and portals: full coverage, a fallen set for every collapse, no shortcuts") {
	CHECK_FALSE(has(run(Spec{}), "zones_portals"));
	Spec uncut;
	uncut.cut = false;
	CHECK(has(run(uncut), "zones_portals", "in no declared zone"));
	Template late = make(Spec{});
	late.cells[0].collapses.push_back(collapse(2, {{15, 13}}));
	CHECK(has(run(late), "zones_portals", "collapse 2 has no fallen zone and portal set"));
	Spec split; // two chamber anchors side by side: two zones touching with no portal
	split.anchors[0] = anchor(AnchorType::CHAMBER, 7, 13, 3, 6);
	split.anchors.push_back(anchor(AnchorType::CHAMBER, 10, 13, 3, 6));
	CHECK(has(run(split), "zones_portals", "touch with no portal"));
	Template mouth = make(Spec{});
	mouth.cells[0].tiles[static_cast<size_t>(Cell::index_of(0, 10))].zone = 0;
	CHECK(has(run(mouth), "zones_portals", "stub mouth without a zone"));
}

TEST_CASE("GEN-04 zones and portals: floor between a template's own cells crosses on zoned tiles") {
	Spec west;
	west.stubs = {stub(Edge::WEST, 10, 3)};
	west.collapses = {};
	west.rows[0][10] = '#';
	west.rows[1][10] = '#';
	Spec east = west;
	east.anchors = {anchor(AnchorType::TIMBER_HOOK, 2, 10), anchor(AnchorType::TIMBER_HOOK, 7, 10),
			anchor(AnchorType::TIMBER_HOOK, 12, 10), anchor(AnchorType::TIMBER_HOOK, 17, 10)};
	east.rows = {};
	for (int y = 0; y < 20; y++) {
		east.rows.push_back(y >= 9 && y <= 11 ? std::string(20, '.') : std::string(20, '#'));
	}
	Template t = make(west);
	t.id = "fixture_two_cells";
	t.footprint_w = 2;
	t.cells.push_back(cell_of(east, {1, 0}));
	t.stubs.push_back(stub(Edge::EAST, 10, 3, 2, false, {1, 0}));
	const std::vector<Problem> problems = run(t);
	CHECK_MESSAGE(!has(problems, "zones_portals"), all(t, problems));
	Template door = t;
	Spec east_door = east;
	east_door.rows[10][0] = 'D';
	door.cells[1] = cell_of(east_door, {1, 0});
	CHECK(has(run(door), "zones_portals", "crosses a cell edge at a portal tile"));
}

TEST_CASE("GEN-04 collapses: on road floor, clear of throats and fixtures, short, and choking") {
	CHECK_FALSE(has(run(Spec{}), "collapses"));
	Spec chamber;
	chamber.collapses = {collapse(1, {{9, 15}})};
	CHECK(has(run(chamber), "collapses", "off road floor"));
	Spec throat;
	throat.collapses = {collapse(1, {{10, 1}})};
	CHECK(has(run(throat), "collapses", "over a stub throat"));
	Spec door_site;
	door_site.anchors.push_back(anchor(AnchorType::DOOR_SITE, 10, 5));
	CHECK(has(run(door_site), "collapses", "over a door site or wall fixture"));
	Spec fixture;
	fixture.collapses = {collapse(1, {{16, 10}, {16, 11}, {16, 9}})};
	fixture.anchors.push_back(anchor(AnchorType::WALL_FIXTURE, 16, 9));
	CHECK(has(run(fixture), "collapses", "over a door site or wall fixture"));
	Spec long_fall;
	long_fall.collapses = {collapse(1, {{10, 3}, {10, 4}, {10, 5}, {10, 6}})};
	CHECK(has(run(long_fall), "collapses", "longer than 3"));
	Spec open;
	open.collapses = {collapse(1, {{5, 10}})};
	CHECK(has(run(open), "collapses", "does not choke"));
}

TEST_CASE("GEN-04 timber hooks: every road tile within 4 tiles, one in every chamber and point of interest") {
	CHECK_FALSE(has(run(Spec{}), "timber_hooks"));
	Spec far;
	drop_anchor(far, AnchorType::TIMBER_HOOK, 10, 4);
	CHECK(has(run(far), "timber_hooks", "more than 4 tiles by path"));
	Spec bare;
	drop_anchor(bare, AnchorType::TIMBER_HOOK, 8, 14);
	CHECK(has(run(bare), "timber_hooks", "a chamber without a timber hook"));
	Spec poi = poi_spec();
	drop_anchor(poi, AnchorType::TIMBER_HOOK, 10, 4);
	poi.anchors.push_back(anchor(AnchorType::TIMBER_HOOK, 10, 1));
	const std::vector<Problem> problems = run(poi, poi_params());
	CHECK(has(problems, "timber_hooks", "point of interest without a timber hook"));
	CHECK(has(problems, "timber_hooks", "a chamber without a timber hook"));
}

TEST_CASE("GEN-04 landmark and rubble: exactly one landmark, 1 or 2 heaps") {
	CHECK_FALSE(has(run(Spec{}), "landmark_rubble"));
	Spec none;
	drop_anchor(none, AnchorType::LANDMARK, 5, 9);
	CHECK(has(run(none), "landmark_rubble", "0 landmarks"));
	Spec heaps;
	heaps.anchors.push_back(anchor(AnchorType::RUBBLE_HEAP, 3, 11));
	heaps.anchors.push_back(anchor(AnchorType::RUBBLE_HEAP, 18, 9));
	CHECK(has(run(heaps), "landmark_rubble", "3 rubble heaps"));
	CHECK_FALSE(has(run(poi_spec(), poi_params()), "landmark_rubble"));
}

TEST_CASE("GEN-04 anchor fit") {
	CHECK_FALSE(has(run(Spec{}), "anchor_fit"));
	Spec thin;
	thin.anchors.push_back(anchor(AnchorType::RICH_ROCK, 13, 13, 2, 3));
	CHECK(has(run(thin), "anchor_fit", "rich_rock"));
	Spec gas;
	gas.anchors.push_back(anchor(AnchorType::GAS_AREA, 1, 9, 9, 1));
	CHECK(has(run(gas), "anchor_fit", "gas_area"));
	Spec through;
	through.anchors.push_back(anchor(AnchorType::GAS_DEAD_END, 10, 2, 1, 4));
	CHECK(has(run(through), "anchor_fit", "gas_dead_end"));
	Spec open;
	open.anchors.push_back(anchor(AnchorType::REMAINS, 5, 10));
	CHECK(has(run(open), "anchor_fit", "remains"));
	Spec door;
	door.anchors.push_back(anchor(AnchorType::DOOR_SITE, 3, 9, 4, 1));
	CHECK(has(run(door), "anchor_fit", "door_site"));
	Spec fixture;
	fixture.anchors.push_back(anchor(AnchorType::WALL_FIXTURE, 5, 10));
	CHECK(has(run(fixture), "anchor_fit", "wall_fixture"));
	Spec brick;
	set(brick, 4, 12, 'B');
	brick.anchors.push_back(anchor(AnchorType::WALL_FIXTURE, 4, 12));
	CHECK(has(run(brick), "anchor_fit", "wall_fixture"));
}

TEST_CASE("GEN-04 point of interest: a door stub, the lair one stub, its slots and its phone") {
	CHECK_FALSE(has(run(poi_spec(), poi_params()), "poi"));
	Spec no_door = poi_spec();
	no_door.stubs[0].door = false;
	CHECK(has(run(no_door, poi_params()), "poi", "without a door stub"));
	Spec lair = poi_spec();
	lair.poi_kind = "lair";
	CHECK_FALSE(has(run(lair, poi_params()), "poi"));
	lair.rows[5] = "#######.............";
	lair.stubs.push_back(stub(Edge::EAST, 5, 1));
	CHECK(has(run(lair, poi_params()), "poi", "the lair has 2 stubs"));
	ValidateParams more = poi_params();
	more.poi_slots["pump_room"] = 3;
	CHECK(has(run(poi_spec(), more), "poi", "2 poi_slots for 3 contents lines"));
	Spec silent = poi_spec();
	silent.anchors.pop_back();
	CHECK(has(run(silent, poi_params()), "poi", "no phone"));
}

TEST_CASE("GEN-04 fallback: a stub at all 12 positions at the biome's maximum width") {
	CHECK_FALSE(has(run(fallback_spec()), "fallback"));
	Spec short_one = fallback_spec();
	short_one.stubs.pop_back();
	CHECK(has(run(short_one), "fallback"));
	Spec narrow = fallback_spec();
	narrow.stubs[4].max_width = 2;
	CHECK(has(run(narrow), "fallback"));
}

TEST_CASE("GEN-04 the zone cutter: rooms, openings, roads and barriers") {
	const Cell c = cell_of(Spec{});
	const CellBlock b = block_of(c.road_graph);
	REQUIRE(b.zones.size() == 2);
	CHECK(b.zones[0].id == 1);
	CHECK(b.zones[0].kind == ZoneKind::CHAMBER);
	CHECK(b.zones[1].kind == ZoneKind::ROAD);
	REQUIRE(b.portals.size() == 1);
	CHECK(b.portals[0].kind == PortalKind::OPENING);
	CHECK(b.portals[0].tiles == std::vector<uint16_t>{static_cast<uint16_t>(Cell::index_of(10, 12))});
	CHECK(c.tiles[static_cast<size_t>(Cell::index_of(10, 15))].zone == 1);
	CHECK(c.tiles[static_cast<size_t>(Cell::index_of(0, 10))].zone == 2);
	CHECK(lb::core::sound::validate_block(c, b).empty());

	Spec door;
	set(door, 10, 12, 'D');
	const Cell d = cell_of(door);
	const CellBlock db = block_of(d.road_graph);
	REQUIRE(d.barriers.size() == 1);
	REQUIRE(db.portals.size() == 1);
	CHECK(db.portals[0].kind == PortalKind::AIR_DOOR);
	CHECK(db.portals[0].barrier == d.barriers[0].id);
	CHECK(d.barriers[0].portal == db.portals[0].id);
	CHECK(lb::core::sound::validate_block(d, db).empty());

	Spec poi = poi_spec(); // the room's mouth at the cell edge joins its room: the edge link stays
	poi.rows.erase(poi.rows.begin(), poi.rows.begin() + 2);
	poi.anchors[0] = anchor(AnchorType::CHAMBER, 7, 1, 6, 6);
	const Cell p = cell_of(poi);
	CHECK(p.tiles[static_cast<size_t>(Cell::index_of(10, 0))].zone == p.tiles[static_cast<size_t>(Cell::index_of(10, 1))].zone);
	CHECK(block_of(p.road_graph).portals.empty());
	CHECK(block_of(p.road_graph).zones[0].kind == ZoneKind::POI);
}

TEST_CASE("GEN-04 the zone cutter: a collapse's fallen cut keeps ids and loads into the Road Graph") {
	const Cell c = cell_of(Spec{});
	REQUIRE(c.collapses.size() == 1);
	const Collapse &col = c.collapses[0];
	const CellBlock fallen = block_of(col.fallen_road_graph);
	REQUIRE(fallen.zones.size() == 3);
	CHECK(fallen.zones[0].id == 1);
	CHECK(fallen.zones[1].id == 2); // the road's bigger piece keeps its id
	CHECK(fallen.zones[2].id == 3);
	CHECK(fallen.portals.size() == 1);
	CHECK(fallen.portals[0].id == 1);
	REQUIRE(col.zones.size() == 5); // (10, 0..4) cut off north of the fall
	for (const ZoneWrite &w : col.zones) {
		CHECK(w.index % CELL_TILES == 10);
		CHECK(w.index / CELL_TILES <= 4);
		CHECK(w.standing == 2);
		CHECK(w.fallen == 3);
	}

	MineMap mine;
	mine.commit(std::make_unique<Cell>(c));
	RoadGraph graph(mine);
	REQUIRE(graph.stitch({0, 0}, block_of(c.road_graph)));
	const uint64_t standing = graph.tables_digest();
	REQUIRE(mine.set_collapse({0, 0}, 1, true));
	graph.on_tiles_changed({0, 0});
	CHECK(graph.is_stitched({0, 0}));

	Cell fallen_cell = c; // a fresh graph over the fallen tiles and block, for comparison
	fallen_cell.tiles[static_cast<size_t>(Cell::index_of(10, 5))].material = static_cast<uint8_t>(TileMaterial::ROCK);
	for (const ZoneWrite &w : col.zones) {
		fallen_cell.tiles[w.index].zone = w.fallen;
	}
	fallen_cell.road_graph = col.fallen_road_graph;
	fallen_cell.collapses[0].is_fallen = true;
	MineMap mine2;
	mine2.commit(std::make_unique<Cell>(fallen_cell));
	RoadGraph fresh(mine2);
	REQUIRE(fresh.stitch({0, 0}, fallen));
	CHECK(graph.tables_digest() == fresh.tables_digest());
	CHECK(graph.tables_digest() != standing);

	REQUIRE(mine.set_collapse({0, 0}, 1, false));
	graph.on_tiles_changed({0, 0});
	CHECK(graph.is_stitched({0, 0}));
	CHECK(graph.tables_digest() == standing);
}

// GEN-07: main-road cells and edges, the bend partitions and runs, transposition, rails across
// edges, the gate arms and the blind arm, and order independence with main roads.

#include "core/rng/rng.h"
#include "core/world/coords.h"
#include "main_road_fixture.h"

#include <doctest.h>

#include <algorithm>
#include <map>

using namespace main_road_fixture;

namespace {

bool rail(const Cell &c, int64_t x, int64_t y) {
	const Tile &t = c.tiles[static_cast<size_t>(Cell::index_of(x, y))];
	return t.material == static_cast<uint8_t>(TileMaterial::FLOOR) && (t.state & lb::core::world::STATE_RAIL) != 0;
}

bool floor_at(const Cell &c, int64_t x, int64_t y) {
	return c.tiles[static_cast<size_t>(Cell::index_of(x, y))].material == static_cast<uint8_t>(TileMaterial::FLOOR);
}

} // namespace

TEST_CASE("GEN-07 main roads run along every 8th row and column, crossing at the shaft, and stop at the Deep") {
	MainRoads roads(1, MainRoadParams{}, {80, 200, 400, 700}, {});
	CHECK_FALSE(roads.is_main_road_cell({0, 0})); // base camp
	CHECK(roads.is_main_road_cell({1, 0}));
	CHECK(roads.is_main_road_cell({0, -5}));
	CHECK(roads.is_main_road_cell({16, 3}));
	CHECK_FALSE(roads.is_main_road_cell({3, 3}));
	CHECK(roads.is_crossing({8, 8}));
	CHECK(roads.is_crossing({-8, 16}));
	CHECK_FALSE(roads.is_crossing({8, 9}));
	// The Deep starts 700 tiles out: cell 34's centre is 690 out, cell 35's 710.
	CHECK(roads.is_main_road_cell({34, 0}));
	CHECK_FALSE(roads.is_main_road_cell({35, 0}));
	CHECK_FALSE(roads.is_main_road_cell({40, 0}));
	CHECK_FALSE(roads.is_crossing({32, 24})); // 40 cells out on the diagonal: the Deep
}

TEST_CASE("GEN-07 every edge between consecutive main-road cells is open, 3 wide, at 10 (10,000 seeds)") {
	auto set = road_set();
	lb::core::Rng rng(701);
	int64_t edges = 0;
	for (int s = 0; s < 10000; s++) {
		auto run = road_run(rng.next_u64(), set);
		const DeriveInputs in = run->inputs();
		const int64_t k = static_cast<int64_t>(rng.next_u64() % 9) - 4; // a line
		const int64_t x = static_cast<int64_t>(rng.next_u64() % 71) - 35; // a place along it
		for (const auto &[a, side] : {std::pair<Coord, Edge>{Coord{x, k * 8}, Edge::EAST}, std::pair<Coord, Edge>{Coord{k * 8, x}, Edge::SOUTH}}) {
			const Coord b = neighbour(a, side);
			if (!run->roads->is_main_road_cell(a) || !run->roads->is_main_road_cell(b)) {
				continue;
			}
			const Socket sock = derive_socket(in, edge_of(a, side));
			CHECK(sock.open);
			CHECK(sock.offset == 10);
			CHECK(sock.width == 3);
			edges++;
		}
		CHECK_FALSE(run->roads->is_main_road_cell({k * 8, 40}));
	}
	CHECK(edges > 9000);
}

TEST_CASE("GEN-07 bends split each segment into runs of 25-40 tiles, never on a cell edge") {
	const std::vector<std::vector<int32_t>> parts = MainRoads::enumerate_partitions(MainRoadParams{});
	CHECK(parts.size() == 47);
	for (const std::vector<int32_t> &p : parts) {
		int32_t at = 0;
		for (size_t i = 0; i < p.size(); i++) {
			CHECK(p[i] >= 25);
			CHECK(p[i] <= 40);
			CHECK(p[i] % 5 == 0);
			at += p[i];
			if (i + 1 < p.size()) {
				const int32_t in_cell = (10 + at) % 20;
				CHECK((in_cell == 5 || in_cell == 10 || in_cell == 15));
			}
		}
		CHECK(at == 160);
	}
	// Walking any line, the gaps between bends and crossings are 25-40 tiles.
	lb::core::Rng rng(702);
	int64_t runs = 0;
	for (int s = 0; s < 300; s++) {
		MainRoads roads(rng.next_u64(), MainRoadParams{}, {80, 200, 400, 700}, {});
		const int64_t k = static_cast<int64_t>(rng.next_u64() % 9) - 4;
		const bool row = (s % 2) == 0;
		int64_t last = -1;
		for (int64_t along = -32; along <= 32; along++) {
			const Coord c = row ? Coord{along, k * 8} : Coord{k * 8, along};
			if (!roads.is_main_road_cell(c) && !(c.x == 0 && c.y == 0)) {
				last = -1; // the Deep, or off the road: start again
				continue;
			}
			int64_t pos = -1;
			if (roads.is_crossing(c) || (c.x == 0 && c.y == 0)) {
				pos = along * 20 + 10;
			} else if (roads.bend_in(c) >= 0) {
				pos = along * 20 + roads.bend_in(c);
				CHECK(roads.bend_in(c) % 5 == 0);
				CHECK(roads.bend_in(c) != 0);
			}
			if (pos >= 0) {
				if (last >= 0) {
					CHECK(pos - last >= 25);
					CHECK(pos - last <= 40);
					runs++;
				}
				last = pos;
			}
		}
	}
	CHECK(runs > 3000);
}

TEST_CASE("GEN-07 a main-road template turned for a north-south road keeps its offsets") {
	const Template t = main_road("main_bend_5", "bend_5", false);
	const Template n = transpose(t);
	for (int64_t y = 0; y < 20; y++) {
		for (int64_t x = 0; x < 20; x++) {
			CHECK(n.cells[0].tiles[static_cast<size_t>(Cell::index_of(y, x))].material ==
					t.cells[0].tiles[static_cast<size_t>(Cell::index_of(x, y))].material);
		}
	}
	REQUIRE(n.stubs.size() == t.stubs.size());
	for (size_t i = 0; i < t.stubs.size(); i++) {
		const Edge want = t.stubs[i].edge == Edge::NORTH ? Edge::WEST : t.stubs[i].edge == Edge::WEST ? Edge::NORTH
				: t.stubs[i].edge == Edge::SOUTH                                                      ? Edge::EAST
																									  : Edge::SOUTH;
		CHECK(n.stubs[i].edge == want);
		CHECK(n.stubs[i].offset == t.stubs[i].offset);
	}
	const Template back = transpose(n);
	CHECK(content_digest(back.cells[0]) == content_digest(t.cells[0]));
	CHECK(validate(n, ValidateParams{}).size() > 0); // the rule reads east-west templates only
	CHECK(validate(t, ValidateParams{}).empty());
}

TEST_CASE("GEN-07 the fixture main roads pass GEN-04's rules, and the rule refuses a broken one") {
	for (const Template &t : main_roads()) {
		const std::vector<Problem> problems = validate(t, ValidateParams{});
		std::string all;
		for (const Problem &p : problems) {
			all += describe(t, p) + "\n";
		}
		CHECK_MESSAGE(problems.empty(), all);
	}
	Template no_rail = main_road("x", "straight", false);
	no_rail.cells[0].tiles[static_cast<size_t>(Cell::index_of(0, 10))].state = 0;
	CHECK(validate(no_rail, ValidateParams{}).front().message == "no rail on the road's centre line at its mouth");
	Template straight_bend = main_road("x", "straight", false);
	straight_bend.shape = "bend_10";
	CHECK(validate(straight_bend, ValidateParams{}).front().message == "a straight line of sight runs through the bend");
	Template fall_bend = main_road("x", "bend_5", false);
	fall_bend.old_fall = true;
	CHECK(validate(fall_bend, ValidateParams{}).back().message == "only a straight main road holds an old fall");
	Template open_fall = main_road("x", "straight", false);
	open_fall.old_fall = true;
	bool split = false;
	for (const Problem &p : validate(open_fall, ValidateParams{})) {
		split = split || p.message.find("the old fall must split the road in two") != std::string::npos;
	}
	CHECK(split);
}

TEST_CASE("GEN-07 derived main roads: rails across every edge, three arms out of base camp, a blind arm") {
	auto set = road_set();
	lb::core::Rng rng(703);
	int64_t road_edges = 0;
	for (int s = 0; s < 60; s++) {
		auto run = road_run(rng.next_u64(), set);
		Deriver d(run->inputs(), 2048);
		const Edge blind = blind_side(run->head.seed);
		for (int e = 0; e < 4; e++) {
			const Coord arm = neighbour({0, 0}, static_cast<Edge>(e));
			const std::optional<Layout> l = d.derive(arm, 0);
			REQUIRE(l.has_value());
			CHECK_FALSE(l->fallback);
			const Edge toward = opposite(static_cast<Edge>(e));
			int open_tiles = 0;
			for (int i = 9; i <= 11; i++) {
				const Coord t = toward == Edge::WEST ? Coord{0, i} : toward == Edge::EAST ? Coord{19, i}
						: toward == Edge::NORTH                                           ? Coord{i, 0}
																						  : Coord{i, 19};
				open_tiles += floor_at(l->cell, t.x, t.y) ? 1 : 0;
			}
			CHECK(open_tiles == (static_cast<Edge>(e) == blind ? 0 : 3)); // a gate arm, or the blind arm's heading
		}
		for (int64_t k = -2; k <= 2; k++) {
			for (int64_t along = -20; along < 20; along++) {
				for (bool row : {true, false}) {
					const Coord a = row ? Coord{along, k * 8} : Coord{k * 8, along};
					const Edge side = row ? Edge::EAST : Edge::SOUTH;
					const Coord b = neighbour(a, side);
					if (!run->roads->is_main_road_cell(a) || !run->roads->is_main_road_cell(b)) {
						continue;
					}
					const std::optional<Layout> la = d.derive(a, 0);
					const std::optional<Layout> lb = d.derive(b, 0);
					REQUIRE(la.has_value());
					REQUIRE(lb.has_value());
					CHECK_FALSE(la->fallback);
					const bool ok = row ? rail(la->cell, 19, 10) && rail(lb->cell, 0, 10) : rail(la->cell, 10, 19) && rail(lb->cell, 10, 0);
					if (!ok) {
						FAIL("no rail across the edge from (" << a.x << ", " << a.y << ")");
					}
					road_edges++;
				}
			}
		}
	}
	CHECK(road_edges > 5000);
	// A road's last cell before the Deep: the edge into the Deep is shut, its road a blind heading.
	auto run = road_run(4040, set);
	Deriver d(run->inputs());
	const Coord last{34, 0};
	REQUIRE(run->roads->is_main_road_cell(last));
	REQUIRE_FALSE(run->roads->is_main_road_cell({35, 0}));
	const Socket deep = d.socket(edge_of(last, Edge::EAST));
	CHECK_FALSE(deep.open);
	CHECK(deep.forced);
	const std::optional<Layout> l = d.derive(last, 0);
	REQUIRE(l.has_value());
	CHECK_FALSE(l->fallback);
	CHECK_FALSE(floor_at(l->cell, 19, 10));
}

TEST_CASE("GEN-07 main-road cells derive the same in any order, cached or not") {
	auto set = road_set();
	lb::core::Rng rng(704);
	std::vector<Coord> cells;
	for (int64_t y = -12; y <= 12; y++) {
		for (int64_t x = -12; x <= 12; x++) {
			cells.push_back({x, y});
		}
	}
	for (int s = 0; s < 20; s++) {
		auto run = road_run(rng.next_u64(), set);
		std::map<Coord, uint64_t> first;
		{
			Deriver d(run->inputs(), 64, 256);
			for (const Coord &c : cells) {
				first[c] = d.derive(c, 0)->digest;
			}
		}
		std::vector<Coord> order = cells;
		rng.shuffle(order);
		Deriver d(run->inputs());
		d.set_verify(true);
		for (const Coord &c : order) {
			CHECK(d.derive(c, 0)->digest == first[c]);
		}
		d.set_caching(false);
		for (const Coord &c : order) {
			CHECK(d.derive(c, 0)->digest == first[c]);
		}
		CHECK(d.verify_failures() == 0);
	}
}

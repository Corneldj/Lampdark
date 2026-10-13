#include "road_fixture.h"

#include <doctest.h>

#include <algorithm>
#include <chrono>
#include <cmath>

using namespace road_fixture;

namespace {

// Three cells of one straight road along row 5: tiles x 0..59.
void straight_road(MineMap &mine, RoadGraph &graph) {
	for (int64_t cx = 0; cx < 3; cx++) {
		mine.commit(cell({cx, 0}, road_row(5)));
		REQUIRE(graph.stitch({cx, 0}, zones({1})));
	}
}

// Base camp (zone 1, x 1..8) | gate S at (9, 5), barrier 1 | road (zone 2, x 10..19).
// Optionally a second way round through an air door at (9, 8) (barrier 2) via row 8.
void gate_cell(MineMap &mine, RoadGraph &graph, bool second_route, bool door_open) {
	std::vector<std::string> rows(20, std::string(20, 'B'));
	for (int y = 2; y <= 8; y++) {
		rows[y] = "B11111111B##########";
	}
	rows[5] = "B11111111S2222222222";
	if (second_route) {
		rows[8] = "B11111111D2222222222";
		for (int y = 6; y <= 7; y++) {
			rows[y][10] = '2';
		}
	}
	auto c = cell({0, 0}, rows);
	c->barriers.push_back(barrier(1, {{9, 5}}));
	CellBlock block = zones({1, 2});
	block.portals.push_back(portal(1, PortalKind::GATE, 1, 2, {{9, 5}}, 1));
	if (second_route) {
		c->barriers.push_back(barrier(2, {{9, 8}}, door_open));
		block.portals.push_back(portal(2, PortalKind::AIR_DOOR, 1, 2, {{9, 8}}, 2));
	}
	mine.commit(std::move(c));
	REQUIRE(graph.stitch({0, 0}, block));
}

std::optional<Delivery> heard(RoadGraph &graph, Coord from, double level, Coord at, Mode mode = Mode::AIR) {
	graph.set_listener({7, at});
	std::vector<Delivery> ds = graph.propagate(1, {from}, level, mode);
	graph.remove_listener(7);
	if (ds.empty()) {
		return std::nullopt;
	}
	return ds[0];
}

} // namespace

TEST_CASE("a 40 np event reaches 40 tiles of straight road with 0 np left, and not 41") {
	MineMap mine;
	RoadGraph graph(mine);
	straight_road(mine, graph);
	const std::optional<Delivery> at40 = heard(graph, {0, 5}, 40.0, {40, 5});
	REQUIRE(at40);
	CHECK(at40->remaining_np == doctest::Approx(0.0));
	CHECK(at40->path_tiles == doctest::Approx(40.0));
	CHECK_FALSE(heard(graph, {0, 5}, 40.0, {41, 5}));
	CHECK(heard(graph, {0, 5}, 40.0, {25, 5})->remaining_np == doctest::Approx(15.0));
}

TEST_CASE("a 14 np strike at a shut gate's inner face reaches the road side at 2 np; open, 14") {
	MineMap mine;
	RoadGraph graph(mine);
	gate_cell(mine, graph, false, false);
	const std::optional<Delivery> shut = heard(graph, {8, 5}, 14.0, {10, 5});
	REQUIRE(shut);
	CHECK(shut->remaining_np == doctest::Approx(2.0));
	CHECK(shut->closed_portals == 1);
	CHECK_FALSE(heard(graph, {8, 5}, 14.0, {10, 5}, Mode::VOICE)); // voice is cut
	mine.set_barrier({0, 0}, 1, true);
	mine.take_changes();
	graph.on_tiles_changed({0, 0});
	CHECK(heard(graph, {8, 5}, 14.0, {10, 5})->remaining_np == doctest::Approx(14.0));
}

TEST_CASE("VOICE takes another open route when the gate is shut") {
	MineMap mine;
	RoadGraph graph(mine);
	gate_cell(mine, graph, true, true);
	const std::optional<Delivery> voice = heard(graph, {8, 5}, 24.0, {10, 5}, Mode::VOICE);
	REQUIRE(voice);
	CHECK(voice->closed_portals == 0);
	CHECK(voice->path_tiles == doctest::Approx(6.0)); // down 3, through the door, up 3
	CHECK(voice->via == 2);
	const std::optional<Delivery> air = heard(graph, {8, 5}, 24.0, {10, 5});
	CHECK(air->remaining_np == doctest::Approx(18.0)); // the open route (6) beats the gate (12)
}

TEST_CASE("apparent position: the source in its own zone, the entry portal otherwise; bounded jitter") {
	MineMap mine;
	RoadGraph graph(mine);
	gate_cell(mine, graph, false, true);
	mine.set_barrier({0, 0}, 1, true);
	graph.on_tiles_changed({0, 0});
	const std::optional<Delivery> same = heard(graph, {2, 5}, 30.0, {7, 5});
	CHECK(same->apparent_tile == Coord{2, 5});
	CHECK(same->via == -1);
	const std::optional<Delivery> other = heard(graph, {2, 5}, 30.0, {15, 5});
	CHECK(other->apparent_tile == Coord{9, 5});
	CHECK(other->via == 1);
	CHECK(other->true_source == Coord{2, 5});
	// 10,000 jitter samples within path / 4 per axis; identical keys repeat exactly.
	int outside = 0;
	for (uint64_t key = 0; key < 10000; key++) {
		const std::optional<Delivery> d = graph.deliver({2, 5}, 30.0, {15, 5}, Mode::AIR, 0.0, 1.0, key);
		const double limit = d->path_tiles / 4.0 + 1e-9;
		if (std::fabs(d->apparent_x - 9.5) > limit || std::fabs(d->apparent_y - 5.5) > limit) {
			outside++;
		}
		const std::optional<Delivery> again = graph.deliver({2, 5}, 30.0, {15, 5}, Mode::AIR, 0.0, 1.0, key);
		CHECK(again->apparent_x == d->apparent_x);
	}
	CHECK(outside == 0);
}

TEST_CASE("a portal toggle or collapse swap reroutes the next event in the same tick") {
	MineMap mine;
	RoadGraph graph(mine);
	auto c = cell({0, 0}, {"####################", "#1111111111111111111", "#1#################1", "#1111111111111111111"});
	Collapse fall;
	fall.id = 9;
	fall.standing = {{static_cast<uint16_t>(Cell::index_of(10, 1)), static_cast<uint8_t>(TileMaterial::FLOOR)}};
	fall.fallen = {{static_cast<uint16_t>(Cell::index_of(10, 1)), static_cast<uint8_t>(TileMaterial::ROCK)}};
	c->collapses.push_back(fall);
	mine.commit(std::move(c));
	REQUIRE(graph.stitch({0, 0}, zones({1})));
	CHECK(heard(graph, {2, 1}, 40.0, {18, 1})->path_tiles == doctest::Approx(16.0));
	const uint64_t before = graph.epoch();
	mine.set_collapse({0, 0}, 9, true);
	mine.take_changes();
	graph.on_tiles_changed({0, 0});
	CHECK(graph.epoch() > before);
	// Round by row 3: (2,1) west 1, down 2, east 18, up 2, west 1.
	const std::optional<Delivery> rerouted = heard(graph, {2, 1}, 40.0, {18, 1});
	REQUIRE(rerouted);
	CHECK(rerouted->path_tiles == doctest::Approx(24.0));
}

TEST_CASE("rock line: a 2-tile pillar reports 2 solid tiles; brick and doors set flags") {
	MineMap mine;
	mine.commit(road_fixture::cell({0, 0}, {"11111111", "11##1B11", "1111D111"}));
	const RockLine pillar = rock_line(mine, {1, 1}, {4, 1});
	CHECK(pillar.solid_tiles == 2);
	CHECK_FALSE(pillar.brick);
	CHECK(pillar.distance == doctest::Approx(3.0));
	CHECK(pillar.listener_face == Coord{3, 1});
	CHECK(rock_line(mine, {4, 1}, {6, 1}).brick);
	CHECK(rock_line(mine, {3, 2}, {5, 2}).door);
	CHECK(rock_line(mine, {0, 0}, {7, 0}).solid_tiles == 0);
}

TEST_CASE("the Tapper's bound: talk heard 12.8 tiles away in ring 4, not beyond 8 in ring 1") {
	MineMap mine;
	RoadGraph graph(mine);
	straight_road(mine, graph);
	auto tapper = [&](Coord at, double multiplier) {
		graph.set_listener({9, at, 4.0, multiplier});
		const bool hears = !graph.propagate(5, {{0, 5}}, 12.0, Mode::AIR).empty();
		graph.remove_listener(9);
		return hears;
	};
	CHECK(tapper({12, 5}, 1.6));
	CHECK_FALSE(tapper({13, 5}, 1.6));
	CHECK(tapper({8, 5}, 1.0));
	CHECK_FALSE(tapper({9, 5}, 1.0));
	CHECK(audible(12.0, 0, 12.0, 12.8, 4.0, 1.6));
	CHECK_FALSE(audible(40.0, 3, 12.0, 1.0, 4.0, 1.6)); // closed portals come off before the multiplier
}

TEST_CASE("multi-origin: the cheapest origin wins") {
	MineMap mine;
	RoadGraph graph(mine);
	straight_road(mine, graph);
	graph.set_listener({3, {30, 5}});
	const std::vector<Delivery> d = graph.propagate(2, {{0, 5}, {50, 5}}, 24.0, Mode::AIR);
	REQUIRE(d.size() == 1);
	CHECK(d[0].path_tiles == doctest::Approx(20.0));
	CHECK(d[0].true_source == Coord{50, 5});
}

TEST_CASE("the delivery function changes no listener, cache or epoch") {
	MineMap mine;
	RoadGraph graph(mine);
	straight_road(mine, graph);
	graph.set_listener({1, {10, 5}});
	graph.propagate(1, {{0, 5}}, 30.0, Mode::AIR);
	const size_t cache = graph.cache_entries();
	const uint64_t epoch = graph.epoch();
	const std::optional<Delivery> d = graph.deliver({5, 5}, 30.0, {20, 5}, Mode::AIR);
	CHECK(d->path_tiles == doctest::Approx(15.0));
	CHECK(graph.cache_entries() == cache);
	CHECK(graph.epoch() == epoch);
	CHECK(graph.propagate(1, {{0, 5}}, 30.0, Mode::AIR).size() == 1);
	CHECK(graph.nearest_open_tile({3, 4}, 3) == Coord{3, 5});
}

TEST_CASE("the Tapper never hears through brick: nearest open tiles never lie behind it") {
	MineMap mine;
	RoadGraph graph(mine);
	// Rock x 0-2, a brick wall at x 3, base camp floor (zone 1) x 4-8; a road (zone 2) at y 9.
	std::vector<std::string> rows(20, std::string(20, '#'));
	for (int y = 0; y < 8; y++) {
		rows[y] = "###B11111###########";
	}
	rows[9] = "22222222222222222222";
	mine.commit(road_fixture::cell({0, 0}, rows));
	REQUIRE(graph.stitch({0, 0}, zones({1, 2})));
	CHECK_FALSE(graph.nearest_open_tile({1, 4}, 3).has_value()); // only base camp is near, behind brick
	const std::optional<Coord> road = graph.nearest_open_tile({1, 6}, 4);
	REQUIRE(road);
	CHECK(road->y == 9);
}

TEST_CASE("a cell unloaded and reloaded matches a fresh build") {
	MineMap mine;
	RoadGraph graph(mine);
	straight_road(mine, graph);
	graph.unload({1, 0});
	CHECK_FALSE(heard(graph, {0, 5}, 40.0, {30, 5}));
	REQUIRE(graph.stitch({1, 0}, zones({1})));
	RoadGraph fresh(mine);
	for (int64_t cx = 0; cx < 3; cx++) {
		REQUIRE(fresh.stitch({cx, 0}, zones({1})));
	}
	CHECK(graph.tables_digest() == fresh.tables_digest());
	CHECK(heard(graph, {0, 5}, 40.0, {30, 5})->path_tiles == doctest::Approx(30.0));
}

TEST_CASE("the block format round-trips and the validator finds problems") {
	CellBlock block = zones({1, 2});
	block.portals.push_back(portal(4, PortalKind::AIR_DOOR, 1, 2, {{9, 5}}, 3));
	const std::optional<CellBlock> back = decode_block(encode_block(block));
	REQUIRE(back);
	CHECK(back->portals[0].barrier == 3);
	CHECK(encode_block(*back) == encode_block(block));
	CHECK_FALSE(decode_block({9, 0, 0}));
	auto c = road_fixture::cell({0, 0}, {"11.11"});
	c->tiles[Cell::index_of(2, 0)].material = static_cast<uint8_t>(TileMaterial::FLOOR);
	const std::vector<std::string> problems = validate_block(*c, zones({1}));
	REQUIRE(problems.size() == 1);
	CHECK(problems[0].find("in no declared zone") != std::string::npos);
}

TEST_CASE("five miners walking and talking, 40 events a tick, in a 9x9-cell window") {
	MineMap mine;
	RoadGraph graph(mine);
	std::vector<std::string> grid(20, std::string(20, '#'));
	for (int i = 0; i < 20; i++) {
		for (int r : {3, 4, 15}) {
			grid[r][i] = '1';
			grid[i][r] = '1';
		}
	}
	for (int64_t cy = -4; cy <= 4; cy++) {
		for (int64_t cx = -4; cx <= 4; cx++) {
			mine.commit(cell({cx, cy}, grid));
		}
	}
	for (int64_t cy = -4; cy <= 4; cy++) {
		for (int64_t cx = -4; cx <= 4; cx++) {
			REQUIRE(graph.stitch({cx, cy}, zones({1})));
		}
	}
	graph.set_listener({100, {0, 0}, 4.0, 1.6}); // a Tapper at its listening tile
	// 2000 ticks, so p99 needs about 20 slow ticks and not one scheduler hiccup.
	std::vector<int64_t> samples;
	for (int tick = 0; tick < 2000; tick++) {
		for (uint32_t m = 0; m < 5; m++) {
			graph.set_listener({m + 1, {static_cast<int64_t>(-40 + 20 * m + tick % 15), 3}});
		}
		const auto start = std::chrono::steady_clock::now();
		for (int e = 0; e < 40; e++) {
			const Coord origin{static_cast<int64_t>(-40 + 20 * (e % 5) + tick % 15), 3};
			const double level = e % 4 == 0 ? 12.0 : 9.0; // talk, steps
			graph.propagate(static_cast<uint64_t>(tick * 64 + e), {origin}, level, e % 4 == 0 ? Mode::VOICE : Mode::AIR);
		}
		samples.push_back(std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - start).count());
	}
	std::sort(samples.begin(), samples.end());
	const int64_t p99 = samples[samples.size() * 99 / 100];
	MESSAGE("road graph 40 events: p50 " << samples[samples.size() / 2] << " us, p99 " << p99 << " us");
#ifndef LB_DEBUG_TOOLS
	CHECK(p99 < 500);
#endif
}

// GEN-08: spines. Each leaves by the open gate nearest its target's bearing (never the blind side;
// an exact tie by hash), steps 4-neighbour cell by cell, never enters base camp, the Deep or any
// point of interest's cells, goes round one in its way, and ends outside its target's door; every
// edge it crosses is forced open at the edge's own offset and width; its main-road cells take no
// old fall.

#include "plan_fixture.h"

#include <doctest.h>

using namespace plan_fixture;

TEST_CASE("GEN-08 the gate nearest the bearing, never the blind side, a tie by hash") {
	const std::vector<Edge> no_north{Edge::EAST, Edge::SOUTH, Edge::WEST};
	CHECK(spine_gate(no_north, 400, -10, 0) == Edge::EAST);
	CHECK(spine_gate(no_north, -400, 10, 0) == Edge::WEST);
	CHECK(spine_gate(no_north, 10, 400, 0) == Edge::SOUTH);
	// Due north with the north side blind: east and west tie, and the hash picks either, never north.
	std::set<Edge> seen;
	for (uint64_t t = 0; t < 16; t++) {
		const Edge g = spine_gate(no_north, 0, -400, lb::core::mix64(t));
		CHECK(g != Edge::NORTH);
		seen.insert(g);
	}
	CHECK(seen == std::set<Edge>{Edge::EAST, Edge::WEST});
}

TEST_CASE("GEN-08 every spine steps from its gate to its door, round every point of interest") {
	int64_t spines = 0;
	int64_t bad = 0;
	for (int32_t kind = 0; kind < 3; kind++) {
		for (uint64_t s = 0; s < 1000; s++) {
			const uint64_t seed = lb::core::mix64(s * 7 + static_cast<uint64_t>(kind) + 0x5917E);
			const RunHeader h = planned(seed, kind);
			REQUIRE(h.plan.error.empty());
			const int blind = blind_of(seed);
			std::set<Coord> footprints;
			for (const PlannedSite &site : h.plan.sites) {
				footprints.insert(site.cells.begin(), site.cells.end());
			}
			std::set<int32_t> targets;
			for (const Spine &sp : h.plan.spines) {
				spines++;
				const PlannedSite &site = h.plan.sites[static_cast<size_t>(sp.site)];
				targets.insert(sp.site);
				CHECK(site.spine);
				const auto [dx2, dy2] = door_point2(site);
				const std::vector<Edge> gates = world(blind).gates;
				bad += static_cast<int>(sp.gate) != blind ? 0 : 1;
				// Nearest the bearing: no open gate scores better.
				auto score = [&](Edge g) {
					return g == Edge::NORTH ? -dy2 : (g == Edge::EAST ? dx2 : (g == Edge::SOUTH ? dy2 : -dx2));
				};
				for (Edge g : gates) {
					bad += score(g) <= score(sp.gate) ? 0 : 1;
				}
				REQUIRE(!sp.cells.empty());
				bad += sp.cells.front() == neighbour({0, 0}, sp.gate) ? 0 : 1;
				bad += sp.cells.back() == site.approach() ? 0 : 1;
				bad += neighbour(site.approach(), opposite(site.door_side)) == site.door ? 0 : 1;
				std::set<Coord> once;
				for (size_t i = 0; i < sp.cells.size(); i++) {
					const Coord c = sp.cells[i];
					if ((c.x == 0 && c.y == 0) || ring(c) >= DEEP_RING || footprints.count(c) != 0 || !once.insert(c).second) {
						bad++;
					}
					if (i > 0) {
						const Coord p = sp.cells[i - 1];
						bad += std::abs(c.x - p.x) + std::abs(c.y - p.y) == 1 ? 0 : 1;
					}
				}
			}
			// One spine to every site but the spares.
			for (size_t i = 0; i < h.plan.sites.size(); i++) {
				bad += h.plan.sites[i].spine == (targets.count(static_cast<int32_t>(i)) != 0) ? 0 : 1;
			}
		}
	}
	MESSAGE(spines, " spines");
	CHECK(bad == 0);
}

TEST_CASE("GEN-08 a spine goes round a point of interest standing in its way") {
	PlannedSite site;
	site.kind = PoiKind::STORES;
	site.door = {7, 0};
	site.door_side = Edge::WEST;
	site.cells = {{7, 0}};
	// A wall of other points of interest across the straight way, cells (4, -2) to (4, 2).
	std::set<Coord> blocked{{7, 0}};
	for (int64_t y = -2; y <= 2; y++) {
		blocked.insert({4, y});
	}
	const std::optional<Spine> sp = route_spine(42, 0, site, {Edge::EAST, Edge::SOUTH, Edge::WEST}, blocked, bounds(), 0);
	REQUIRE(sp.has_value());
	CHECK(sp->gate == Edge::EAST);
	CHECK(sp->cells.back() == Coord{6, 0});
	for (const Coord &c : sp->cells) {
		CHECK(blocked.count(c) == 0);
	}
	// Walled in on every side: no spine.
	std::set<Coord> sealed = blocked;
	for (const Coord &c : {Coord{6, -1}, Coord{6, 1}, Coord{5, 0}}) {
		sealed.insert(c);
	}
	CHECK_FALSE(route_spine(42, 0, site, {Edge::EAST}, sealed, bounds(), 0).has_value());
}

TEST_CASE("GEN-08 spine sockets open every spine edge at the edge's own offset and width") {
	const RunHeader h = planned(1234, 1);
	REQUIRE(h.plan.error.empty());
	UniformCells cells("seam", {1, 2, 3});
	SocketParams params;
	SpineSockets sockets(h.seed, h.plan, cells, params);
	int64_t edges = 0;
	for (const Spine &sp : h.plan.spines) {
		for (const EdgeKey &e : spine_edges(sp, h.plan.sites[static_cast<size_t>(sp.site)])) {
			const std::optional<Socket> s = sockets.query(e);
			REQUIRE(s.has_value());
			CHECK(s->open);
			CHECK(s->forced);
			CHECK((s->offset == 5 || s->offset == 10 || s->offset == 15));
			CHECK((s->width >= 1 && s->width <= 3));
			SocketParams always = params;
			always.open_ppm = 1000000;
			const Socket hashed = hashed_socket(h.seed, e, always, {1, 2, 3});
			CHECK(s->offset == hashed.offset);
			CHECK(s->width == hashed.width);
			edges++;
		}
		for (const Coord &c : sp.cells) {
			CHECK(sockets.is_spine_cell(c));
		}
	}
	MESSAGE(edges, " spine edges");
	// An edge no spine crosses is not the spines' to answer.
	CHECK_FALSE(sockets.query(edge_of({-30, -30}, Edge::EAST)).has_value());
	CHECK_FALSE(sockets.is_spine_cell({-30, -30}));
}

TEST_CASE("GEN-08 spine cells on a main road take no old fall") {
	int64_t checked = 0;
	for (uint64_t s = 0; s < 200; s++) {
		const RunHeader h = planned(lb::core::mix64(s + 991), 2);
		REQUIRE(h.plan.error.empty());
		const std::set<Coord> spine = spine_cells(h.plan);
		MainRoads r(h.seed, MainRoadParams{}, bounds(), {});
		r.is_spine = [&](Coord c) { return spine.count(c) != 0; };
		for (const Coord &c : spine) {
			if (r.is_main_road_cell(c)) {
				CHECK_FALSE(r.old_fall(c));
				checked++;
			}
		}
	}
	MESSAGE(checked, " spine cells on main roads");
	CHECK(checked > 0);
}

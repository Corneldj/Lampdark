// GEN-14's metrics on hand-made worlds: the cells nearest the shaft and the seeded orders, a cell's
// digest, a spine's road against the straight line and the shortest road home, the joined share,
// the exploration model, the finds count and the report's histograms.

#include "harness_fixture.h"

#include <doctest.h>

#include <cmath>
#include <set>

using namespace harness_fixture;
namespace h = lb::harness;

TEST_CASE("GEN-14 the cells nearest the shaft, base camp's excepted, nearest first") {
	const std::vector<Coord> eight = h::nearest_cells(8);
	CHECK(eight == std::vector<Coord>{{0, -1}, {-1, 0}, {1, 0}, {0, 1}, {-1, -1}, {1, -1}, {-1, 1}, {1, 1}});
	const std::vector<Coord> many = h::nearest_cells(400);
	REQUIRE(many.size() == 400);
	const std::set<Coord> in(many.begin(), many.end());
	CHECK(in.size() == 400);
	CHECK(in.count({0, 0}) == 0);
	const int64_t last = many.back().x * many.back().x + many.back().y * many.back().y;
	for (int64_t y = -16; y <= 16; y++) {
		for (int64_t x = -16; x <= 16; x++) {
			if ((x != 0 || y != 0) && in.count({x, y}) == 0) {
				CHECK(x * x + y * y >= last);
			}
		}
	}
}

TEST_CASE("GEN-14 a seed's orders: each a permutation, fixed by the seed and the order's number") {
	const std::vector<Coord> cells = h::nearest_cells(50);
	const std::vector<Coord> a = h::shuffled(cells, 7, 0);
	CHECK(a == h::shuffled(cells, 7, 0));
	CHECK(a != h::shuffled(cells, 7, 1));
	CHECK(a != h::shuffled(cells, 8, 0));
	CHECK(std::set<Coord>(a.begin(), a.end()) == std::set<Coord>(cells.begin(), cells.end()));
}

TEST_CASE("GEN-14 a cell's digest covers its layout, its placements and how the validator reached them") {
	WorldRun w;
	const Coord c{2, 1};
	const std::optional<Layout> layout = w.world().layout(c);
	const PlacedCell placed = place_validated(w.world(), w.pp, w.vp, c);
	const uint64_t d = h::cell_digest(layout, placed);
	CHECK(d == h::cell_digest(w.world().layout(c), place_validated(w.world(), w.pp, w.vp, c)));
	std::optional<Layout> changed = layout;
	changed->cell.tiles[static_cast<size_t>(Cell::index_of(1, 1))].material = static_cast<uint8_t>(TileMaterial::FLOOR);
	CHECK(h::cell_digest(changed, placed) != d);
	PlacedCell retried = placed;
	retried.retry = 1;
	CHECK(h::cell_digest(layout, retried) != d);
	PlacedCell fewer = placed;
	REQUIRE(!fewer.list.empty());
	fewer.list.pop_back();
	CHECK(h::cell_digest(layout, fewer) != d);
	CHECK(h::cell_digest(std::nullopt, placed) != d);
}

TEST_CASE("GEN-14 a spine's road against the straight line, and the shortest road home") {
	WorldRun w;
	w.world_.head.plan = east_then_north();
	const h::Road r = h::spine_road(w.world(), w.world_.head.plan, 0);
	REQUIRE(r.tiles > 0);
	CHECK(lb::core::world::cell_of(r.from) == Coord{1, 0});
	CHECK(lb::core::world::cell_of(r.to) == Coord{3, -2});
	// Through GEN-04's cross roads east, then north: never a step back.
	CHECK(r.tiles == std::llabs(r.to.x - r.from.x) + std::llabs(r.to.y - r.from.y));
	CHECK(r.straight() == doctest::Approx(std::sqrt(static_cast<double>((r.to.x - r.from.x) * (r.to.x - r.from.x) + (r.to.y - r.from.y) * (r.to.y - r.from.y)))));
	const double ratio = static_cast<double>(r.tiles) / r.straight();
	CHECK(ratio > 1.0);
	CHECK(ratio < 1.5);
	// The shortest road home is no longer than the spine's.
	const h::Road home = h::home_road(w.world(), w.world_.head.plan.sites[0], 400000);
	REQUIRE(home.tiles > 0);
	CHECK(home.tiles <= r.tiles);
	CHECK(lb::core::world::cell_of(home.to) == Coord{3, -2});
	// A door its spine cannot reach has no spine road.
	w.world_.head.plan.spines[0].cells = {{1, 0}, {2, 0}};
	CHECK(h::spine_road(w.world(), w.world_.head.plan, 0).tiles == -1);
}

TEST_CASE("GEN-14 the joined share walks open sockets within the rings, a point of interest one piece") {
	h::SocketGraph g;
	g.ring = [](Coord c) { return std::max(std::llabs(c.x), std::llabs(c.y)); };
	// Every socket open but those between columns 1 and 2.
	g.sockets = [](Coord c) {
		CellSockets s{};
		for (int e = 0; e < 4; e++) {
			s[static_cast<size_t>(e)] = open_socket(10, 2);
		}
		if (c.x == 1) {
			s[static_cast<size_t>(Edge::EAST)].open = false;
		}
		if (c.x == 2) {
			s[static_cast<size_t>(Edge::WEST)].open = false;
		}
		return s;
	};
	g.footprint = [](Coord) { return std::vector<Coord>{}; };
	// Rings 0-3 within 3 cells: the 7x7 square, base camp's cell excepted.
	h::Joined j = h::joined_cells(g, 3, 3);
	CHECK(j.cells == 48);
	CHECK(j.joined == 5 * 7 - 1); // columns -3 to 1
	// A point of interest across the cut is one piece: the far side joins through it.
	g.footprint = [](Coord c) {
		if (c == Coord{1, 0} || c == Coord{2, 0}) {
			return std::vector<Coord>{{1, 0}, {2, 0}};
		}
		return std::vector<Coord>{};
	};
	CHECK(h::joined_cells(g, 3, 3).joined == 48);
	// The walk stays within the rings: the 3x3 of rings 0-1.
	j = h::joined_cells(g, 1, 3);
	CHECK(j.cells == 8);
	CHECK(j.joined == 8);
	// Shut base camp: nothing joins.
	g.sockets = [](Coord c) {
		CellSockets s{};
		for (int e = 0; e < 4; e++) {
			s[static_cast<size_t>(e)] = open_socket(10, 2);
			s[static_cast<size_t>(e)].open = !(c == Coord{0, 0});
		}
		return s;
	};
	g.footprint = [](Coord) { return std::vector<Coord>{}; };
	CHECK(h::joined_cells(g, 3, 3).joined == 0);
}

TEST_CASE("GEN-14 the exploration model: spines, their neighbours, the sites, and nearby ring 0-1 cells") {
	WorldRun w;
	RunPlan plan;
	Spine sp;
	sp.site = 0;
	sp.cells = {{5, 0}, {6, 0}, {7, 0}};
	plan.spines.push_back(sp);
	PlannedSite site;
	site.door = {8, 0};
	site.cells = {{8, 0}, {9, 0}, {9, 1}};
	plan.sites.push_back(site);
	const std::vector<Coord> cells = h::explored_cells(plan, w.world(), 3, 1);
	const std::set<Coord> in(cells.begin(), cells.end());
	CHECK(std::is_sorted(cells.begin(), cells.end()));
	CHECK(in.size() == cells.size());
	// A spine cell and its 8-neighbours, whatever their ring.
	for (const Coord &c : std::vector<Coord>{{5, 0}, {4, -1}, {8, 1}, {6, 1}}) {
		CHECK_MESSAGE(in.count(c) == 1, c.x, ",", c.y);
	}
	// The site's cells.
	CHECK(in.count({9, 1}) == 1);
	// Within 3 cells of a spine: ring 0 and 1 cells only (ring 1 ends at 200 tiles: about 9.5 cells).
	CHECK(w.world().facts({2, 0}).ring == 0);
	CHECK(in.count({2, 0}) == 1);
	CHECK(w.world().facts({9, 3}).ring == 1);
	CHECK(in.count({9, 3}) == 1);
	CHECK(w.world().facts({10, 3}).ring == 2);
	CHECK(in.count({10, 3}) == 0);
	// Beyond 3 cells of every spine cell: never.
	CHECK(in.count({5, 4}) == 0);
	CHECK(in.count({1, 0}) == 0);
	// Base camp is never explored.
	CHECK(in.count({0, 0}) == 0);
}

TEST_CASE("GEN-14 finds: lamps besides the hoard, kits with the cupboard's, flares and tools by ring") {
	WorldRun w;
	place_fixture::reset(w.world_, 31);
	std::vector<Coord> cells;
	for (int64_t y = -3; y <= 3; y++) {
		for (int64_t x = 1; x <= 12; x++) {
			cells.push_back({x, y});
		}
	}
	const std::map<std::string, int64_t> finds = h::count_finds(w.world(), w.pp, w.vp, cells, 1);
	// Tallied apart: every item placement in the cells, the hoard's lamps (its cell (8, 0)) aside.
	std::map<std::string, int64_t> tally;
	int64_t hoard_lamps = 0;
	for (const Coord &c : cells) {
		const int64_t ring = w.world().facts(c).ring;
		for (const Placement &x : place_validated(w.world(), w.pp, w.vp, c).list) {
			if (x.kind != PlacedKind::ITEM) {
				continue;
			}
			const int64_t n = std::max<int64_t>(1, x.count);
			if (x.thing == "gauze_lamp") {
				(c == Coord{8, 0} ? hoard_lamps : tally["lamps"]) += n;
			} else if (x.thing == "flare" && ring <= 2) {
				tally["flares_ring2"] += n;
			} else if (x.thing == "healing_kit") {
				tally["kits"] += n;
			} else if (x.thing == "spanner" || x.thing == "hammer" || x.thing == "crowbar" || x.thing == "wire_cutters") {
				tally["tools_ring2." + x.thing] += ring <= 2 ? n : 0;
				tally["tools_ring1." + x.thing] += ring <= 1 ? n : 0;
			}
		}
	}
	CHECK(finds.at("lamps") == tally["lamps"]);
	CHECK(finds.at("kits") == tally["kits"] + 1);
	CHECK(finds.at("flares_ring2") == tally["flares_ring2"]);
	for (const char *tool : {"spanner", "hammer", "crowbar", "wire_cutters"}) {
		CHECK(finds.at(std::string("tools_ring2.") + tool) == tally[std::string("tools_ring2.") + tool]);
		CHECK(finds.at(std::string("tools_ring1.") + tool) == tally[std::string("tools_ring1.") + tool]);
	}
	CHECK(finds.at("explored_cells") == static_cast<int64_t>(cells.size()));
	MESSAGE("finds over ", cells.size(), " cells: lamps ", finds.at("lamps"), " (", hoard_lamps, " in the hoard aside), kits ", finds.at("kits"));
}

TEST_CASE("GEN-14 the report's histograms: fixed bins, any merge order, quantiles at bin edges") {
	h::Histogram a(10, 11);
	h::Histogram b(10, 11);
	for (int64_t v : {3, 15, 15, 27, 99, 250}) {
		a.add(v);
	}
	for (int64_t v : {250, 99, 27, 15, 15, 3}) {
		b.add(v);
	}
	CHECK(a.bins == b.bins);
	CHECK(a.count == 6);
	CHECK(a.sum == 409);
	CHECK(a.min == 3);
	CHECK(a.max == 250);
	CHECK(a.bins.back() == 1); // 250 overflows into the last bin
	CHECK(a.quantile(0.5) == 20); // the third value (15) lies in [10, 20)
	CHECK(a.quantile(1.0) == 250);
	h::Histogram m(10, 11);
	m.merge(a);
	m.merge(b);
	CHECK(m.count == 12);
	CHECK(m.quantile(0.5) == a.quantile(0.5));
}

TEST_CASE("GEN-16 coverage: the weighted share of socket sets a biome's templates cover, and blind headings") {
	// One template with stubs north and south at 10: it covers the sets with east and west shut and
	// north and south each shut or at 10.
	Spec ns = fallback_spec();
	ns.id = "seam_ns";
	ns.kind = TemplateKind::BIOME_CELL;
	ns.stubs = {stub(Edge::NORTH, 10, 3), stub(Edge::SOUTH, 10, 3)};
	Template t = make(ns);
	t.biome = "seam";
	auto set = std::make_shared<TemplateSet>();
	REQUIRE(set->load(encode_pack("coverage", {t})));
	const h::Coverage c = h::coverage(*set, "seam", 600000, {5, 10, 15}, {3});
	CHECK(c.templates == 1);
	CHECK(c.sets == 256);
	// (0.4 + 0.2)^2 for north and south, 0.4^2 for east and west.
	CHECK(c.covered_ppm == 57600);
	CHECK(c.fallback_ppm == 0);
	CHECK(c.uncovered_ppm == 1000000 - 57600);
	// Covered sets: both shut (2 blind headings), one open (1), both open (0).
	const double blind = 0.16 * (0.16 * 2 + 2 * 0.4 * 0.2 * 1 + 0.2 * 0.2 * 0);
	CHECK(c.blind_milli == static_cast<int64_t>(std::llround(blind * 1000.0)));
	CHECK(c.templates_per_set.at(1) == 4);
	REQUIRE(!c.uncovered.empty());
	CHECK(c.uncovered.front().find("N-") != std::string::npos); // the likeliest gap: some edge open off the stubs
	// GEN-07's road set: every biome's hub and fallback cover every set.
	const std::shared_ptr<TemplateSet> roads = main_road_fixture::road_set();
	const h::Coverage all = h::coverage(*roads, "seam", 600000, {5, 10, 15}, {2, 3});
	CHECK(all.covered_ppm == 1000000);
	CHECK(all.uncovered.empty());
}

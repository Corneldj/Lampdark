// GEN-12: spine reach at run start. Every spine of planned runs walks from its gate to its target's
// door with every collapse point its cells arm fallen; a failing spine replans from its next
// sub-seed until its route moves, the mine derived again after each move, and a hopeless one stops
// at the replan limit.

#include "validate_fixture.h"

#include <doctest.h>

using namespace validate_fixture;
using lb::core::world::Coord;

namespace {

bool has_cell(const Spine &s, Coord c) {
	return std::find(s.cells.begin(), s.cells.end(), c) != s.cells.end();
}

Verdict blocked_at(Coord c) {
	Verdict v;
	v.check = Check::SPINE_REACH;
	v.tile = lb::core::world::tile_of(c, {10, 10});
	return v;
}

// A plan with one site whose door lies diagonally off the east gate, so routes tie at every step
// and a replan moves them.
RunPlan diagonal_plan(uint64_t seed, const std::vector<Edge> &gates, const std::vector<int64_t> &bounds) {
	RunPlan plan;
	PlannedSite site;
	site.kind = PoiKind::STORES;
	site.door = {7, 7};
	site.door_side = Edge::WEST;
	site.cells = {site.door};
	plan.sites.push_back(site);
	const std::optional<Spine> s = route_spine(seed, 0, site, gates, {site.door}, bounds, 0);
	REQUIRE(s);
	plan.spines.push_back(*s);
	return plan;
}

} // namespace

TEST_CASE("GEN-12 every spine of planned runs reaches its target with its armed collapse points fallen") {
	int64_t walked = 0;
	int64_t cells = 0;
	for (uint64_t seed : {3ull, 41ull, 977ull, 5003ull}) {
		for (int32_t kind = 0; kind < 3; kind++) {
			const auto run = planned_run(seed, kind);
			REQUIRE_MESSAGE(run->head().plan.error.empty(), run->head().plan.error);
			for (size_t i = 0; i < run->head().plan.spines.size(); i++) {
				const Verdict v = walk_spine(*run->world, run->pp, run->vp, run->head().plan, i);
				CHECK_MESSAGE(v.ok(), "seed " << seed << " list " << kind << " spine " << i << ": " << describe(v));
				walked++;
				cells += static_cast<int64_t>(run->head().plan.spines[i].cells.size());
			}
			CHECK_MESSAGE(check_gates(*run->world).ok(), describe(check_gates(*run->world)));
		}
	}
	MESSAGE(walked << " spines walked through " << cells << " cells");
	CHECK(walked > 40);
}

TEST_CASE("GEN-12 a failing spine replans until its route moves, and every spine is walked again after") {
	const std::vector<int64_t> bounds{80, 200, 400, 700};
	const std::vector<Edge> gates{Edge::NORTH, Edge::EAST, Edge::SOUTH};
	RunPlan plan = diagonal_plan(21, gates, bounds);
	const Spine first = plan.spines[0];
	// A cell the walk cannot cross: one off the diagonal midway along the first route (every route
	// passes the diagonal's tie points, but each tie may step either way).
	REQUIRE(first.cells.size() == 13);
	const Coord bad = first.cells[7];
	int32_t rebuilds = 0;
	int32_t walks = 0;
	const SpineCheck check = validate_spines(
			plan, 21, gates, bounds, 20,
			[&](size_t i) {
				walks++;
				return has_cell(plan.spines[i], bad) ? blocked_at(bad) : Verdict{};
			},
			[&]() { rebuilds++; });
	REQUIRE(check.verdicts.size() == 1);
	CHECK(check.verdicts[0].ok());
	CHECK(check.replans[0] >= 1);
	CHECK(check.total == check.replans[0]);
	CHECK(rebuilds >= 1);
	CHECK(check.rebuilds == rebuilds);
	CHECK(walks == rebuilds + 1);
	CHECK(!has_cell(plan.spines[0], bad));
	CHECK(plan.spines[0].replan >= 1);
	// The replanned route is the one route_spine gives at that sub-seed.
	const std::optional<Spine> again = route_spine(21, 0, plan.sites[0], gates, {plan.sites[0].door}, bounds, plan.spines[0].replan);
	REQUIRE(again);
	CHECK(again->cells == plan.spines[0].cells);
}

TEST_CASE("GEN-12 a spine no replan saves stops at the replan limit, unreached") {
	const std::vector<int64_t> bounds{80, 200, 400, 700};
	const std::vector<Edge> gates{Edge::NORTH, Edge::EAST, Edge::SOUTH};
	RunPlan plan = diagonal_plan(5, gates, bounds);
	int32_t rebuilds = 0;
	const SpineCheck check = validate_spines(
			plan, 5, gates, bounds, 6, [&](size_t) { return blocked_at({1, 1}); }, [&]() { rebuilds++; });
	CHECK_FALSE(check.verdicts[0].ok());
	CHECK(check.verdicts[0].check == Check::SPINE_REACH);
	CHECK(check.replans[0] == 6);
	CHECK(plan.spines[0].replan == 6);
	CHECK(rebuilds <= 6);
	// A spine that walks is never replanned.
	RunPlan fine = diagonal_plan(5, gates, bounds);
	const Spine before = fine.spines[0];
	const SpineCheck none = validate_spines(
			fine, 5, gates, bounds, 6, [](size_t) { return Verdict{}; }, [] {});
	CHECK(none.replans[0] == 0);
	CHECK(none.rebuilds == 0);
	CHECK(fine.spines[0].cells == before.cells);
}

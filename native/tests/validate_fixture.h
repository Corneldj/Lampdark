#pragma once
// GEN-12's fixtures: GEN-04's base cell fitted to the sockets its stubs cover, a biome class, the
// validator's numbers, and a whole planned run (GEN-07's road set over the design's biomes,
// GEN-08's plan and spines, GEN-10's homes) derived through the validator.

#include "core/gen/stub_fill.h"
#include "core/gen/validator.h"
#include "main_road_fixture.h"
#include "place_fixture.h"
#include "plan_fixture.h"

#include <doctest.h>

#include <memory>

namespace validate_fixture {

using namespace template_fixture;
using lb::core::world::Coord;

inline Socket open_socket(int32_t offset, int32_t width) {
	Socket s;
	s.open = true;
	s.offset = offset;
	s.width = width;
	return s;
}

// The base template's stubs: north 1 wide at 10, east and west 3 wide at 10; the south shut.
inline CellSockets base_sockets() {
	CellSockets s{};
	s[static_cast<size_t>(Edge::NORTH)] = open_socket(10, 1);
	s[static_cast<size_t>(Edge::EAST)] = open_socket(10, 3);
	s[static_cast<size_t>(Edge::WEST)] = open_socket(10, 3);
	return s;
}

// A spec's template fitted at `at`, as derive_layout would give it.
inline Layout fitted(const Template &t, const CellSockets &sockets, Coord at) {
	Layout l;
	l.coord = at;
	l.template_id = t.id;
	l.fallback = t.kind == TemplateKind::FALLBACK;
	l.sockets = sockets;
	l.cell = fill_stubs(t, sockets, at);
	return l;
}

inline Layout fitted(const Spec &s, const CellSockets &sockets = base_sockets(), Coord at = {3, 7}) {
	return fitted(make(s), sockets, at);
}

inline CellClass biome_class(const std::string &biome = "seam") {
	CellClass c;
	c.biome = biome;
	c.widths = {1, 2, 3};
	return c;
}

inline ValidatorParams params() {
	return ValidatorParams{};
}

// The world tile of a cell's local tile.
inline Coord at(Coord cell, int64_t x, int64_t y) {
	return lb::core::world::tile_of(cell, {x, y});
}

// A whole planned run on GEN-07's road set (or `set`): the design's biomes, main roads, base
// camp's gates (GEN-05's rule), the plan for a drawn list and its spines, GEN-10's homes, every
// derive through the validator, its counts kept.
struct PlannedRun {
	std::unique_ptr<main_road_fixture::RoadRun> road;
	std::unique_ptr<SpineSockets> spines;
	ValidatorParams vp;
	PlacementParams pp;
	ValidatorCounters counters;
	std::unique_ptr<Deriver> deriver;
	std::unique_ptr<DerivedWorld> world;
	std::vector<Edge> gates;

	RunHeader &head() { return road->head; }
	// The deriver and world again from the header (after its plan's spines change).
	void rebuild() {
		world.reset();
		deriver.reset();
		spines = std::make_unique<SpineSockets>(road->head.seed, road->head.plan, *road->cells, road->head.sockets);
		const SpineSockets *s = spines.get();
		road->roads->is_spine = [s](Coord c) { return s->is_spine_cell(c); };
		DeriveInputs in = road->inputs();
		in.providers.push_back(spines.get());
		in.validator = &vp;
		in.counters = &counters;
		deriver = std::make_unique<Deriver>(in);
		world = std::make_unique<DerivedWorld>(road->head, *deriver, *road->biomes, road->roads.get(), spines.get(), nullptr, nullptr,
				std::vector<int64_t>{80, 200, 400, 700});
	}
};

inline std::unique_ptr<PlannedRun> planned_run(uint64_t seed, int32_t list_kind, std::shared_ptr<TemplateSet> set = nullptr) {
	auto r = std::make_unique<PlannedRun>();
	r->road = main_road_fixture::road_run(seed, set ? std::move(set) : main_road_fixture::road_set());
	const RunHeader list = plan_fixture::header(seed, list_kind);
	RunHeader &h = r->road->head;
	h.list_kind = list.list_kind;
	h.jobs = list.jobs;
	h.cans = list.cans;
	h.solo = list.solo;
	for (int e = 0; e < 4; e++) {
		const std::optional<Socket> s = h.forced.query(edge_of({0, 0}, static_cast<Edge>(e)));
		if (s && s->open) {
			r->gates.push_back(static_cast<Edge>(e));
		}
	}
	PlanWorld pw;
	const MainRoads *roads = r->road->roads.get();
	pw.is_main_road_cell = [roads](Coord c) { return roads->is_main_road_cell(c); };
	pw.gates = r->gates;
	h.plan = make_plan(h, PlanParams{}, pw);
	for (Edge e : r->gates) {
		r->vp.arch_reach[static_cast<size_t>(e)] = 8;
	}
	r->rebuild();
	write_homes(make_homes(*r->world, r->pp), h);
	r->rebuild();
	return r;
}

} // namespace validate_fixture

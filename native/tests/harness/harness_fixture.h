#pragma once
// GEN-14's fixtures: the harness's Run over a hand-made world (GEN-10's place_fixture World, one
// prototype cell everywhere) and over a whole planned run (GEN-12's validate_fixture, its spines
// validated at run start as the server's LbLayouts does), with factories for fresh worlds.

#include "harness/harness.h"

#include "../place_fixture.h"
#include "../validate_fixture.h"

#include <memory>

namespace harness_fixture {

using namespace validate_fixture;
using lb::core::world::Coord;
using lb::harness::Run;
using lb::harness::RunFactory;

// GEN-04's base cell opened south as well (a road through it north to south, 1 wide at 10).
inline Layout through_cell() {
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

// A hand-made world as a Run: every cell the world's prototype, each cell's class its biome.
// `layout_hook` sees each final layout the run gives (to break one on purpose).
class WorldRun final : public Run {
public:
	place_fixture::World world_;
	PlacementParams pp;
	ValidatorParams vp;
	std::function<void(Layout &)> layout_hook;

	class Hooked final : public PlacementWorld {
	public:
		const WorldRun *owner = nullptr;
		const RunHeader &header() const override { return owner->world_.header(); }
		std::optional<Layout> layout(Coord c) const override {
			std::optional<Layout> l = owner->world_.layout(c);
			if (l && owner->layout_hook) {
				owner->layout_hook(*l);
			}
			return l;
		}
		CellFacts facts(Coord c) const override { return owner->world_.facts(c); }
		const std::vector<int64_t> &ring_bounds() const override { return owner->world_.ring_bounds(); }
	};
	Hooked hooked;

	WorldRun() {
		hooked.owner = this;
		world_.head = layout_fixture::header(17);
		world_.proto = through_cell();
	}
	const RunHeader &header() const override { return world_.head; }
	const PlacementWorld &world() const override { return hooked; }
	const PlacementParams &placement_params() const override { return pp; }
	const ValidatorParams &validator_params() const override { return vp; }
	CellSockets sockets(Coord c) const override { return hooked.layout(c)->sockets; }
	CellClass cell_class(Coord c) const override { return biome_class(world_.facts(c).biome); }
	std::map<std::string, int64_t> counter_totals() const override { return {}; }
};

// GEN-12 rule 6's plan: a spine east from the east gate, then north to a stores' door at (3, -2).
inline RunPlan east_then_north() {
	RunPlan plan;
	PlannedSite site;
	site.kind = PoiKind::STORES;
	site.need = "stores";
	site.door = {3, -2};
	site.door_side = Edge::SOUTH;
	site.cells = {site.door};
	plan.sites.push_back(site);
	Spine sp;
	sp.site = 0;
	sp.gate = Edge::EAST;
	sp.cells = {{1, 0}, {2, 0}, {3, 0}, {3, -1}};
	plan.spines.push_back(sp);
	return plan;
}

// A factory copying a hand-made run's world (`tweak` runs on each copy, as on the original).
inline RunFactory world_factory(std::function<void(WorldRun &)> tweak) {
	return [tweak]() -> std::unique_ptr<Run> {
		auto w = std::make_unique<WorldRun>();
		tweak(*w);
		return w;
	};
}

// A whole planned run as a Run.
class PlannedFixtureRun final : public Run {
public:
	std::unique_ptr<PlannedRun> r;
	const RunHeader &header() const override { return r->road->head; }
	const PlacementWorld &world() const override { return *r->world; }
	const PlacementParams &placement_params() const override { return r->pp; }
	const ValidatorParams &validator_params() const override { return r->vp; }
	CellSockets sockets(Coord c) const override { return r->deriver->sockets(c); }
	CellClass cell_class(Coord c) const override { return r->deriver->inputs().cells->classify(c); }
	std::map<std::string, int64_t> counter_totals() const override { return r->counters.totals(); }
	const DeriveInputs *derive_inputs() const override { return &r->deriver->inputs(); }
};

// The planned run for (seed, list) on `set`, its spines walked and replanned at run start and its
// homes made again after, as LbLayouts' validate_run_start and make_homes do.
inline std::unique_ptr<PlannedFixtureRun> planned(uint64_t seed, int32_t list, std::shared_ptr<TemplateSet> set = nullptr) {
	auto out = std::make_unique<PlannedFixtureRun>();
	out->r = planned_run(seed, list, std::move(set));
	PlannedRun &r = *out->r;
	RunHeader &h = r.head();
	validate_spines(
			h.plan, h.seed, r.gates, {80, 200, 400, 700}, r.vp.max_replans, [&r, &h](size_t i) { return walk_spine(*r.world, r.pp, r.vp, h.plan, i); },
			[&r]() { r.rebuild(); });
	write_homes(make_homes(*r.world, r.pp), h);
	r.rebuild();
	return out;
}

// Fresh worlds for a planned run: the same seed, list and set, the plan and homes as the original's.
inline RunFactory planned_factory(const PlannedFixtureRun &original, int32_t list, std::shared_ptr<TemplateSet> set = nullptr) {
	const RunPlan plan = original.header().plan;
	const std::map<std::string, std::vector<uint8_t>> homes = original.header().homes;
	const uint64_t seed = original.header().seed;
	return [plan, homes, seed, list, set]() -> std::unique_ptr<Run> {
		auto out = std::make_unique<PlannedFixtureRun>();
		out->r = planned_run(seed, list, set);
		out->r->head().plan = plan;
		out->r->head().homes = homes;
		out->r->rebuild();
		return out;
	};
}

} // namespace harness_fixture

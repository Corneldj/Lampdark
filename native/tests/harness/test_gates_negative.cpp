// GEN-14: one broken fixture per gate (and a sound run that trips none). Each names its failure's
// seed, list, check, cell and rule, and the command that repeats it: a spine blocked by an armed
// collapse, an order-dependent read of loaded state, a 4-wide chamber, an uncovered socket set,
// a template that forces long detours, a plan out of retries, ring 0-2 cells cut off from base
// camp, and generation over the budget on the reference machine.

#include "harness_fixture.h"

#include <doctest.h>

using namespace harness_fixture;
namespace h = lb::harness;

namespace {

h::Params quick() {
	h::Params p;
	p.order_cells = 24;
	p.orders = 2;
	return p;
}

h::Report report_of(const Run &run, const RunFactory &fresh, const h::Params &p) {
	h::Report r(p);
	r.add(h::check_run(run, fresh, p));
	return r;
}

bool tripped(const h::Report &r, const std::string &gate) {
	for (const h::Report::Gate &g : r.gates()) {
		if (g.name == gate) {
			return g.failed;
		}
	}
	FAIL("no gate named " << gate);
	return false;
}

const h::Failure *first(const h::Report &r, const std::string &check) {
	for (const h::Failure &f : r.failures()) {
		if (f.check == check) {
			return &f;
		}
	}
	return nullptr;
}

// A hand-made run and its factory from one tweak.
struct Made {
	std::function<void(WorldRun &)> tweak;
	WorldRun run;
	explicit Made(std::function<void(WorldRun &)> t) : tweak(std::move(t)) { tweak(run); }
	RunFactory fresh() const { return world_factory(tweak); }
};

void quiet(WorldRun &w) {
	w.pp.collapse_ppm = 0;
	w.pp.phone_ring12_ppm = 0;
	w.pp.phone_beyond_ppm = 0;
}

std::shared_ptr<TemplateSet> roads_without_hubs() {
	std::vector<Template> list = main_road_fixture::main_roads();
	for (const char *biome : {"pit_bottom", "seam", "old_workings", "black_seam", "old_mens"}) {
		Spec f = fallback_spec();
		f.id = std::string(biome) + "_plain";
		Template fb = make(f);
		fb.biome = biome;
		list.push_back(fb);
	}
	auto set = std::make_shared<TemplateSet>();
	REQUIRE(set->load(encode_pack("no_hubs", list)));
	return set;
}

// A cell whose road winds: from the west throat up and down eight columns to the east throat, the
// north and south throats joining the winding road's middle column.
Layout winding_cell() {
	Spec s;
	for (std::string &row : s.rows) {
		row = std::string(20, '#');
	}
	auto carve = [&s](int x, int y) { s.rows[static_cast<size_t>(y)][static_cast<size_t>(x)] = '.'; };
	for (int y = 9; y <= 11; y++) {
		carve(0, y);
		carve(1, y);
		for (int x = 17; x <= 19; x++) {
			carve(x, y);
		}
	}
	for (int x = 2; x <= 16; x += 2) {
		for (int y = 1; y <= 18; y++) {
			carve(x, y);
		}
	}
	for (int x = 2; x < 16; x += 2) {
		carve(x + 1, (x / 2) % 2 == 1 ? 1 : 18);
	}
	carve(10, 0);
	carve(10, 19);
	s.collapses.clear();
	Layout l;
	l.template_id = "winding";
	l.cell = cell_of(s);
	l.sockets = base_sockets();
	l.sockets[static_cast<size_t>(Edge::SOUTH)] = open_socket(10, 1);
	return l;
}

} // namespace

TEST_CASE("GEN-14 a sound planned run trips no gate of the generator's") {
	const std::shared_ptr<TemplateSet> set = main_road_fixture::road_set();
	const auto run = planned(11, 1, set);
	REQUIRE(run->header().plan.error.empty());
	h::Params p = quick();
	p.order_cells = 60;
	const h::Report r = report_of(*run, planned_factory(*run, 1, set), p);
	for (const h::Report::Gate &g : r.gates()) {
		MESSAGE(g.name, (g.failed ? ": FAIL " : ": pass "), g.detail);
	}
	CHECK_FALSE(tripped(r, "plan"));
	CHECK_FALSE(tripped(r, "spine_reach"));
	CHECK_FALSE(tripped(r, "order"));
	CHECK_FALSE(tripped(r, "validator"));
	CHECK_FALSE(tripped(r, "fallback_rate"));
	CHECK_FALSE(tripped(r, "road_ratio"));
	// GEN-16's roost count: the homes' roosts, by list, for runs with a hoard.
	CHECK(r.json(false).find("\"roosts\":{\"count\":1") != std::string::npos);
}

TEST_CASE("GEN-14 gate spine_reach: a spine blocked by an armed collapse") {
	const Made armed([](WorldRun &w) {
		w.world_.head.plan = east_then_north();
		w.pp.collapse_ppm = 1000000;
		w.pp.phone_ring12_ppm = 0;
		w.pp.phone_beyond_ppm = 0;
	});
	const h::Report r = report_of(armed.run, armed.fresh(), quick());
	CHECK(tripped(r, "spine_reach"));
	const h::Failure *f = first(r, "spine_reach");
	REQUIRE(f != nullptr);
	CHECK(f->seed == 17);
	CHECK(f->rule == 6);
	CHECK(f->cell == Coord{3, -2});
	CHECK(f->repro() == "tools/seed_harness/run.sh --repro 17 " + std::string(h::list_name(f->list)) + " spine_reach 3,-2");
	const Made unarmed([](WorldRun &w) {
		w.world_.head.plan = east_then_north();
		quiet(w);
	});
	CHECK_FALSE(tripped(report_of(unarmed.run, unarmed.fresh(), quick()), "spine_reach"));
}

TEST_CASE("GEN-14 gate order: an order-dependent read of loaded state") {
	// Every fifth layout its world gives is changed: a read of how much has been generated.
	const Made leaky([](WorldRun &w) {
		quiet(w);
		auto given = std::make_shared<int64_t>(0);
		w.layout_hook = [given](Layout &l) {
			if ((*given)++ % 5 == 0) {
				l.cell.tiles[static_cast<size_t>(Cell::index_of(1, 1))].material = static_cast<uint8_t>(TileMaterial::FLOOR);
			}
		};
	});
	const h::Report r = report_of(leaky.run, leaky.fresh(), quick());
	CHECK(tripped(r, "order"));
	const h::Failure *f = first(r, "order");
	REQUIRE(f != nullptr);
	CHECK(f->detail.find("differs between the first order and order 1") != std::string::npos);
	const Made pure(quiet);
	CHECK_FALSE(tripped(report_of(pure.run, pure.fresh(), quick()), "order"));
}

TEST_CASE("GEN-14 gate validator: a 4-wide chamber") {
	const Made four([](WorldRun &w) {
		quiet(w);
		Spec s;
		for (int y = 13; y <= 16; y++) {
			for (int x = 1; x <= 4; x++) {
				s.rows[static_cast<size_t>(y)][static_cast<size_t>(x)] = '.';
			}
		}
		s.rows[12][2] = '.';
		s.rows[19][10] = '.';
		w.world_.proto.cell = cell_of(s);
		w.world_.proto.template_id = "four_wide";
	});
	const h::Report r = report_of(four.run, four.fresh(), quick());
	CHECK(tripped(r, "validator"));
	const h::Failure *f = first(r, "validator");
	REQUIRE(f != nullptr);
	CHECK(f->rule == 4);
	CHECK(f->detail.find("four_wide") != std::string::npos);
	CHECK(f->repro().find("--repro 17 ") != std::string::npos);
}

TEST_CASE("GEN-14 gate fallback_rate: socket sets no template covers but the plain fallback") {
	const std::shared_ptr<TemplateSet> set = roads_without_hubs();
	const auto run = planned(11, 1, set);
	h::Params p = quick();
	p.order_cells = 60;
	const h::Report r = report_of(*run, planned_factory(*run, 1, set), p);
	CHECK(tripped(r, "fallback_rate"));
	CHECK(r.json(false).find("\"seam\":") != std::string::npos);
	const std::shared_ptr<TemplateSet> sound = main_road_fixture::road_set();
	const auto good = planned(11, 1, sound);
	CHECK_FALSE(tripped(report_of(*good, planned_factory(*good, 1, sound), p), "fallback_rate"));
}

TEST_CASE("GEN-14 gate road_ratio: a template that forces long detours") {
	const Made winding([](WorldRun &w) {
		quiet(w);
		w.world_.head.plan = east_then_north();
		w.world_.proto = winding_cell();
	});
	const h::Report r = report_of(winding.run, winding.fresh(), quick());
	CHECK(tripped(r, "road_ratio"));
	const h::Failure *f = first(r, "road_ratio");
	REQUIRE(f != nullptr);
	CHECK(f->cell == Coord{3, -2});
	CHECK(f->detail.find("x the straight line") != std::string::npos);
	const Made straight([](WorldRun &w) {
		quiet(w);
		w.world_.head.plan = east_then_north();
	});
	CHECK_FALSE(tripped(report_of(straight.run, straight.fresh(), quick()), "road_ratio"));
}

TEST_CASE("GEN-14 gate plan: a plan whose retries ran out") {
	const Made exhausted([](WorldRun &w) {
		quiet(w);
		w.world_.head.plan.error = "the substation's band ran out of retries";
	});
	const h::Report r = report_of(exhausted.run, exhausted.fresh(), quick());
	CHECK(tripped(r, "plan"));
	const h::Failure *f = first(r, "plan");
	REQUIRE(f != nullptr);
	CHECK(f->repro() == "tools/seed_harness/run.sh --repro 17 " + std::string(h::list_name(f->list)) + " plan");
	const Made planned_ok(quiet);
	CHECK_FALSE(tripped(report_of(planned_ok.run, planned_ok.fresh(), quick()), "plan"));
}

TEST_CASE("GEN-14 gate joined: ring 0-2 cells cut off from base camp") {
	// Only north sockets open: base camp joins a single column.
	const Made cut([](WorldRun &w) {
		quiet(w);
		for (Edge e : {Edge::EAST, Edge::WEST, Edge::SOUTH}) {
			w.world_.proto.sockets[static_cast<size_t>(e)].open = false;
		}
	});
	const h::Report r = report_of(cut.run, cut.fresh(), quick());
	CHECK(tripped(r, "joined"));
	CHECK(r.json(false).find("\"runs_joined_under\":1") != std::string::npos);
}

TEST_CASE("GEN-14 gate generation_time: over the budget, gated only on the reference machine") {
	const Made made(quiet);
	h::Params p = quick();
	p.budget_ms = -1.0; // every cell is over it
	h::Report r = report_of(made.run, made.fresh(), p);
	bool gated = false;
	for (const h::Report::Gate &g : r.gates()) {
		gated = gated || g.name == "generation_time";
	}
	CHECK_FALSE(gated);
	CHECK(r.json(false).find("not gated") == std::string::npos);
	CHECK(r.json(true).find("not gated") != std::string::npos);
	p.timing_gate = true;
	p.machine = "fleet";
	r = report_of(made.run, made.fresh(), p);
	CHECK(tripped(r, "generation_time"));
}

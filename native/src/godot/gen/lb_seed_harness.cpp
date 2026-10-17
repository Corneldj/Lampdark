#ifdef LB_DEBUG_TOOLS

#include "godot/gen/lb_seed_harness.h"

#include "harness/harness.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <mutex>
#include <thread>

using namespace godot;

namespace lb::godot {

namespace {

namespace gen = lb::core::gen;
namespace harness = lb::harness;
using lb::core::world::Coord;

// An LbLayouts as the harness's Run.
class LayoutsRun final : public harness::Run {
public:
	Ref<LbLayouts> l;
	const gen::RunHeader &header() const override { return l->gen_header(); }
	const gen::PlacementWorld &world() const override { return l->gen_world(); }
	const gen::PlacementParams &placement_params() const override { return l->gen_place_params(); }
	const gen::ValidatorParams &validator_params() const override { return l->gen_validator_params(); }
	gen::CellSockets sockets(Coord c) const override { return l->gen_deriver().sockets(c); }
	gen::CellClass cell_class(Coord c) const override { return l->gen_deriver().inputs().cells->classify(c); }
	std::map<std::string, int64_t> counter_totals() const override { return l->gen_counters().totals(); }
	const gen::DeriveInputs *derive_inputs() const override { return &l->gen_deriver().inputs(); }
};

// What one worker reads: its own copies, so no Godot container is shared between threads.
struct Inputs {
	std::shared_ptr<gen::TemplateSet> set;
	Dictionary configure;
	Dictionary plan_tuning;
};

// A run's deriver configured as MineLayouts.configure does it, its arch reach its own.
Ref<LbLayouts> configured(const Inputs &in, const Dictionary &run) {
	Ref<LbLayouts> l;
	l.instantiate();
	// A debug build derives every layout twice, its caches bypassed (GEN-05's verify): the harness's
	// own order check is the stronger test, and the second derive would cost it most of its time.
	l->set_verify(false);
	l->use_set(in.set);
	Dictionary cfg = in.configure.duplicate(true);
	Dictionary validate = cfg.get("validate", Dictionary());
	validate["arch_reach"] = run.get("arch_reach", Dictionary());
	cfg["validate"] = validate;
	l->configure(static_cast<int64_t>(run["seed"]), cfg);
	const Dictionary gates = run.get("gates", Dictionary());
	const Array sides = gates.keys();
	for (int64_t i = 0; i < sides.size(); i++) {
		l->force_socket(Vector2i(0, 0), String(sides[i]), gates[sides[i]]);
	}
	return l;
}

// The run planned as RunPlan.fix does it: the plan, the run-start check (spines replanned), then
// the homes.
std::unique_ptr<LayoutsRun> planned(const Inputs &in, const Dictionary &run) {
	auto out = std::make_unique<LayoutsRun>();
	out->l = configured(in, run);
	Dictionary p;
	for (const char *key : {"list_kind", "jobs", "cans", "solo", "draw", "staging", "hard_variant", "data_version"}) {
		if (run.has(key)) {
			p[key] = run[key];
		}
	}
	p["tuning"] = in.plan_tuning;
	const Dictionary plan = out->l->plan(p);
	if (static_cast<bool>(plan.get("ok", false))) {
		out->l->validate_run_start();
		out->l->make_homes();
	}
	return out;
}

// Fresh worlds for an order check: the run configured again, its plan and homes from its header.
harness::RunFactory factory(const Inputs &in, const Dictionary &run, const PackedByteArray &plan_bytes) {
	return [&in, run, plan_bytes]() -> std::unique_ptr<harness::Run> {
		auto out = std::make_unique<LayoutsRun>();
		out->l = configured(in, run);
		out->l->load_plan(plan_bytes);
		return out;
	};
}

std::pair<int64_t, int64_t> band(const Dictionary &d, const char *key, std::pair<int64_t, int64_t> fallback) {
	const Array a = d.get(key, Array());
	if (a.size() != 2) {
		return fallback;
	}
	return {static_cast<int64_t>(std::llround(static_cast<double>(a[0]))), static_cast<int64_t>(std::llround(static_cast<double>(a[1])))};
}

harness::Params params_of(const Dictionary &d) {
	harness::Params p;
	auto num = [&d](const char *key, double fallback) { return d.has(key) ? static_cast<double>(d[key]) : fallback; };
	p.order_cells = static_cast<int32_t>(num("order_cells", p.order_cells));
	p.orders = static_cast<int32_t>(num("orders", p.orders));
	p.spine_reach_min = num("spine_reach_min", p.spine_reach_min);
	p.road_ratio_max = num("road_ratio_max", p.road_ratio_max);
	p.road_ratio_share_max = num("road_ratio_share_max", p.road_ratio_share_max);
	p.joined_min = num("joined_min", p.joined_min);
	p.joined_max_ring = static_cast<int64_t>(num("joined_max_ring", static_cast<double>(p.joined_max_ring)));
	p.fallback_rate_max = num("fallback_rate_max", p.fallback_rate_max);
	p.explore_radius = static_cast<int32_t>(num("explore_radius", p.explore_radius));
	p.explore_max_ring = static_cast<int64_t>(num("explore_max_ring", static_cast<double>(p.explore_max_ring)));
	p.lamps = band(d, "lamps", p.lamps);
	p.kits = band(d, "kits", p.kits);
	p.flares_ring2 = band(d, "flares_ring2", p.flares_ring2);
	p.tools_ring2 = band(d, "tools_ring2", p.tools_ring2);
	p.cupboard_kits = static_cast<int64_t>(num("cupboard_kits", static_cast<double>(p.cupboard_kits)));
	p.finds_warn_share = num("finds_warn_share", p.finds_warn_share);
	p.budget_ms = num("budget_ms", p.budget_ms);
	p.timing_gate = static_cast<bool>(d.get("timing_gate", p.timing_gate));
	if (d.has("machine")) {
		const CharString m = String(d["machine"]).utf8();
		p.machine = std::string(m.get_data(), static_cast<size_t>(m.length()));
	}
	p.lair_min_bearing_deg = num("lair_min_bearing_deg", p.lair_min_bearing_deg);
	p.failures_kept_per_check = static_cast<int32_t>(num("failures_kept_per_check", p.failures_kept_per_check));
	return p;
}

String text(const std::string &s) {
	return String::utf8(s.c_str(), static_cast<int>(s.size()));
}

} // namespace

void LbSeedHarness::_bind_methods() {
	ClassDB::bind_static_method("LbSeedHarness", D_METHOD("run", "base", "configure", "runs", "options"), &LbSeedHarness::run);
	ClassDB::bind_static_method("LbSeedHarness", D_METHOD("repro", "base", "configure", "run", "options", "check", "cell"), &LbSeedHarness::repro);
}

Dictionary LbSeedHarness::run(const Ref<LbLayouts> &base, const Dictionary &configure, const Array &runs, const Dictionary &options) {
	Dictionary out;
	ERR_FAIL_COND_V_MSG(base.is_null() || !base->template_set(), out, "LbSeedHarness.run: no template pack");
	const harness::Params p = params_of(options.get("params", Dictionary()));
	const int64_t asked = static_cast<int64_t>(options.get("threads", 0));
	const int64_t threads = std::max<int64_t>(1, asked > 0 ? asked : static_cast<int64_t>(std::thread::hardware_concurrency()));
	const double progress_s = static_cast<double>(options.get("progress_s", 30.0));
	// Every worker its own copies of the inputs, every run its own dictionary.
	std::vector<Inputs> inputs(static_cast<size_t>(threads));
	for (Inputs &in : inputs) {
		in.set = base->template_set();
		in.configure = configure.duplicate(true);
		in.plan_tuning = Dictionary(options.get("plan_tuning", Dictionary())).duplicate(true);
	}
	std::vector<Dictionary> list;
	list.reserve(static_cast<size_t>(runs.size()));
	for (int64_t i = 0; i < runs.size(); i++) {
		list.push_back(Dictionary(runs[i]).duplicate(true));
	}
	harness::Report report(p);
	std::mutex mutex;
	std::atomic<size_t> next{0};
	std::atomic<size_t> done{0};
	const auto t0 = std::chrono::steady_clock::now();
	std::vector<std::thread> pool;
	for (int64_t w = 0; w < threads; w++) {
		pool.emplace_back([&, w] {
			const Inputs &in = inputs[static_cast<size_t>(w)];
			for (size_t i = next++; i < list.size(); i = next++) {
				const std::unique_ptr<LayoutsRun> r = planned(in, list[i]);
				const harness::RunResult result = harness::check_run(*r, factory(in, list[i], r->l->plan_bytes()), p);
				{
					std::lock_guard<std::mutex> lock(mutex);
					report.add(result);
				}
				done++;
			}
		});
	}
	auto last = std::chrono::steady_clock::now();
	while (done.load() < list.size()) {
		std::this_thread::sleep_for(std::chrono::milliseconds(200));
		const auto now = std::chrono::steady_clock::now();
		if (progress_s > 0.0 && std::chrono::duration<double>(now - last).count() >= progress_s) {
			last = now;
			UtilityFunctions::print("seed harness: ", static_cast<int64_t>(done.load()), " of ", static_cast<int64_t>(list.size()), " runs, ",
					String::num(std::chrono::duration<double>(now - t0).count(), 0), " s");
		}
	}
	for (std::thread &t : pool) {
		t.join();
	}
	const Array lists = options.get("lists", Array());
	std::vector<int32_t> lv;
	for (int64_t i = 0; i < lists.size(); i++) {
		lv.push_back(static_cast<int32_t>(static_cast<int64_t>(lists[i])));
	}
	report.set_range(static_cast<uint64_t>(static_cast<int64_t>(options.get("first_seed", 0))), static_cast<uint64_t>(static_cast<int64_t>(options.get("last_seed", 0))),
			lv);
	report.set_pack(base->template_set()->set_version());
	Array gates;
	for (const harness::Report::Gate &g : report.gates()) {
		Dictionary d;
		d["name"] = text(g.name);
		d["failed"] = g.failed;
		d["detail"] = text(g.detail);
		gates.push_back(d);
	}
	out["json"] = text(report.json(false));
	out["timing_json"] = text(report.json(true));
	out["markdown"] = text(report.markdown());
	out["failed"] = report.failed();
	out["gates"] = gates;
	out["runs"] = report.runs();
	out["seconds"] = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
	out["threads"] = threads;
	return out;
}

String LbSeedHarness::repro(const Ref<LbLayouts> &base, const Dictionary &configure, const Dictionary &run, const Dictionary &options,
		const String &check, const Variant &cell) {
	ERR_FAIL_COND_V_MSG(base.is_null() || !base->template_set(), String(), "LbSeedHarness.repro: no template pack");
	Inputs in;
	in.set = base->template_set();
	in.configure = configure.duplicate(true);
	in.plan_tuning = Dictionary(options.get("plan_tuning", Dictionary())).duplicate(true);
	const harness::Params p = params_of(options.get("params", Dictionary()));
	const Dictionary one = run.duplicate(true);
	const std::unique_ptr<LayoutsRun> r = planned(in, one);
	std::optional<Coord> at;
	if (cell.get_type() == Variant::VECTOR2I) {
		const Vector2i v = cell;
		at = Coord{v.x, v.y};
	}
	const CharString c = check.utf8();
	return text(harness::repro(*r, factory(in, one, r->l->plan_bytes()), p, std::string(c.get_data(), static_cast<size_t>(c.length())), at));
}

} // namespace lb::godot

#endif

// GEN-12 over many seeds (LB_VALIDATOR_SEEDS, 12 by default, on LB_VALIDATOR_THREADS threads; GEN-14's
// harness runs 10,000 on the shipped set): for every list, every spine reaches its target with its armed collapse points
// fallen and base camp's gates hold, and no final cell on a spine, at a door or round base camp
// breaks a rule. The run's reroll, fallback and retry counts are reported by biome and rule. The
// template set is GEN-07's road set with a failing grid mixed into the Seam and the Old Workings,
// so rerolls happen.

#include "validate_fixture.h"

#include <doctest.h>

#include <cstdlib>
#include <mutex>
#include <thread>

using namespace validate_fixture;
using lb::core::world::Coord;

namespace {

std::shared_ptr<TemplateSet> noisy_road_set() {
	std::vector<Template> list = main_road_fixture::main_roads();
	for (const char *biome : {"pit_bottom", "seam", "old_workings", "black_seam", "old_mens"}) {
		Template g = layout_fixture::grid(std::string(biome) + "_grid", 1.0);
		g.biome = biome;
		list.push_back(g);
		Spec f = fallback_spec();
		f.id = std::string(biome) + "_plain";
		Template fb = make(f);
		fb.biome = biome;
		list.push_back(fb);
		if (std::string(biome) == "seam" || std::string(biome) == "old_workings") {
			Spec bad = fallback_spec();
			bad.id = std::string(biome) + "_bad";
			bad.kind = TemplateKind::BIOME_CELL;
			bad.rows[1][1] = '.'; // a floor tile no road reaches: rule 7
			Template b = make(bad);
			b.biome = biome;
			b.weight = 0.5;
			list.push_back(b);
		}
	}
	auto set = std::make_shared<TemplateSet>();
	REQUIRE(set->load(encode_pack("noisy_roads", list)));
	return set;
}

struct Tally {
	std::mutex mutex;
	int64_t runs = 0;
	int64_t spines = 0;
	int64_t reached = 0;
	int64_t gates_failed = 0;
	int64_t cells = 0;
	int64_t final_invalid = 0;
	int64_t placement_invalid = 0;
	int64_t plan_failed = 0;
	std::map<std::string, int64_t> totals;
	std::vector<std::string> failures;
};

void one_run(uint64_t seed, int32_t kind, const std::shared_ptr<TemplateSet> &set, Tally &t) {
	const auto run = planned_run(seed, kind, set);
	const RunPlan &plan = run->head().plan;
	int64_t spines = 0;
	int64_t reached = 0;
	int64_t cells = 0;
	int64_t final_invalid = 0;
	int64_t placement_invalid = 0;
	std::vector<std::string> failures;
	if (!plan.error.empty()) {
		std::lock_guard<std::mutex> lock(t.mutex);
		t.plan_failed++;
		return;
	}
	std::set<Coord> checked;
	for (int64_t y = -2; y <= 2; y++) {
		for (int64_t x = -2; x <= 2; x++) {
			checked.insert({x, y});
		}
	}
	for (size_t i = 0; i < plan.spines.size(); i++) {
		spines++;
		const Verdict v = walk_spine(*run->world, run->pp, run->vp, plan, i);
		if (v.ok()) {
			reached++;
		} else {
			failures.push_back("seed " + std::to_string(seed) + " list " + std::to_string(kind) + " spine " + std::to_string(i) + ": " + describe(v));
		}
		checked.insert(plan.spines[i].cells.begin(), plan.spines[i].cells.end());
		checked.insert(plan.sites[static_cast<size_t>(plan.spines[i].site)].door);
	}
	const Verdict gates = check_gates(*run->world);
	for (const Coord &c : checked) {
		const std::optional<Layout> l = run->deriver->derive_final(c);
		if (!l || l->base_camp) {
			continue;
		}
		cells++;
		const Verdict lv = validate_layout(*l, run->road->cells->classify(c), run->vp);
		if (!lv.ok()) {
			final_invalid++;
			failures.push_back("seed " + std::to_string(seed) + " cell (" + std::to_string(c.x) + ", " + std::to_string(c.y) + "): " + describe(lv));
		}
		const PlacedCell p = place_validated(*run->world, run->pp, run->vp, c);
		run->counters.count_placement(c, p);
		const Verdict pv = validate_placement(placement_context(*run->world, run->pp, run->vp, c), p.list);
		if (!pv.ok()) {
			placement_invalid++;
			failures.push_back("seed " + std::to_string(seed) + " placement (" + std::to_string(c.x) + ", " + std::to_string(c.y) + "): " + describe(pv));
		}
	}
	std::lock_guard<std::mutex> lock(t.mutex);
	t.runs++;
	t.spines += spines;
	t.reached += reached;
	t.gates_failed += gates.ok() ? 0 : 1;
	t.cells += cells;
	t.final_invalid += final_invalid;
	t.placement_invalid += placement_invalid;
	for (const auto &[key, n] : run->counters.totals()) {
		t.totals[key] += n;
	}
	for (const std::string &f : failures) {
		if (t.failures.size() < 10) {
			t.failures.push_back(f);
		}
	}
}

std::string rate(int64_t part, int64_t whole) {
	if (whole <= 0) {
		return "0";
	}
	const int64_t per_mille = part * 100000 / whole;
	return std::to_string(per_mille / 1000) + "." + std::to_string(1000 + per_mille % 1000).substr(1) + "%";
}

} // namespace

TEST_CASE("GEN-12 over many seeds no final cell breaks a rule and every spine reaches its target") {
	int64_t seeds = 12;
	if (const char *v = std::getenv("LB_VALIDATOR_SEEDS")) {
		seeds = std::max<int64_t>(1, std::atoll(v));
	}
	const std::shared_ptr<TemplateSet> set = noisy_road_set();
	Tally t;
	int64_t threads = seeds >= 64 ? std::max<int64_t>(1, static_cast<int64_t>(std::thread::hardware_concurrency())) : 1;
	if (const char *v = std::getenv("LB_VALIDATOR_THREADS")) {
		threads = std::max<int64_t>(1, std::atoll(v));
	}
	std::vector<std::thread> pool;
	for (int64_t w = 0; w < threads; w++) {
		pool.emplace_back([&, w] {
			for (int64_t s = w; s < seeds; s += threads) {
				for (int32_t kind = 0; kind < 3; kind++) {
					one_run(static_cast<uint64_t>(1000 + s), kind, set, t);
				}
			}
		});
	}
	for (std::thread &th : pool) {
		th.join();
	}
	for (const std::string &f : t.failures) {
		MESSAGE(f);
	}
	CHECK(t.plan_failed == 0);
	CHECK(t.runs == seeds * 3);
	CHECK(t.reached == t.spines);
	CHECK(t.gates_failed == 0);
	CHECK(t.final_invalid == 0);
	CHECK(t.placement_invalid == 0);
	CHECK(t.totals["shipped_invalid"] == 0);
	CHECK(t.totals["rerolled"] > 0);
	// The report: rates by biome and rule.
	std::string report = std::to_string(seeds) + " seeds x 3 lists: " + std::to_string(t.spines) + " spines, " + rate(t.reached, t.spines) +
			" reached; " + std::to_string(t.cells) + " cells checked";
	for (const char *biome : {"pit_bottom", "seam", "old_workings", "black_seam", "old_mens", "main_road"}) {
		const int64_t cells = t.totals["cells." + std::string(biome)];
		report += "\n  " + std::string(biome) + ": " + std::to_string(cells) + " cells, rerolled " + rate(t.totals["rerolled." + std::string(biome)], cells) +
				", fallback " + rate(t.totals["fallbacks." + std::string(biome)], cells);
	}
	for (int32_t rule = 1; rule < static_cast<int32_t>(Check::COUNT); rule++) {
		const int64_t failed = t.totals["failed." + std::to_string(rule)];
		const int64_t placed = t.totals["placement_failed." + std::to_string(rule)];
		if (failed > 0 || placed > 0) {
			report += "\n  rule " + std::to_string(rule) + " (" + check_name(static_cast<Check>(rule)) + "): " + std::to_string(failed) + " layout tries failed, " +
					std::to_string(placed) + " placement tries failed";
		}
	}
	report += "\n  placement: " + std::to_string(t.totals["placed"]) + " cells, " + std::to_string(t.totals["retried"]) + " retried, " +
			std::to_string(t.totals["strict"]) + " strict (" + std::to_string(t.totals["dropped"]) + " dropped)";
	MESSAGE(report);
}

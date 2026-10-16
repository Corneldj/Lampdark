// GEN-08: retries. Each try takes its site's next sub-seed; the retries never run out over 10,000
// seeds of the longest list, solo or not (the bands test covers every list); replanning a spine
// from a sub-seed is deterministic; and planning meets the 50 ms budget on this machine (the
// Deck's 150 ms is QA-03's to measure).

#include "plan_fixture.h"

#include <doctest.h>

#include <chrono>

using namespace plan_fixture;

TEST_CASE("GEN-08 the retries never run out, even solo") {
	int32_t worst = 0;
	int64_t sites = 0;
	int64_t retried = 0;
	for (uint64_t s = 0; s < 10000; s++) {
		const RunHeader h = planned(lb::core::mix64(s + 0xAE7), 2, s % 2 == 0);
		REQUIRE_MESSAGE(h.plan.error.empty(), "seed ", s, ": ", h.plan.error);
		for (const PlannedSite &site : h.plan.sites) {
			worst = std::max(worst, site.attempt);
			retried += site.attempt > 0 ? 1 : 0;
			sites++;
		}
	}
	MESSAGE(sites, " sites, ", retried, " placed on a retry; the most tries for one: ", worst + 1);
	CHECK(worst < PlanParams{}.max_retries);
}

TEST_CASE("GEN-08 replanning a spine is deterministic") {
	const RunHeader h = planned(5150, 1);
	REQUIRE(h.plan.error.empty());
	std::set<Coord> footprints;
	for (const PlannedSite &site : h.plan.sites) {
		footprints.insert(site.cells.begin(), site.cells.end());
	}
	const std::vector<Edge> gates = world(blind_of(5150)).gates;
	for (const Spine &sp : h.plan.spines) {
		const PlannedSite &site = h.plan.sites[static_cast<size_t>(sp.site)];
		for (int32_t replan = 1; replan <= 3; replan++) {
			const std::optional<Spine> a = route_spine(h.seed, sp.site, site, gates, footprints, bounds(), replan);
			const std::optional<Spine> b = route_spine(h.seed, sp.site, site, gates, footprints, bounds(), replan);
			REQUIRE(a.has_value());
			REQUIRE(b.has_value());
			CHECK(a->cells == b->cells);
			CHECK(a->gate == b->gate);
			CHECK(a->replan == replan);
			CHECK(a->cells.back() == site.approach());
		}
	}
}

TEST_CASE("GEN-08 planning stays within its budget") {
	std::vector<double> ms;
	for (uint64_t s = 0; s < 2000; s++) {
		const auto t0 = std::chrono::steady_clock::now();
		const RunHeader h = planned(lb::core::mix64(s + 0xB0D6E7), 2);
		const auto t1 = std::chrono::steady_clock::now();
		REQUIRE(h.plan.error.empty());
		ms.push_back(std::chrono::duration<double, std::milli>(t1 - t0).count());
	}
	std::sort(ms.begin(), ms.end());
	const double p50 = ms[ms.size() / 2];
	const double p99 = ms[ms.size() * 99 / 100];
	MESSAGE("plan ms: p50 ", p50, ", p99 ", p99, ", max ", ms.back());
	CHECK(p99 < 50.0);
}

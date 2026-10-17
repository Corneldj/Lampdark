// GEN-14 at scale on the fixture set (GEN-07's roads, a hub and a plain fallback per biome): the
// harness's default numbers (400 cells in three orders) over LB_HARNESS_SEEDS seeds (2 by
// default) and the three lists, on every core, reporting runs a second and the gates, so the CI
// budget (Proposed: 10,000 seeds in 30 minutes) can be read off a machine.

#include "harness_fixture.h"

#include <doctest.h>

#include <atomic>
#include <chrono>
#include <cstdlib>
#include <mutex>
#include <thread>

using namespace harness_fixture;
namespace h = lb::harness;

TEST_CASE("GEN-14 the harness at its default numbers over many fixture seeds") {
	int64_t seeds = 2;
	if (const char *v = std::getenv("LB_HARNESS_SEEDS")) {
		seeds = std::max<int64_t>(1, std::atoll(v));
	}
	const std::shared_ptr<TemplateSet> set = main_road_fixture::road_set();
	const h::Params p;
	h::Report report(p);
	std::mutex mutex;
	std::atomic<int64_t> next{0};
	const int64_t runs = seeds * 3;
	const int64_t threads = std::max<int64_t>(1, std::min<int64_t>(runs, static_cast<int64_t>(std::thread::hardware_concurrency())));
	const auto t0 = std::chrono::steady_clock::now();
	std::vector<std::thread> pool;
	for (int64_t w = 0; w < threads; w++) {
		pool.emplace_back([&] {
			for (int64_t i = next++; i < runs; i = next++) {
				const uint64_t seed = static_cast<uint64_t>(2000 + i / 3);
				const int32_t list = static_cast<int32_t>(i % 3);
				const auto run = planned(seed, list, set);
				const h::RunResult r = h::check_run(*run, planned_factory(*run, list, set), p);
				std::lock_guard<std::mutex> lock(mutex);
				report.add(r);
			}
		});
	}
	for (std::thread &t : pool) {
		t.join();
	}
	const double s = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
	CHECK(report.runs() == runs);
	for (const h::Report::Gate &g : report.gates()) {
		MESSAGE(g.name, (g.failed ? ": FAIL " : ": pass "), g.detail);
	}
	CHECK(report.failure_count("order") == 0);
	CHECK(report.failure_count("plan") == 0);
	MESSAGE(runs, " runs in ", s, " s on ", threads, " threads: ", static_cast<double>(runs) / s, " runs a second; 30,000 runs would take ",
			30000.0 / (static_cast<double>(runs) / s) / 60.0, " minutes here");
}

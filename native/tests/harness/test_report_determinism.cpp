// GEN-14: two runs over the same seeds and binaries give byte-identical reports, timing aside,
// whatever order the runs reach the report in (the harness's threads finish in any order).

#include "harness_fixture.h"

#include <doctest.h>

#include <algorithm>

using namespace harness_fixture;
namespace h = lb::harness;

namespace {

std::vector<h::RunResult> check_all(const std::shared_ptr<TemplateSet> &set, const h::Params &p) {
	std::vector<h::RunResult> out;
	for (uint64_t seed : {11u, 12u, 13u}) {
		for (int32_t list : {0, 1}) {
			const auto run = planned(seed, list, set);
			out.push_back(h::check_run(*run, planned_factory(*run, list, set), p));
		}
	}
	return out;
}

} // namespace

TEST_CASE("GEN-14 the same seeds give the same report bytes in any order, timing aside") {
	const std::shared_ptr<TemplateSet> set = main_road_fixture::road_set();
	h::Params p;
	p.order_cells = 40;
	p.orders = 2;
	const std::vector<h::RunResult> results = check_all(set, p);
	h::Report forward(p);
	h::Report backward(p);
	for (const h::RunResult &r : results) {
		forward.add(r);
	}
	for (auto it = results.rbegin(); it != results.rend(); ++it) {
		backward.add(*it);
	}
	for (h::Report *r : {&forward, &backward}) {
		r->set_pack("fixture");
		r->set_range(11, 13, {0, 1});
	}
	CHECK(forward.runs() == 6);
	CHECK(forward.json(false) == backward.json(false));
	// From nothing again: the same bytes.
	h::Report again(p);
	for (const h::RunResult &r : check_all(set, p)) {
		again.add(r);
	}
	again.set_pack("fixture");
	again.set_range(11, 13, {0, 1});
	CHECK(again.json(false) == forward.json(false));
	// Timing is its own section, absent from the canonical bytes.
	CHECK(forward.json(false).find("timing_us") == std::string::npos);
	CHECK(forward.json(true).find("\"timing_us\"") != std::string::npos);
	CHECK(forward.markdown().find("## Gates") != std::string::npos);
}

TEST_CASE("GEN-14 a report keeps the same failures whichever runs it meets first") {
	h::Params p;
	p.failures_kept_per_check = 2;
	std::vector<h::RunResult> results;
	for (uint64_t seed = 1; seed <= 5; seed++) {
		h::RunResult r;
		r.seed = seed;
		r.list = 1;
		h::Failure f;
		f.check = "order";
		f.seed = seed;
		f.list = 1;
		f.cell = {static_cast<int64_t>(seed), 0};
		f.detail = "cell differs";
		r.failures.push_back(f);
		r.failure_counts["order"] = 1;
		results.push_back(r);
	}
	h::Report a(p);
	h::Report b(p);
	for (const h::RunResult &r : results) {
		a.add(r);
	}
	std::reverse(results.begin(), results.end());
	for (const h::RunResult &r : results) {
		b.add(r);
	}
	REQUIRE(a.failures().size() == 2);
	CHECK(a.failures()[0].seed == 1);
	CHECK(a.failures()[1].seed == 2);
	CHECK(a.json(false) == b.json(false));
	CHECK(a.failure_count("order") == 5);
}

// GEN-12: a failing cell rerolls from the next sub-seed until a template passes phase 1, and at
// the reroll limit takes its biome's plain fallback; the reroll count, the final template and the
// placement are the same in any generation order and with any thread count.

#include "core/gen/gen_pool.h"
#include "core/rng/rng.h"
#include "validate_fixture.h"

#include <doctest.h>

#include <algorithm>
#include <chrono>
#include <cstdlib>
#include <thread>

using namespace validate_fixture;
using lb::core::world::Coord;

namespace {

// GEN-05's grid with an isolated floor tile: it covers every socket set and fails rule 7.
Template bad_grid(const std::string &id, double weight) {
	Spec s = fallback_spec();
	s.id = id;
	s.kind = TemplateKind::BIOME_CELL;
	s.rows[1][1] = '.';
	Template t = make(s);
	t.weight = weight;
	return t;
}

std::shared_ptr<TemplateSet> noisy_set(bool any_good = true, double bad_weight = 3.0) {
	std::vector<Template> list{bad_grid("seam_bad", bad_weight), make(fallback_spec())};
	if (any_good) {
		list.push_back(layout_fixture::grid("seam_good", 1.0));
	}
	auto set = std::make_shared<TemplateSet>();
	REQUIRE(set->load(encode_pack("noisy", list)));
	return set;
}

struct Validated {
	layout_fixture::Run run;
	ValidatorParams vp;
	ValidatorCounters counters;
	explicit Validated(std::shared_ptr<TemplateSet> set, uint64_t seed = 77) : run(layout_fixture::run(seed, std::move(set))) {}
	DeriveInputs inputs() {
		DeriveInputs in = run.inputs();
		in.validator = &vp;
		in.counters = &counters;
		return in;
	}
};

std::vector<Coord> square(int64_t r) {
	std::vector<Coord> out;
	for (int64_t y = -r; y <= r; y++) {
		for (int64_t x = -r; x <= r; x++) {
			out.push_back({x, y});
		}
	}
	return out;
}

struct Outcome {
	int32_t reroll = -1;
	std::string id;
	uint64_t digest = 0;
	bool operator==(const Outcome &o) const { return reroll == o.reroll && id == o.id && digest == o.digest; }
};

Outcome outcome(const std::optional<Layout> &l) {
	return l ? Outcome{l->reroll, l->template_id, l->digest} : Outcome{};
}

} // namespace

TEST_CASE("GEN-12 a failing cell rerolls to the first template that passes, the fallback at the limit") {
	Validated v(noisy_set());
	const DeriveInputs in = v.inputs();
	const int32_t limit = v.run.head.reroll_limit;
	REQUIRE(limit == 20);
	int64_t rerolled = 0;
	int64_t fallbacks = 0;
	for (const Coord &c : square(10)) {
		std::vector<LayoutTry> tried;
		const std::optional<Layout> l = derive_final(in, c, &tried);
		REQUIRE(l);
		if (l->base_camp) {
			continue;
		}
		// The first reroll whose hash pick is the good template; the fallback if none is by the limit.
		int32_t want = limit;
		for (int32_t k = 0; k < limit; k++) {
			const Choice pick = choose_template(*v.run.set, TemplateKind::BIOME_CELL, "seam", l->sockets, v.run.head.seed, c, k, limit);
			if (pick.chosen != nullptr && pick.chosen->id == "seam_good") {
				want = k;
				break;
			}
		}
		CHECK(l->reroll == want);
		CHECK(l->template_id == (want < limit ? "seam_good" : "fixture_seam_fallback"));
		CHECK(l->fallback == (want == limit));
		CHECK(validate_layout(*l, v.run.cells.classify(c), v.vp).ok());
		CHECK(tried.size() == static_cast<size_t>(want));
		for (const LayoutTry &t : tried) {
			CHECK(t.template_id == "seam_bad");
			CHECK(t.verdict.check == Check::CONNECTED);
			CHECK(lb::core::world::cell_of(t.verdict.tile) == c);
		}
		rerolled += l->reroll > 0 ? 1 : 0;
		fallbacks += l->fallback ? 1 : 0;
	}
	MESSAGE("of 440 cells, " << rerolled << " rerolled, " << fallbacks << " took the fallback");
	CHECK(rerolled > 200);
	// With no template that passes, every cell rerolls to the limit and takes the plain fallback.
	Validated all_bad(noisy_set(false));
	const DeriveInputs bad_in = all_bad.inputs();
	for (const Coord &c : {Coord{3, 1}, Coord{-5, 2}, Coord{0, 7}}) {
		std::vector<LayoutTry> tried;
		const std::optional<Layout> l = derive_final(bad_in, c, &tried);
		REQUIRE(l);
		CHECK(l->fallback);
		CHECK(l->reroll == limit);
		CHECK(tried.size() == static_cast<size_t>(limit));
	}
	// Without the validator, reroll 0 as GEN-05 derives it.
	Validated off(noisy_set());
	DeriveInputs plain = off.inputs();
	plain.validator = nullptr;
	const std::optional<Layout> raw = derive_final(plain, {3, 1});
	REQUIRE(raw);
	CHECK(raw->reroll == 0);
	CHECK(raw->digest == derive_layout(plain, {3, 1}, 0)->digest);
}

TEST_CASE("GEN-12 the counters keep each cell once, by rule, biome and template") {
	Validated v(noisy_set());
	Deriver d(v.inputs());
	for (int pass = 0; pass < 3; pass++) {
		for (const Coord &c : square(6)) {
			d.derive_final(c);
		}
		d.clear_caches();
	}
	const std::map<std::string, int64_t> n = v.counters.totals();
	CHECK(n.at("cells") == 13 * 13 - 1); // base camp is GEN-02's
	CHECK(n.at("cells.seam") == n.at("cells"));
	CHECK(n.at("rerolled") > 0);
	CHECK(n.at("failed.7") == n.at("rerolls")); // each reroll followed one failed try
	CHECK(n.at("failed.7.seam") == n.at("failed.7"));
	CHECK(n.at("failed.7.seam_bad") == n.at("failed.7"));
	CHECK(n.count("shipped_invalid") == 0);
	CHECK(!v.counters.notes().empty());
	CHECK(v.counters.notes().front().find("rule 7 (connected)") != std::string::npos);
}

TEST_CASE("GEN-12 rerolls, templates and placements are the same in any order and on any thread count") {
	const std::shared_ptr<TemplateSet> set = noisy_set();
	std::vector<Coord> cells = square(9);
	std::map<Coord, Outcome> first;
	std::map<Coord, uint64_t> placed_first;
	for (int order = 0; order < 3; order++) {
		Validated v(set);
		const Deriver d(v.inputs());
		DerivedWorld world(v.run.head, d, v.run.cells, nullptr, nullptr, nullptr, nullptr, {80, 200, 400, 700});
		const PlacementParams pp;
		std::vector<Coord> shuffled = cells;
		lb::core::Rng r(0xC0FFEEull + static_cast<uint64_t>(order));
		r.shuffle(shuffled);
		if (order == 2) {
			std::reverse(shuffled.begin(), shuffled.end());
		}
		for (const Coord &c : shuffled) {
			const Outcome o = outcome(d.derive_final(c));
			const PlacedCell p = place_validated(world, pp, v.vp, c);
			const uint64_t digest = placement_digest(p.list) ^ (static_cast<uint64_t>(p.retry) << 48) ^ (p.strict ? 1ull << 60 : 0);
			if (order == 0) {
				first[c] = o;
				placed_first[c] = digest;
			} else {
				CHECK(o == first[c]);
				CHECK(digest == placed_first[c]);
			}
		}
	}
	// Uncached, and through GEN-11's pool on 0, 1 and 4 threads.
	for (int threads : {0, 1, 4}) {
		Validated v(set);
		Deriver d(v.inputs());
		d.set_caching(threads != 1);
		GenPool pool(d, threads);
		for (const Coord &c : cells) {
			pool.want(c, std::abs(c.x) + std::abs(c.y));
		}
		size_t got = 0;
		const auto until = std::chrono::steady_clock::now() + std::chrono::seconds(60);
		while (got < cells.size() && std::chrono::steady_clock::now() < until) {
			const std::vector<GenPool::Result> results = pool.take(64);
			for (const GenPool::Result &res : results) {
				CHECK(outcome(res.layout) == first[res.cell]);
				got++;
			}
			if (results.empty()) {
				std::this_thread::sleep_for(std::chrono::milliseconds(1));
			}
		}
		CHECK(got == cells.size());
	}
}

TEST_CASE("GEN-12 validation and a typical reroll fit GEN-11's budget for a cell") {
	// A third of the Seam's picks fail here, so a cell rerolls about once in two. Each cell derives
	// once on a fresh deriver, as GEN-11's workers ask (phase 1 with its rerolls); then each inner
	// cell places with its neighbours derived, as a cell commits inside the prefetch ring (phase 2).
	Validated v(noisy_set(true, 0.5));
	const Deriver d(v.inputs());
	DerivedWorld world(v.run.head, d, v.run.cells, nullptr, nullptr, nullptr, nullptr, {80, 200, 400, 700});
	const PlacementParams pp;
	std::vector<double> derive_ms;
	std::vector<double> place_ms;
	int64_t rerolls = 0;
	for (const Coord &c : square(10)) {
		const auto t0 = std::chrono::steady_clock::now();
		const std::optional<Layout> l = d.derive_final(c);
		derive_ms.push_back(std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count());
		rerolls += l ? l->reroll : 0;
	}
	for (const Coord &c : square(8)) {
		const auto t0 = std::chrono::steady_clock::now();
		place_validated(world, pp, v.vp, c);
		place_ms.push_back(std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count());
	}
	std::sort(derive_ms.begin(), derive_ms.end());
	std::sort(place_ms.begin(), place_ms.end());
	auto at = [](const std::vector<double> &t, double f) { return t[std::min(t.size() - 1, static_cast<size_t>(f * static_cast<double>(t.size())))]; };
	MESSAGE(derive_ms.size() << " cells, " << rerolls << " rerolls: derive with phase 1 p50 " << at(derive_ms, 0.5) << " ms, p99 " << at(derive_ms, 0.99)
						  << " ms; placement with phase 2 p50 " << at(place_ms, 0.5) << " ms, p99 " << at(place_ms, 0.99) << " ms");
#ifndef LB_DEBUG_TOOLS
	// GEN-11's 1 ms a cell on a fleet core (GDD §C.11). CI's shared runners report it (FND-04).
	if (std::getenv("LB_TIMING_REPORT_ONLY") == nullptr) {
		CHECK(at(derive_ms, 0.99) < 1.0);
		CHECK(at(place_ms, 0.99) < 1.0);
	}
#endif
}

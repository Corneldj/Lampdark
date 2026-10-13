#include "core/rng/rng.h"
#include "golden/rng_golden.gen.h"

#include <doctest.h>

#include <cstdint>
#include <limits>
#include <numeric>
#include <vector>

using namespace lb::core;

TEST_CASE("SplitMix64 matches the published reference outputs (seed 1234567)") {
	Rng rng(1234567);
	CHECK(rng.next_u64() == 6457827717110365317ULL);
	CHECK(rng.next_u64() == 3203168211198807973ULL);
	CHECK(rng.next_u64() == 9817491932198370423ULL);
	CHECK(rng.next_u64() == 4593380528125082431ULL);
	CHECK(rng.next_u64() == 16408922859458223821ULL);
}

TEST_CASE("streams reproduce the golden outputs") {
	CHECK(golden::STREAMS.size() == 8);
	for (const golden::Stream &s : golden::STREAMS) {
		Rng rng(s.seed);
		for (uint64_t expected : s.outputs) {
			CHECK(rng.next_u64() == expected);
		}
	}
}

TEST_CASE("range reproduces the golden draws and stays in bounds") {
	for (const golden::Range &r : golden::RANGES) {
		Rng rng(r.seed);
		const int64_t lo = static_cast<int64_t>(r.lo);
		const int64_t hi = static_cast<int64_t>(r.hi);
		for (uint64_t expected : r.draws) {
			const int64_t got = *rng.range(lo, hi);
			CHECK(static_cast<uint64_t>(got) == expected);
			CHECK(got >= lo);
			CHECK(got <= hi);
		}
	}
	Rng rng(9);
	CHECK(*rng.range(5, 5) == 5);
	CHECK_FALSE(rng.range(6, 5).has_value());
}

TEST_CASE("range(0, 9) passes chi-square over 10^6 draws") {
	Rng rng(20261011);
	int64_t counts[10] = {};
	const int64_t draws = 1000000;
	for (int64_t i = 0; i < draws; i++) {
		counts[*rng.range(0, 9)]++;
	}
	const double expected = draws / 10.0;
	double chi2 = 0;
	for (int64_t c : counts) {
		chi2 += (c - expected) * (c - expected) / expected;
	}
	MESSAGE("chi-square (9 dof): " << chi2);
	CHECK(chi2 < 27.877); // p > 0.001 for 9 degrees of freedom
}

TEST_CASE("chance_ppm reproduces the golden results") {
	for (const golden::Chance &c : golden::CHANCES) {
		Rng rng(c.seed);
		for (int expected : c.results) {
			CHECK(rng.chance_ppm(c.ppm) == (expected == 1));
		}
	}
}

TEST_CASE("pick_weighted reproduces the golden picks and never picks a zero weight") {
	for (const golden::Pick &p : golden::PICKS) {
		Rng rng(p.seed);
		for (int64_t expected : p.picks) {
			const size_t got = *rng.pick_weighted(p.weights.data(), p.weights.size());
			CHECK(static_cast<int64_t>(got) == expected);
			CHECK(p.weights[got] > 0);
		}
	}
	Rng rng(3);
	const int64_t zeros[3] = {0, 0, 0};
	CHECK_FALSE(rng.pick_weighted(zeros, 3).has_value());
	const int64_t negative[2] = {5, -1};
	CHECK_FALSE(rng.pick_weighted(negative, 2).has_value());
	const int64_t too_big[2] = {int64_t{1} << 31, int64_t{1} << 31};
	CHECK_FALSE(rng.pick_weighted(too_big, 2).has_value());
	CHECK_FALSE(rng.pick_weighted(nullptr, 0).has_value());
}

TEST_CASE("shuffle reproduces the golden permutations") {
	for (const golden::Shuffle &s : golden::SHUFFLES) {
		Rng rng(s.seed);
		std::vector<int64_t> items(static_cast<size_t>(s.n));
		std::iota(items.begin(), items.end(), 0);
		rng.shuffle(items);
		CHECK(items == s.result);
	}
}

TEST_CASE("unit_double is the top 53 bits times 2^-53") {
	for (const golden::Unit &u : golden::UNITS) {
		Rng rng(u.seed);
		for (uint64_t raw : u.raw53) {
			const double got = rng.unit_double();
			CHECK(got == static_cast<double>(raw) * 0x1.0p-53);
			CHECK(got >= 0.0);
			CHECK(got < 1.0);
		}
	}
}

TEST_CASE("saving and restoring state continues the identical sequence") {
	Rng rng(77);
	for (int i = 0; i < 10; i++) {
		rng.next_u64();
	}
	const uint64_t saved = rng.state();
	std::vector<uint64_t> first;
	for (int i = 0; i < 20; i++) {
		first.push_back(rng.next_u64());
	}
	Rng restored(0);
	restored.set_state(saved);
	for (uint64_t expected : first) {
		CHECK(restored.next_u64() == expected);
	}
}

#ifdef LB_DEBUG_TOOLS
TEST_CASE("script_values returns the scripted draws, then resumes the stream") {
	Rng plain(5);
	const uint64_t a = plain.next_u64();
	Rng scripted(5);
	scripted.script_values({111, 222});
	CHECK(scripted.next_u64() == 111);
	CHECK(scripted.next_u64() == 222);
	CHECK(scripted.next_u64() == a);
}
#endif

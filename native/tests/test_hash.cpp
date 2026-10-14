#include "core/generated/hash_domains.h"
#include "core/rng/hash.h"
#include "golden/rng_golden.gen.h"

#include <doctest.h>

#include <algorithm>
#include <chrono>
#include <cstdio>
#include <vector>

using namespace lb::core;

namespace {

uint64_t hash_of(uint64_t seed, uint64_t domain, const std::vector<int64_t> &keys) {
	return hash_u64(seed, domain, keys.data(), keys.size());
}

int popcount64(uint64_t v) {
	int n = 0;
	for (; v != 0; v &= v - 1) {
		n++;
	}
	return n;
}

std::vector<int64_t> as_keys(const std::vector<uint64_t> &bits) {
	std::vector<int64_t> keys;
	for (uint64_t b : bits) {
		keys.push_back(static_cast<int64_t>(b));
	}
	return keys;
}

} // namespace

TEST_CASE("mix64 reproduces the golden values") {
	CHECK(golden::MIX.size() == 64);
	for (const golden::Mix &m : golden::MIX) {
		CHECK(mix64(m.in) == m.out);
	}
}

TEST_CASE("hash_u64 reproduces the golden tuples, negative keys included") {
	CHECK(golden::HASH.size() == 100);
	for (const golden::Hash &h : golden::HASH) {
		CHECK(hash_of(h.seed, h.domain, as_keys(h.keys)) == h.hash);
	}
}

TEST_CASE("sub_seed is hash_u64 with the attempt appended") {
	for (const golden::SubSeed &s : golden::SUB_SEED) {
		std::vector<int64_t> keys = as_keys(s.keys);
		CHECK(sub_seed(s.seed, s.domain, keys.data(), keys.size(), s.attempt) == s.value);
		keys.push_back(s.attempt);
		CHECK(hash_of(s.seed, s.domain, keys) == s.value);
	}
}

TEST_CASE("changing any single input changes the hash (avalanche spot checks)") {
	const std::vector<int64_t> keys = {3, -7, 11};
	const uint64_t base = hash_of(42, 5, keys);
	CHECK(hash_of(43, 5, keys) != base);
	CHECK(hash_of(42, 6, keys) != base);
	for (size_t i = 0; i < keys.size(); i++) {
		std::vector<int64_t> changed = keys;
		changed[i] ^= 1;
		CHECK(hash_of(42, 5, changed) != base);
	}
	CHECK(hash_of(42, 5, {3, -7}) != base);
	CHECK(hash_of(42, 5, {-7, 3, 11}) != base);
	// One flipped seed bit changes about half the output bits.
	int total_bits = 0;
	for (int bit = 0; bit < 64; bit++) {
		total_bits += popcount64(hash_of(42ULL ^ (1ULL << bit), 5, keys) ^ base);
	}
	const double mean = total_bits / 64.0;
	CHECK(mean > 28.0);
	CHECK(mean < 36.0);
}

TEST_CASE("domain IDs are unique and positive") {
	for (size_t i = 0; i < hash_domain::COUNT; i++) {
		CHECK(hash_domain::ALL[i].id > 0);
		for (size_t j = i + 1; j < hash_domain::COUNT; j++) {
			CHECK(hash_domain::ALL[i].id != hash_domain::ALL[j].id);
		}
	}
}

TEST_CASE("10^7 hash_u64 calls fit the 100 ms budget") {
	const int64_t keys[3] = {1, 2, 3};
	uint64_t sink = 0;
	// The best of three: a shared CI machine's stalls measure the machine, not the hash.
	double ms = 1e9;
	for (int trial = 0; trial < 3; trial++) {
		const auto start = std::chrono::steady_clock::now();
		for (uint64_t i = 0; i < 10000000ULL; i++) {
			sink ^= hash_u64(i, 4, keys, 3);
		}
		ms = std::min(ms, std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - start).count());
	}
	MESSAGE("10^7 hash_u64 calls: " << ms << " ms (sink " << sink << ")");
#ifndef LB_DEBUG_TOOLS
	CHECK(ms < 100.0);
#endif
}

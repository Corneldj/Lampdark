#pragma once
// LAMPBLACK's one hash (FND-06). Bit-identical on every platform: integer arithmetic only.
// Thread-safe: pure functions.
//
// Changing any algorithm or constant here changes every seed-derived mine, so it needs a
// new HASH_VERSION kept beside the old one (saves resume with the generator they began with).

#include <cstddef>
#include <cstdint>

namespace lb::core {

constexpr uint64_t HASH_VERSION = 1;
constexpr uint64_t GOLDEN_GAMMA = 0x9E3779B97F4A7C15ULL;

// SplitMix64 finaliser.
constexpr uint64_t mix64(uint64_t z) {
	z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
	z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
	return z ^ (z >> 31);
}

// Keyed hash: h = mix64(seed ^ mix64(domain + G)); then per key i,
// h = mix64(h ^ mix64(key_i + G * (i + 2))). Keys are int64 read as their bit pattern.
uint64_t hash_u64(uint64_t seed, uint64_t domain, const int64_t *keys, size_t key_count);

// hash_u64 with `attempt` appended as the last key. Attempt 0 is the first try; a validator
// reroll takes attempt 1, 2, ... (GEN-12).
uint64_t sub_seed(uint64_t seed, uint64_t domain, const int64_t *keys, size_t key_count, int64_t attempt);

} // namespace lb::core

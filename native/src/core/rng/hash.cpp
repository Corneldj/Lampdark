#include "core/rng/hash.h"

namespace lb::core {

uint64_t hash_u64(uint64_t seed, uint64_t domain, const int64_t *keys, size_t key_count) {
	uint64_t h = mix64(seed ^ mix64(domain + GOLDEN_GAMMA));
	for (size_t i = 0; i < key_count; i++) {
		const uint64_t key = static_cast<uint64_t>(keys[i]);
		h = mix64(h ^ mix64(key + GOLDEN_GAMMA * static_cast<uint64_t>(i + 2)));
	}
	return h;
}

uint64_t sub_seed(uint64_t seed, uint64_t domain, const int64_t *keys, size_t key_count, int64_t attempt) {
	uint64_t h = hash_u64(seed, domain, keys, key_count);
	const uint64_t key = static_cast<uint64_t>(attempt);
	return mix64(h ^ mix64(key + GOLDEN_GAMMA * static_cast<uint64_t>(key_count + 2)));
}

} // namespace lb::core

#pragma once
// LAMPBLACK's one random stream (FND-06): SplitMix64, state = one uint64.
// Not thread-safe: each system owns its own Rng (seeded from sub_seed of its domain).
// No floating point decides a draw except unit_double(), which is exact on every platform.

#include "core/rng/hash.h"

#include <cstdint>
#include <optional>
#include <utility>
#include <vector>

namespace lb::core {

class Rng {
public:
	explicit Rng(uint64_t seed = 0) : state_(seed) {}

	uint64_t next_u64();

	// Inclusive and unbiased (rejection sampling). The full int64 span returns the raw draw.
	// lo > hi gives std::nullopt.
	std::optional<int64_t> range(int64_t lo, int64_t hi);

	// True with probability ppm / 1,000,000.
	bool chance_ppm(int64_t ppm);

	// Index drawn by integer weight. Zero weights are never chosen. An empty list, a negative
	// weight, an all-zero list or a total of 2^32 or more gives std::nullopt.
	std::optional<size_t> pick_weighted(const int64_t *weights, size_t count);

	// Fisher-Yates from the last index, using range(0, i).
	template <typename T>
	void shuffle(std::vector<T> &items) {
		for (size_t i = items.size(); i > 1; i--) {
			const size_t last = i - 1;
			const size_t j = static_cast<size_t>(*range(0, static_cast<int64_t>(last)));
			std::swap(items[last], items[j]);
		}
	}

	// (next >> 11) × 2^-53, in [0, 1).
	double unit_double();

	uint64_t state() const { return state_; }
	void set_state(uint64_t state) { state_ = state; }

#ifdef LB_DEBUG_TOOLS
	// Test hook (QA-02, FND-09): the next draws return these raw values in order, then the
	// stream resumes. Debug builds only.
	void script_values(std::vector<uint64_t> values);
#endif

private:
	uint64_t state_;
#ifdef LB_DEBUG_TOOLS
	std::vector<uint64_t> scripted_;
	size_t scripted_next_ = 0;
#endif
};

} // namespace lb::core

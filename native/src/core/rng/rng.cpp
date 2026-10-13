#include "core/rng/rng.h"

namespace lb::core {

uint64_t Rng::next_u64() {
#ifdef LB_DEBUG_TOOLS
	if (scripted_next_ < scripted_.size()) {
		return scripted_[scripted_next_++];
	}
#endif
	state_ += GOLDEN_GAMMA;
	return mix64(state_);
}

std::optional<int64_t> Rng::range(int64_t lo, int64_t hi) {
	if (lo > hi) {
		return std::nullopt;
	}
	// n = hi - lo + 1 in unsigned arithmetic; 0 means the full 2^64 span.
	const uint64_t n = static_cast<uint64_t>(hi) - static_cast<uint64_t>(lo) + 1;
	if (n == 0) {
		return static_cast<int64_t>(next_u64());
	}
	// limit = 2^64 - (2^64 mod n); (0 - n) % n is 2^64 mod n.
	const uint64_t remainder = (0 - n) % n;
	uint64_t x = next_u64();
	if (remainder != 0) {
		const uint64_t limit = 0 - remainder;
		while (x >= limit) {
			x = next_u64();
		}
	}
	return static_cast<int64_t>(static_cast<uint64_t>(lo) + x % n);
}

bool Rng::chance_ppm(int64_t ppm) {
	return *range(0, 999999) < ppm;
}

std::optional<size_t> Rng::pick_weighted(const int64_t *weights, size_t count) {
	uint64_t total = 0;
	for (size_t i = 0; i < count; i++) {
		if (weights[i] < 0) {
			return std::nullopt;
		}
		total += static_cast<uint64_t>(weights[i]);
		if (total >= (uint64_t{1} << 32)) {
			return std::nullopt;
		}
	}
	if (total == 0) {
		return std::nullopt;
	}
	const int64_t r = *range(0, static_cast<int64_t>(total) - 1);
	int64_t acc = 0;
	for (size_t i = 0; i < count; i++) {
		acc += weights[i];
		if (r < acc) {
			return i;
		}
	}
	return std::nullopt; // unreachable
}

double Rng::unit_double() {
	return static_cast<double>(next_u64() >> 11) * 0x1.0p-53;
}

#ifdef LB_DEBUG_TOOLS
void Rng::script_values(std::vector<uint64_t> values) {
	scripted_ = std::move(values);
	scripted_next_ = 0;
}
#endif

} // namespace lb::core

#include "godot/rng/lb_rng.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

namespace lb::godot {

void LbRng::_bind_methods() {
	ClassDB::bind_static_method("LbRng", D_METHOD("from_seed", "seed"), &LbRng::from_seed);
	ClassDB::bind_method(D_METHOD("next_u64"), &LbRng::next_u64);
	ClassDB::bind_method(D_METHOD("range", "lo", "hi"), &LbRng::range);
	ClassDB::bind_method(D_METHOD("chance_ppm", "ppm"), &LbRng::chance_ppm);
	ClassDB::bind_method(D_METHOD("pick_weighted", "weights"), &LbRng::pick_weighted);
	ClassDB::bind_method(D_METHOD("shuffle", "items"), &LbRng::shuffle);
	ClassDB::bind_method(D_METHOD("unit_double"), &LbRng::unit_double);
	ClassDB::bind_method(D_METHOD("get_state"), &LbRng::get_state);
	ClassDB::bind_method(D_METHOD("set_state", "state"), &LbRng::set_state);
#ifdef LB_DEBUG_TOOLS
	ClassDB::bind_method(D_METHOD("script_values", "values"), &LbRng::script_values);
#endif
}

Ref<LbRng> LbRng::from_seed(int64_t seed) {
	Ref<LbRng> rng;
	rng.instantiate();
	rng->rng_.set_state(static_cast<uint64_t>(seed));
	return rng;
}

int64_t LbRng::next_u64() {
	return static_cast<int64_t>(rng_.next_u64());
}

int64_t LbRng::range(int64_t lo, int64_t hi) {
	std::optional<int64_t> value = rng_.range(lo, hi);
	if (!value) {
		UtilityFunctions::push_error("LbRng.range: lo ", lo, " is above hi ", hi);
		return lo;
	}
	return *value;
}

bool LbRng::chance_ppm(int64_t ppm) {
	return rng_.chance_ppm(ppm);
}

int64_t LbRng::pick_weighted(const PackedInt64Array &weights) {
	std::optional<size_t> index = rng_.pick_weighted(weights.ptr(), static_cast<size_t>(weights.size()));
	if (!index) {
		UtilityFunctions::push_error("LbRng.pick_weighted: weights must be non-negative, not all zero, totalling under 2^32");
		return -1;
	}
	return static_cast<int64_t>(*index);
}

void LbRng::shuffle(Array items) {
	for (int64_t i = items.size() - 1; i > 0; i--) {
		const int64_t j = *rng_.range(0, i);
		const Variant held = items[i];
		items[i] = items[j];
		items[j] = held;
	}
}

double LbRng::unit_double() {
	return rng_.unit_double();
}

int64_t LbRng::get_state() const {
	return static_cast<int64_t>(rng_.state());
}

void LbRng::set_state(int64_t state) {
	rng_.set_state(static_cast<uint64_t>(state));
}

#ifdef LB_DEBUG_TOOLS
void LbRng::script_values(const PackedInt64Array &values) {
	std::vector<uint64_t> raw;
	for (int64_t i = 0; i < values.size(); i++) {
		raw.push_back(static_cast<uint64_t>(values[i]));
	}
	rng_.script_values(std::move(raw));
}
#endif

} // namespace lb::godot

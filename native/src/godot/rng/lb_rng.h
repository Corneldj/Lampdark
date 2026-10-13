#pragma once
// GDScript face of core/rng/rng.h (FND-06). Build one with LbRng.from_seed(seed); GDExtension
// classes take no constructor arguments.

#include "core/rng/rng.h"

#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>

namespace lb::godot {

class LbRng : public ::godot::RefCounted {
	GDCLASS(LbRng, ::godot::RefCounted)

protected:
	static void _bind_methods();

public:
	static ::godot::Ref<LbRng> from_seed(int64_t seed);

	int64_t next_u64();
	// Inclusive; lo > hi reports an error and returns lo.
	int64_t range(int64_t lo, int64_t hi);
	bool chance_ppm(int64_t ppm);
	// Index by integer weight; an all-zero, negative or oversized list reports an error and returns -1.
	int64_t pick_weighted(const ::godot::PackedInt64Array &weights);
	// Shuffles the array in place (Fisher-Yates from the last index).
	void shuffle(::godot::Array items);
	double unit_double();
	int64_t get_state() const;
	void set_state(int64_t state);
#ifdef LB_DEBUG_TOOLS
	void script_values(const ::godot::PackedInt64Array &values);
#endif

private:
	lb::core::Rng rng_;
};

} // namespace lb::godot

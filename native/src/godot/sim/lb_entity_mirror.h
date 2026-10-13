#pragma once
// GDScript face of core/sim/entity_mirror.h (NET-01).

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>

namespace lb::godot {

class LbEntityMirror : public ::godot::RefCounted {
	GDCLASS(LbEntityMirror, ::godot::RefCounted)

protected:
	static void _bind_methods();

public:
	// Parallel arrays in ascending ID order; xy holds x0, y0, x1, y1, ...
	static bool set_packed(int64_t tick, const ::godot::PackedInt64Array &ids, const ::godot::PackedInt32Array &kinds,
			const ::godot::PackedFloat64Array &xy, const ::godot::PackedInt32Array &flags);
	static int64_t count();
	static int64_t mirrored_tick();
	// {id, kind, x, y, flags}, or an empty Dictionary for an unknown ID.
	static ::godot::Dictionary find(int64_t id);
};

} // namespace lb::godot

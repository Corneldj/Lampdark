#pragma once
// GDScript face of the core's deterministic trig (core/vision/det_trig.h): unit vectors that
// are bit-identical on every platform, for MNR-01's shared movement step (server and NET-05's
// prediction) instead of GDScript's libm sin and cos.

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>

namespace lb::godot {

class LbDetMath : public ::godot::Object {
	GDCLASS(LbDetMath, ::godot::Object)

protected:
	static void _bind_methods();

public:
	// [x, y] of the unit vector at an angle in turns (0 is +x, a quarter turn +y).
	static ::godot::PackedFloat64Array unit(double turns);
	static double cos_deg(double degrees);
};

} // namespace lb::godot

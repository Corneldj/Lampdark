#pragma once
// SND-08: the voice loss model for GDScript: the distance rule, combining, and recorded lines' masks
// (SND-11's callouts, CRT-10's illusions) from the same process a live utterance gets.

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>

namespace lb::godot {

class LbVoiceLoss : public ::godot::RefCounted {
	GDCLASS(LbVoiceLoss, ::godot::RefCounted)

public:
	static double distance_loss(double d, double range, double clean_fraction, double edge_loss);
	static double distance_muffle(double d, double range, double clean_fraction);
	static double combine(const ::godot::PackedFloat64Array &rates);
	// 1 kept, 0 dropped, per frame.
	static ::godot::PackedByteArray mask_for(int64_t run_seed, int64_t utterance, int64_t listener, int64_t frames, double p,
			int64_t run_min, int64_t run_max);

protected:
	static void _bind_methods();
};

} // namespace lb::godot

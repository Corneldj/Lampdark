#pragma once
// GDScript face of core/audio's mixer (SND-04): the client's one native mixer. Client-only.

#include "core/audio/mixer.h"
#include "core/audio/phonon_hrtf.h"

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>

#include <memory>

namespace lb::godot {

class LbAudioMixer : public ::godot::RefCounted {
	GDCLASS(LbAudioMixer, ::godot::RefCounted)

protected:
	static void _bind_methods();

public:
	void setup(double sample_rate, int64_t hrtf_frame = 512, bool hrtf_bilinear = false);
	void set_pose(double x, double y, int64_t facing_u16);
	void set_mode(int64_t mode);
	int64_t get_mode() const;
	void set_rear(double start_deg, double min_hz);
	int64_t add(const ::godot::PackedFloat32Array &samples, double rate, double x, double y, double gain_db, int64_t group,
			bool positional, bool loop);
	bool remove(int64_t id);
	// SND-07: a voice stream (starts empty), its samples as they decode, its gain, and its end.
	int64_t open_stream(double rate, double x, double y, double gain_db, int64_t group, bool positional);
	bool append(int64_t id, const ::godot::PackedFloat32Array &samples);
	void set_gain(int64_t id, double gain_db);
	void close_stream(int64_t id);
	int64_t queued(int64_t id) const;
	bool has(int64_t id) const;
	void move(int64_t id, double x, double y);
	int64_t count() const;
	::godot::PackedVector2Array mix(int64_t group, int64_t frames);
	double azimuth_of(int64_t id) const;
	double rear_cutoff_of(int64_t id) const;
#ifdef LB_DEBUG_TOOLS
	void set_screen_up(bool on);
#endif
	bool is_screen_up() const;
	// SND-04: the headphone HRTF. setup() loads Steam Audio from beside the core library; without it
	// the spherical-head model renders headphones. use_hrtf(false) switches to that model (tests, A/B).
	bool has_hrtf() const;
	::godot::String hrtf_name() const;
	::godot::String hrtf_error() const;
	void use_hrtf(bool on);

private:
	std::unique_ptr<lb::core::audio::Mixer> mixer_ = std::make_unique<lb::core::audio::Mixer>();
	std::shared_ptr<lb::core::audio::Hrtf> hrtf_;
	std::string hrtf_error_;
};

} // namespace lb::godot

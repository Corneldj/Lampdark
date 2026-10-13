#pragma once
// SND-05: the microphone for GDScript (client/audio/voice_capture.gd decides when it may open).
// Opens the default or a named input, cleans it (echo cancelling against the game's final mix,
// which the client feeds in, then noise suppression) and hands out 20 ms frames of 48 kHz mono,
// stamped on Godot's Time clock. Debug builds add a fake device for tests.

#include "core/voice/mic_capture.h"

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/string.hpp>

#include <atomic>
#include <memory>

namespace lb::godot {

class LbVoiceCapture : public ::godot::RefCounted {
	GDCLASS(LbVoiceCapture, ::godot::RefCounted)

public:
	LbVoiceCapture();
	// "device" (the default: real devices), "null" (miniaudio's null device), or, in debug builds,
	// "fake" (devices added and fed by hand). Closes whatever was open.
	bool use_driver(const ::godot::String &kind);
	// voice.apm_backend, voice.noise_suppression_level, voice.speex_echo_tail_ms and
	// voice.speex_noise_suppress_db (four levels). False on an unknown name or a backend that
	// cannot start.
	bool configure(const ::godot::String &backend, const ::godot::String &noise, double speex_tail_ms,
			const ::godot::PackedFloat32Array &speex_suppress_db);
	// [{id, name, is_default}].
	::godot::Array devices();
	bool open(const ::godot::String &id);
	void close();
	bool is_open() const;
	bool is_lost() const;
	::godot::String device_id() const;
	int64_t open_count() const;
	// Every successful open by any instance in this process (the Mute never-opens check).
	static int64_t total_open_count();
	// The game's final mix: stereo frames at `mix_rate`.
	void push_far_end(const ::godot::PackedVector2Array &frames, int64_t mix_rate);
	// [[PackedFloat32Array pcm (960), int ticks_usec], ...], oldest first.
	::godot::Array pop_frames();
	// {device_latency_ms, processing_us_p95, dropped_frames, dropped_far_end}.
	::godot::Dictionary stats() const;
	// Debug builds only (tests): the fake driver's controls.
	void fake_add_device(const ::godot::String &id, const ::godot::String &name, bool is_default);
	void fake_remove_device(const ::godot::String &id);
	bool fake_feed(const ::godot::PackedFloat32Array &samples);

protected:
	static void _bind_methods();

private:
	lb::core::voice::MicCapture &mic();
	const lb::core::voice::MicCapture *mic_if_made() const;

	::godot::String kind_ = "device";
	std::unique_ptr<lb::core::voice::MicCapture> mic_;
	lb::core::voice::FakeCaptureDriver *fake_ = nullptr;
	lb::core::voice::ProcessorParams params_;
	static std::atomic<int64_t> total_opens_;
};

} // namespace lb::godot

#pragma once
// SND-07: one incoming voice stream for GDScript (client/audio/voice_playback.gd).

#include "core/voice/voice_playout.h"

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>

#include <memory>

namespace lb::godot {

class LbVoicePlayout : public ::godot::RefCounted {
	GDCLASS(LbVoicePlayout, ::godot::RefCounted)

public:
	// params: {start_ms, min_ms, max_ms, frame_ms, speech_low_hz, speech_high_hz,
	//          cap_dbfs (PackedFloat32Array of 4: whisper..scream), smear_dbfs, hiss_dbfs}
	void configure(const ::godot::Dictionary &params);
	bool push(const ::godot::PackedByteArray &packet, int64_t now_usec);
	// [{kind ("frame", "conceal", "smear", "end"), pcm, band, probe_t0_usec, cap_db}, ...]
	::godot::Array pop(int64_t now_usec);
	bool done() const;
	double jitter_ms() const;
	int64_t target_ms() const;
	// {gain_db, muffled, telephone, dry, crackle, position (Vector2 tiles)}
	::godot::Dictionary header() const;
	// The target a new stream should start from, given the jitter measured so far.
	static int64_t suggest_ms(double jitter_ms, int64_t min_ms, int64_t max_ms, int64_t frame_ms);
	// Wire helpers for the stream id of a downstream packet (0 when too short).
	static int64_t stream_of(const ::godot::PackedByteArray &packet);

protected:
	static void _bind_methods();

private:
	std::unique_ptr<lb::core::voice::VoicePlayout> p_;
};

} // namespace lb::godot

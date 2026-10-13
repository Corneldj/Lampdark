#pragma once
// SND-07 and SND-13: Opus for GDScript. LbOpusEncoder turns 20 ms of 48 kHz mono into a packet;
// LbOpusDecoder turns a packet (or a lost one) back, and decodes a whole .lbv character line.

#include "core/voice/opus_codec.h"

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>

#include <memory>

namespace lb::godot {

class LbOpusEncoder : public ::godot::RefCounted {
	GDCLASS(LbOpusEncoder, ::godot::RefCounted)

public:
	void setup(int64_t bitrate, bool voip);
	::godot::PackedByteArray encode(const ::godot::PackedFloat32Array &pcm);

protected:
	static void _bind_methods();

private:
	std::unique_ptr<lb::core::voice::OpusVoiceEncoder> enc_;
};

class LbOpusDecoder : public ::godot::RefCounted {
	GDCLASS(LbOpusDecoder, ::godot::RefCounted)

public:
	LbOpusDecoder();
	::godot::PackedFloat32Array decode(const ::godot::PackedByteArray &packet);
	::godot::PackedFloat32Array conceal();
	void reset();
	// A whole .lbv file (SND-13): the line's samples at 48 kHz, its pre-skip dropped and its tail
	// trimmed to the recorded length; empty if malformed.
	::godot::PackedFloat32Array decode_lbv(const ::godot::PackedByteArray &file);
	static ::godot::String version();

protected:
	static void _bind_methods();

private:
	std::unique_ptr<lb::core::voice::OpusVoiceDecoder> dec_;
};

} // namespace lb::godot

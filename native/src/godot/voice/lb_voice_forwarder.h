#pragma once
// SND-07: the server's voice forwarder for GDScript (server/systems/sound/voice_system.gd). It
// rewrites and fans out packets; it holds routes, never frames, and links no Opus code.

#include "core/voice/voice_forwarder.h"

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>

namespace lb::godot {

class LbVoiceForwarder : public ::godot::RefCounted {
	GDCLASS(LbVoiceForwarder, ::godot::RefCounted)

public:
	// {valid, seq, band, end, probe} of an upstream packet.
	static ::godot::Dictionary parse(const ::godot::PackedByteArray &packet);
	// routes: [{listener, stream, gain_db, flags, crackle, x, y (tiles)}]
	void set_routes(int64_t speaker, const ::godot::Array &routes);
	void clear(int64_t speaker);
	int64_t route_count(int64_t speaker) const;
	// [[listener, PackedByteArray], ...]; empty when invalid or routeless.
	::godot::Array forward(int64_t speaker, const ::godot::PackedByteArray &packet) const;

protected:
	static void _bind_methods();

private:
	lb::core::voice::VoiceForwarder fwd_;
};

} // namespace lb::godot

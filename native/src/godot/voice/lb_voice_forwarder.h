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
	// SND-08: the run seed loss processes are keyed from, and the drop runs' lengths.
	void set_loss(int64_t run_seed, int64_t run_min, int64_t run_max);
	// routes: [{listener, stream, gain_db, flags, crackle (bool), muffle (0-1), loss (0-1), x, y (tiles)}]
	// for utterance `utterance` (a new one restarts the loss processes).
	void set_routes(int64_t speaker, const ::godot::Array &routes, int64_t utterance);
	// This utterance's counts: {listener: {seen, sent}} (SND-08's QA logs).
	::godot::Dictionary counts(int64_t speaker) const;
	void clear(int64_t speaker);
	int64_t route_count(int64_t speaker) const;
	// [[listener, PackedByteArray], ...]; empty when invalid or routeless.
	::godot::Array forward(int64_t speaker, const ::godot::PackedByteArray &packet);

protected:
	static void _bind_methods();

private:
	lb::core::voice::VoiceForwarder fwd_;
};

} // namespace lb::godot

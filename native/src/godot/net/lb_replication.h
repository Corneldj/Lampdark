#pragma once
// GDScript face of core/net (NET-04): one ClientView per client, fed from VIS-03's last frame
// for that client's miner, GEN-01's geometry and NET-01's entity mirror. Server-only.

#include "core/net/client_view.h"
#include "godot/vision/lb_vision.h"
#include "godot/world/lb_mine.h"

#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>

#include <map>
#include <memory>
#include <set>

namespace lb::godot {

class LbReplication : public ::godot::RefCounted {
	GDCLASS(LbReplication, ::godot::RefCounted)

protected:
	static void _bind_methods();

public:
	void attach(const ::godot::Ref<LbVision> &vision, const ::godot::Ref<LbMine> &mine);
	// Keys: budget_kbps, burst_bytes, max_frame_bytes, history, token_cooldown, age_gain, held_cells,
	// full_frames (the debug switch: every frame a full resync).
	void set_params(const ::godot::Dictionary &params);
	void add_client(int64_t slot, int64_t secret);
	void remove_client(int64_t slot);
	void reset_client(int64_t slot);
	bool has_client(int64_t slot) const;
	// The client-facing kind (SeenKind) an entity kind is identified as.
	void set_seen_kind(int64_t entity_kind, int64_t seen_kind);
	void set_entity_facing(int64_t entity, int64_t facing);
	void clear_entity_facing(int64_t entity);
	// MNR-03's body cues for an entity (MinerCues bits), sent only on its identity records.
	void set_entity_cues(int64_t entity, int64_t cues);
	// MNR-04: what an entity holds in its hands (InventorySystem.held_bits), identity records only.
	void set_entity_held(int64_t entity, int64_t bits);
	// MNR-13: an entity riding on another (a body over a carrier's shoulder) is never sent as its own
	// token; the carrier's identity record shows it through its in-hand bits.
	void set_entity_attached(int64_t entity, bool attached);
	// VIS-08: the flame states shown on an entity's identity record (its lamp hand's flame, or the
	// flame it is); 0 clears.
	void set_entity_flame(int64_t entity, int64_t bits);
	void on_ack(int64_t slot, int64_t now, int64_t ack16, int64_t bits);
	// {type, start_tick, apparent (Vector2, tiles), remaining_np, duration_s, voice (-1 none)}
	void queue_event(int64_t slot, const ::godot::Dictionary &event);
	// observer: the slot's VIS-03 observer (-1: no miner, an empty view); own: {x, y, facing,
	// gait, speed_q, flags}.
	::godot::PackedByteArray build(int64_t slot, int64_t observer, int64_t tick, const ::godot::Dictionary &own, int64_t action_ack, int64_t input_depth, int64_t input_ack = 0xFFFF);
	::godot::Dictionary last_stats(int64_t slot) const;
	int64_t token_of(int64_t slot, int64_t entity) const;
	// LFT-14: the slot's budget left after this tick's frame, in whole bytes (0 for an unknown
	// slot or before its first frame); the sheets spend from it what they send.
	int64_t bucket_bytes(int64_t slot) const;
	void spend(int64_t slot, int64_t bytes);
	::godot::Array last_numbered(int64_t slot) const;
	// NET-07: the view frame `tick` leaves the client holding, in ReceivedView.to_dict()'s shape,
	// while that frame is in the history ({} after). The client's decoder gives the same view.
	::godot::Dictionary sent_view(int64_t slot, int64_t tick) const;

private:
	::godot::Ref<LbVision> vision_;
	::godot::Ref<LbMine> mine_;
	lb::core::net::ReplicationParams params_;
	std::map<int64_t, std::unique_ptr<lb::core::net::ClientView>> clients_;
	std::map<int64_t, lb::core::net::BuildStats> stats_;
	std::map<uint16_t, uint8_t> seen_kind_;
	std::map<uint32_t, uint16_t> facing_;
	std::map<uint32_t, uint16_t> cues_;
	std::map<uint32_t, uint16_t> in_hand_;
	std::set<uint32_t> attached_;
	std::map<uint32_t, uint8_t> flame_;
};

// Frame decoding for the stream tap and tests: the records one frame carries, without a
// baseline (NET-07, NET-08).
class LbFrameCodec : public ::godot::RefCounted {
	GDCLASS(LbFrameCodec, ::godot::RefCounted)

protected:
	static void _bind_methods();

public:
	static ::godot::Dictionary decode_records(const ::godot::PackedByteArray &bytes);
};

} // namespace lb::godot

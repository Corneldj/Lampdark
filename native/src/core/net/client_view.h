#pragma once
// NET-04's per-client replication (the Quake 3 model). For each client the server keeps the
// view it sent in each recent frame; a frame encodes what the client should now hold against
// the newest frame the client acknowledged, so anything a lost or over-budget frame left out is
// still different, and is sent again, until acknowledged. With no usable acknowledgement a frame
// goes against an empty view: a full resync. The same rules decode on the client.
//
// Records: the own block; tile light, colour and decals (seen tiles only); tile geometry (seen
// tiles, and held for cells within the held radius of the own miner); entities by per-client
// token (identity: kind and facing; fringe: size class only); the edge glow; and audio events,
// which wait in a reliable queue until a frame carrying them is acknowledged. Positions are
// relative to the own miner, never absolute, except the own block. Engine-free.

#include "core/vision/seen_set.h"
#include "core/world/coords.h"

#include <array>
#include <cstdint>
#include <map>
#include <optional>
#include <set>
#include <vector>

namespace lb::core::net {

using world::Coord;

constexpr uint32_t FRAME_VERSION = 4; // 2: VIS-08 flame-state bytes; 3: SND-03 audio record fields; 4: VIS-09 dust flag, shading bits
constexpr uint8_t FLAG_FULL = 1;
constexpr uint8_t FLAG_BLINDED = 2;
constexpr uint8_t FLAG_DUST = 4;  // VIS-09: the Moth's dust settles on every lit tile this client sees
constexpr size_t GLOW_BUCKETS = 32;

struct TileView {
	uint8_t light = 0, colour = 0, decals = 0;
	bool operator==(const TileView &o) const { return light == o.light && colour == o.colour && decals == o.decals; }
	bool operator!=(const TileView &o) const { return !(*this == o); }
};

struct GeoView {
	uint8_t material = 0, state = 0;
	bool operator==(const GeoView &o) const { return material == o.material && state == o.state; }
	bool operator!=(const GeoView &o) const { return !(*this == o); }
};

// level 1: a fringe token (size class only); level 2: identity (kind, facing, body cues and what
// is in its hands);
// level 3: a hidden margin token (VIS-04: size class only, drawn only once the client's predicted
// light reaches it).
struct EntityView {
	uint8_t level = 0;
	uint8_t size_or_kind = 0;
	int64_t x64 = 0, y64 = 0; // absolute, 1/64 tile (relative on the wire)
	uint16_t facing = 0;
	uint16_t cues = 0;        // MNR-03's body cues, identity only
	uint16_t in_hand = 0;      // MNR-04: what is in its hands (lamp kind low byte, free hand high), identity only
	uint8_t flame = 0;         // VIS-08: the flame states of the flame it carries or is, identity only
	bool operator==(const EntityView &o) const {
		return level == o.level && size_or_kind == o.size_or_kind && x64 == o.x64 && y64 == o.y64 && facing == o.facing &&
			   cues == o.cues && in_hand == o.in_hand && flame == o.flame;
	}
	bool operator!=(const EntityView &o) const { return !(*this == o); }
};

struct OwnBlock {
	int32_t x256 = 0, y256 = 0; // absolute, 1/256 tile
	uint16_t facing = 0;
	uint8_t gait = 0;
	uint8_t speed_q = 100; // the gait constraints' product x 100
	uint16_t flags = 0;    // life state and capabilities (MNR-03)
	uint8_t stamina_q = 120; // the owner's stamina in 0.05 s steps (MNR-02), for NET-05 only
	uint8_t lamp_radius_q = 0; // the own light's radius after guttering and blackdamp, 1/16 tile (VIS-04)
	uint8_t flame = 0;         // VIS-08: the own flame's states (a shuttered or slotted lamp: guttering only)
	Coord tile() const { return Coord{world::floor_div(x256, 256), world::floor_div(y256, 256)}; }
	bool operator==(const OwnBlock &o) const {
		return x256 == o.x256 && y256 == o.y256 && facing == o.facing && gait == o.gait && speed_q == o.speed_q && flags == o.flags &&
			   stamina_q == o.stamina_q && lamp_radius_q == o.lamp_radius_q && flame == o.flame;
	}
};

struct ViewState {
	std::map<Coord, TileView> tiles;
	std::map<Coord, GeoView> geometry;
	std::map<uint16_t, EntityView> entities; // by token
	uint32_t glow_mask = 0;
	std::array<uint8_t, GLOW_BUCKETS> glow_colour{};
	OwnBlock own;
	bool blinded = false;
	bool dust = false;
};

// An audio event for one client (a Road Graph delivery or an illusion: the same fields).
// SND-03's audio record flags.
namespace audio_flag {
constexpr uint8_t MUFFLED = 1; // a closed portal on the path (a low-pass on the client)
constexpr uint8_t DIFFUSE = 2; // a diffuse tell: play from the points, caption without direction
constexpr uint8_t LOCAL = 4;   // a local emitter outside the Road Graph (the firedamp hiss)
} // namespace audio_flag
constexpr size_t MAX_EVENT_POINTS = 6;

struct EventIn {
	uint8_t type = 0;
	uint32_t start_tick = 0;
	double ax = 0.0, ay = 0.0; // apparent position, absolute tiles
	double remaining_np = 0.0;
	double level_np = 0.0;      // the event's level at its source (the client's gain)
	double duration_s = 0.5;
	int32_t voice = -1;
	uint8_t flags = 0;          // audio_flag bits
	int32_t gain_db = 0;        // set by SND-03's masks
	std::vector<std::pair<double, double>> points; // diffuse or multi-point emitters, absolute tiles
};

struct EventRec {
	uint16_t number = 0;
	uint8_t type = 0;
	uint32_t start_tick = 0;
	int64_t ax16 = 0, ay16 = 0; // absolute, 1/16 tile
	uint8_t remaining_q4 = 0;
	uint8_t level_q4 = 0;
	uint8_t duration_ds = 0;
	int32_t voice = -1;
	uint8_t flags = 0;
	int8_t gain_db = 0;
	std::vector<std::pair<int64_t, int64_t>> points; // absolute, 1/16 tile
	bool operator==(const EventRec &o) const {
		return number == o.number && type == o.type && start_tick == o.start_tick && ax16 == o.ax16 && ay16 == o.ay16 &&
			   remaining_q4 == o.remaining_q4 && level_q4 == o.level_q4 && duration_ds == o.duration_ds && voice == o.voice &&
			   flags == o.flags && gain_db == o.gain_db && points == o.points;
	}
};

struct ReplicationParams {
	int64_t budget_bytes_per_tick = 400; // net.down_budget_kbps at 20 Hz
	int64_t burst_bytes = 2400;
	int64_t max_frame_bytes = 1200;
	int64_t history = 32;
	int64_t token_cooldown = 64;
	double age_gain = 1.0;
	int64_t held_cells = 2;
	// Debug switch (M1 staging): every frame against an empty view, ignoring acknowledgements.
	bool full_frames = false;
	// NET-12's planted fault (tests only): a margin token is sent only once it has been in the
	// margin this many ticks. 0: at once.
	int64_t margin_delay_ticks = 0;
};

// What a client should hold this tick, before the budget.
struct Desired {
	vision::PerceptionFrame frame;              // VIS-03's frame (tokens carry their entity)
	std::map<uint32_t, uint8_t> identified_kind; // entity -> client-facing kind
	std::map<uint32_t, uint16_t> facing;        // entity -> facing
	std::map<uint32_t, uint16_t> cues;          // entity -> body cues (identity only)
	std::map<uint32_t, uint16_t> in_hand;       // entity -> items in hand (identity only, MNR-04)
	std::map<uint32_t, uint8_t> flame;          // entity -> flame states (identity only, VIS-08)
	std::map<uint32_t, std::pair<double, double>> position; // entity -> position
	OwnBlock own;
	std::map<Coord, GeoView> geometry_now;      // current geometry of every seen and margin tile
	bool dust = false;                          // VIS-09's per-viewer dust flag
};

struct BuildStats {
	size_t bytes = 0;
	bool full = false;
	size_t tiles_sent = 0, tiles_pending = 0;
	size_t geometry_sent = 0, geometry_pending = 0;
	size_t entities_sent = 0, entities_pending = 0;
	size_t events_sent = 0, events_pending = 0;
};

// The result of decoding one frame against a baseline.
struct Decoded {
	bool ok = false;
	uint32_t tick = 0;
	uint32_t baseline_tick = 0;
	bool full = false;
	uint16_t action_ack = 0xFFFF;
	uint16_t input_ack = 0xFFFF;
	uint8_t input_depth = 0;
	ViewState view;
	std::vector<EventRec> events;
};

class ClientView {
public:
	ClientView(uint64_t secret, uint32_t slot);

	// Forget everything the client holds (a rejoin, NET-11): the next frame is a full resync
	// and every entity gets a fresh token.
	void reset();

	// NET-03's acknowledgement riding on an input packet: the newest frame tick (u16 of it) and
	// a bitmask of the 32 before it. `now` resolves the u16 to a full tick.
	void on_ack(uint32_t now, uint32_t ack16, uint32_t bits);

	// Events for this tick, real and illusory alike; numbered in a canonical order at build().
	void queue_event(const EventIn &e);

	// input_ack: the seq of the input the server applied for this client this tick (NET-05
	// reconciles against it), 0xFFFF before the first.
	std::vector<uint8_t> build(uint32_t tick, const Desired &desired, uint16_t action_ack, uint8_t input_depth,
			const ReplicationParams &p, BuildStats *stats = nullptr, uint16_t input_ack = 0xFFFF);

	// The newest acknowledged frame tick, if any.
	std::optional<uint32_t> baseline() const { return newest_acked_; }
	// The view a frame still in the history leaves the client holding once decoded (NET-07's
	// keyframes), or null.
	const ViewState *sent_view(uint32_t tick) const {
		auto it = history_.find(tick);
		return it == history_.end() ? nullptr : &it->second;
	}
	size_t pending_events() const { return events_.size(); }
	// The token an entity holds for this client now, or 0.
	uint16_t token_of(uint32_t entity) const;
	// The events numbered at the last build, with their numbers (FND-08's overlay tags name an
	// illusion by its number; nothing here is sent).
	const std::vector<EventRec> &last_numbered() const { return last_numbered_; }

private:
	uint64_t secret_;
	uint32_t slot_;
	uint64_t token_state_ = 0;
	std::map<uint32_t, ViewState> history_;      // frame tick -> the view it sent
	std::map<uint32_t, std::set<uint16_t>> frame_events_; // frame tick -> event numbers in it
	std::optional<uint32_t> newest_acked_;
	std::map<uint32_t, uint16_t> tokens_;        // entity -> token
	std::map<uint16_t, uint32_t> cooling_;       // retired token -> tick retired
	std::vector<EventIn> incoming_;
	std::vector<EventRec> events_;               // numbered, unacknowledged
	std::vector<EventRec> last_numbered_;        // numbered at the last build
	uint16_t next_event_ = 1;
	std::map<std::pair<int, Coord>, uint32_t> pending_since_; // (kind, key) -> tick first pending
	std::map<uint32_t, uint32_t> margin_since_;  // entity -> tick it entered the margin (the planted delay)
	double bucket_ = -1.0;

	uint16_t new_token(uint32_t tick, int64_t cooldown);
	void number_incoming();
};

// Decodes a frame (the payload after Protocol's framing) against the client's history of
// decoded views. Returns ok false on a malformed frame or a missing baseline.
Decoded decode_frame(const std::vector<uint8_t> &bytes, const std::map<uint32_t, ViewState> &history, int64_t held_cells);

// The held-geometry rule both sides apply: keep geometry only for cells within `held_cells`
// (Chebyshev) of the own miner's cell.
void apply_held_rule(ViewState &view, int64_t held_cells);

} // namespace lb::core::net

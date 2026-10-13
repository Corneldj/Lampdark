#include "core/net/client_view.h"

#include "core/generated/hash_domains.h"
#include "core/net/byte_io.h"
#include "core/rng/hash.h"
#include "core/rng/rng.h"

#include <algorithm>

namespace lb::core::net {

namespace {

int64_t round_to(double v) {
	return static_cast<int64_t>(v >= 0.0 ? v + 0.5 : v - 0.5);
}

int32_t clamp_i(int64_t v, int64_t lo, int64_t hi) {
	return static_cast<int32_t>(v < lo ? lo : (v > hi ? hi : v));
}

Coord held_cell_of(Coord t) {
	return Coord{world::floor_div(t.x, world::CELL_TILES), world::floor_div(t.y, world::CELL_TILES)};
}

uint32_t popcount32(uint32_t v) {
	uint32_t n = 0;
	while (v != 0) {
		v &= v - 1;
		n++;
	}
	return n;
}

// Section sizes (bytes) on the wire.
constexpr size_t HEADER_BYTES = 1 + 4 + 2 + 2 + 2 + 1 + 1;
// x, y, facing, gait, speed_q, flags, stamina_q, lamp_radius_q, flame (VIS-08).
constexpr size_t OWN_BYTES = 4 + 4 + 2 + 1 + 1 + 2 + 1 + 1 + 1;
constexpr size_t COUNT_BYTES = 2 + 2 + 2 + 2 + 2 + 1 + 1;
constexpr size_t TILE_BYTES = 5, TILE_REMOVE_BYTES = 2, GEO_BYTES = 4;
// A token: token, level, size, dx, dy. An identity adds facing, cues, in hand (MNR-04) and flame
// (VIS-08); the budget must count every byte the encoder writes, or a full frame overruns.
constexpr size_t TOKEN_BYTES = 2 + 1 + 1 + 2 + 2, IDENTITY_BYTES = TOKEN_BYTES + 2 + 2 + 2 + 1, ENTITY_REMOVE_BYTES = 2;

// number, type, start tick, dx, dy, remaining, level, duration, flags, [voice], gain, point count,
// then dx, dy per point (from the apparent position).
size_t event_bytes(const EventRec &e) {
	return 2 + 1 + 4 + 2 + 2 + 1 + 1 + 1 + 1 + (e.voice >= 0 ? 1 : 0) + 1 + 1 + 4 * e.points.size();
}

enum Category : int { EVENTS = 1, ENTITY_REMOVALS = 2, GEOMETRY = 3, IDENTITY = 4, TOKENS = 5, TILES = 6, GLOW = 8 };

struct Candidate {
	int category;
	Coord key;    // tile, or {token, 0}, or {event number, 0}
	bool removal;
	size_t bytes;
	double score;
};

} // namespace

void apply_held_rule(ViewState &view, int64_t held_cells) {
	const Coord own_cell = held_cell_of(view.own.tile());
	for (auto it = view.geometry.begin(); it != view.geometry.end();) {
		const Coord c = held_cell_of(it->first);
		const int64_t dx = c.x > own_cell.x ? c.x - own_cell.x : own_cell.x - c.x;
		const int64_t dy = c.y > own_cell.y ? c.y - own_cell.y : own_cell.y - c.y;
		if (dx > held_cells || dy > held_cells) {
			it = view.geometry.erase(it);
		} else {
			++it;
		}
	}
}

ClientView::ClientView(uint64_t secret, uint32_t slot) : secret_(secret), slot_(slot) {
	const int64_t keys[1] = {static_cast<int64_t>(slot)};
	token_state_ = hash_u64(secret, hash_domain::NET_TOKEN, keys, 1);
}

void ClientView::reset() {
	history_.clear();
	frame_events_.clear();
	newest_acked_.reset();
	for (const auto &[entity, token] : tokens_) {
		cooling_[token] = 0;
	}
	tokens_.clear();
	incoming_.clear();
	events_.clear();
	pending_since_.clear();
}

uint16_t ClientView::token_of(uint32_t entity) const {
	auto it = tokens_.find(entity);
	return it == tokens_.end() ? 0 : it->second;
}

void ClientView::on_ack(uint32_t now, uint32_t ack16, uint32_t bits) {
	const uint32_t newest = now - ((now - ack16) & 0xFFFFu);
	std::vector<uint32_t> acked = {newest};
	for (uint32_t i = 0; i < 32; i++) {
		if ((bits >> i) & 1u) {
			acked.push_back(newest - 1 - i);
		}
	}
	for (uint32_t t : acked) {
		if (history_.count(t) == 0) {
			continue;
		}
		if (!newest_acked_ || t > *newest_acked_) {
			newest_acked_ = t;
		}
		auto fe = frame_events_.find(t);
		if (fe != frame_events_.end()) {
			events_.erase(std::remove_if(events_.begin(), events_.end(),
								  [&](const EventRec &e) { return fe->second.count(e.number) != 0; }),
					events_.end());
		}
	}
}

void ClientView::queue_event(const EventIn &e) {
	incoming_.push_back(e);
}

uint16_t ClientView::new_token(uint32_t tick, int64_t cooldown) {
	std::set<uint16_t> in_use;
	for (const auto &[entity, token] : tokens_) {
		in_use.insert(token);
	}
	Rng rng(token_state_);
	for (;;) {
		const uint16_t v = static_cast<uint16_t>(rng.next_u64() & 0xFFFFu);
		token_state_ = rng.state();
		if (v == 0 || in_use.count(v) != 0) {
			continue;
		}
		auto c = cooling_.find(v);
		if (c != cooling_.end() && static_cast<int64_t>(tick) - static_cast<int64_t>(c->second) < cooldown && c->second != 0) {
			continue;
		}
		cooling_.erase(v);
		return v;
	}
}

void ClientView::number_incoming() {
	struct Keyed {
		uint64_t key;
		EventRec rec;
	};
	std::vector<Keyed> keyed;
	for (const EventIn &e : incoming_) {
		EventRec r;
		r.type = e.type;
		r.start_tick = e.start_tick;
		r.ax16 = round_to(e.ax * 16.0);
		r.ay16 = round_to(e.ay * 16.0);
		r.remaining_q4 = static_cast<uint8_t>(clamp_i(round_to(e.remaining_np * 4.0), 0, 255));
		r.level_q4 = static_cast<uint8_t>(clamp_i(round_to(e.level_np * 4.0), 0, 255));
		r.duration_ds = static_cast<uint8_t>(clamp_i(round_to(e.duration_s * 10.0), 0, 255));
		r.voice = e.voice < 0 ? -1 : clamp_i(e.voice, 0, 255);
		r.flags = e.flags;
		r.gain_db = static_cast<int8_t>(clamp_i(e.gain_db, -127, 127));
		for (size_t i = 0; i < e.points.size() && i < MAX_EVENT_POINTS; i++) {
			r.points.emplace_back(round_to(e.points[i].first * 16.0), round_to(e.points[i].second * 16.0));
		}
		// Canonical order: start tick, then a hash of the content keyed by the server secret, so
		// order and numbering never depend on which record is an illusion (§9.2, GDD §15.7).
		std::vector<int64_t> keys = {r.start_tick, r.type, r.ax16, r.ay16, r.remaining_q4 * 256 + r.duration_ds, r.voice,
			r.level_q4 * 65536 + r.flags * 256 + (r.gain_db & 0xFF)};
		for (const auto &pt : r.points) {
			keys.push_back(pt.first);
			keys.push_back(pt.second);
		}
		keyed.push_back({hash_u64(secret_, hash_domain::NET_EVENT_ORDER, keys.data(), keys.size()), r});
	}
	std::stable_sort(keyed.begin(), keyed.end(), [](const Keyed &a, const Keyed &b) {
		return a.rec.start_tick != b.rec.start_tick ? a.rec.start_tick < b.rec.start_tick : a.key < b.key;
	});
	last_numbered_.clear();
	for (Keyed &k : keyed) {
		k.rec.number = next_event_;
		next_event_ = static_cast<uint16_t>(next_event_ + 1);
		if (next_event_ == 0) {
			next_event_ = 1;
		}
		events_.push_back(k.rec);
		last_numbered_.push_back(k.rec);
	}
	incoming_.clear();
}

std::vector<uint8_t> ClientView::build(uint32_t tick, const Desired &desired, uint16_t action_ack, uint8_t input_depth,
		const ReplicationParams &p, BuildStats *stats, uint16_t input_ack) {
	number_incoming();
	static const ViewState EMPTY;
	const ViewState *base = &EMPTY;
	uint32_t base_tick = 0;
	if (!p.full_frames && newest_acked_ && history_.count(*newest_acked_) != 0 && static_cast<int64_t>(tick - *newest_acked_) <= p.history) {
		base = &history_.at(*newest_acked_);
		base_tick = *newest_acked_;
	}
	const bool full = base == &EMPTY;

	// What the client should hold now.
	ViewState want;
	want.own = desired.own;
	want.blinded = desired.frame.blinded;
	want.dust = desired.dust;
	for (const vision::FrameTile &t : desired.frame.tiles) {
		want.tiles[t.tile] = TileView{t.light, t.colour, t.decals};
	}
	want.geometry = base->geometry;
	apply_held_rule(want, p.held_cells);
	for (const auto &[tile, geo] : desired.geometry_now) {
		want.geometry[tile] = geo;
	}
	std::set<uint32_t> present;
	auto token_for = [&](uint32_t entity) {
		present.insert(entity);
		auto it = tokens_.find(entity);
		if (it != tokens_.end()) {
			return it->second;
		}
		const uint16_t t = new_token(tick, p.token_cooldown);
		tokens_[entity] = t;
		return t;
	};
	for (const vision::FrameToken &tk : desired.frame.tokens) {
		EntityView v;
		v.level = 1;
		v.size_or_kind = static_cast<uint8_t>(tk.size);
		v.x64 = round_to(tk.x * 64.0);
		v.y64 = round_to(tk.y * 64.0);
		want.entities[token_for(tk.entity)] = v;
	}
	std::map<uint32_t, uint32_t> margin_now;
	for (const vision::FrameToken &tk : desired.frame.margin_tokens) {
		if (p.margin_delay_ticks > 0) {
			auto since = margin_since_.find(tk.entity);
			const uint32_t first = since != margin_since_.end() ? since->second : tick;
			margin_now[tk.entity] = first;
			if (static_cast<int64_t>(tick - first) < p.margin_delay_ticks) {
				continue;
			}
		}
		EntityView v;
		v.level = 3;
		v.size_or_kind = static_cast<uint8_t>(tk.size);
		v.x64 = round_to(tk.x * 64.0);
		v.y64 = round_to(tk.y * 64.0);
		want.entities[token_for(tk.entity)] = v;
	}
	margin_since_ = std::move(margin_now);
	for (uint32_t entity : desired.frame.identified) {
		EntityView v;
		v.level = 2;
		auto k = desired.identified_kind.find(entity);
		v.size_or_kind = k != desired.identified_kind.end() ? k->second : 0;
		auto f = desired.facing.find(entity);
		v.facing = f != desired.facing.end() ? f->second : 0;
		auto cu = desired.cues.find(entity);
		v.cues = cu != desired.cues.end() ? cu->second : 0;
		auto he = desired.in_hand.find(entity);
		v.in_hand = he != desired.in_hand.end() ? he->second : 0;
		auto fl = desired.flame.find(entity);
		v.flame = fl != desired.flame.end() ? fl->second : 0;
		auto pos = desired.position.find(entity);
		if (pos != desired.position.end()) {
			v.x64 = round_to(pos->second.first * 64.0);
			v.y64 = round_to(pos->second.second * 64.0);
		}
		want.entities[token_for(entity)] = v;
	}
	// A token lives only while its entity stays continuously in the sent set.
	for (auto it = tokens_.begin(); it != tokens_.end();) {
		if (present.count(it->first) == 0) {
			cooling_[it->second] = tick;
			it = tokens_.erase(it);
		} else {
			++it;
		}
	}
	for (size_t b = 0; b < desired.frame.glow.size() && b < GLOW_BUCKETS; b++) {
		if (desired.frame.glow[b].present) {
			want.glow_mask |= 1u << b;
			want.glow_colour[b] = desired.frame.glow[b].colour;
		}
	}

	// The view the client has once it applies this frame starts from the baseline.
	ViewState sent = *base;
	sent.own = want.own;
	sent.blinded = want.blinded;
	sent.dust = want.dust;
	apply_held_rule(sent, p.held_cells);
	const Coord own = want.own.tile();
	auto dist = [&](Coord t) {
		const double dx = static_cast<double>(t.x - own.x), dy = static_cast<double>(t.y - own.y);
		return dx * dx + dy * dy;
	};

	// Candidates: everything that differs from the baseline, and every unacknowledged event.
	std::vector<Candidate> cands;
	std::map<std::pair<int, Coord>, uint32_t> since;
	auto add = [&](int category, Coord key, bool removal, size_t bytes, double order) {
		const std::pair<int, Coord> id{category * 2 + (removal ? 1 : 0), key};
		auto old = pending_since_.find(id);
		const uint32_t first = old != pending_since_.end() ? old->second : tick;
		since[id] = first;
		const double age = static_cast<double>(tick - first);
		cands.push_back({category, key, removal, bytes, category * 1000.0 + order - age * p.age_gain});
	};
	for (const EventRec &e : events_) {
		add(EVENTS, Coord{e.number, 0}, false, event_bytes(e), static_cast<double>(e.number) * 1e-6);
	}
	for (const auto &[token, v] : sent.entities) {
		if (want.entities.count(token) == 0) {
			add(ENTITY_REMOVALS, Coord{token, 0}, true, ENTITY_REMOVE_BYTES, 0.0);
		}
	}
	for (const auto &[tile, g] : want.geometry) {
		auto b = sent.geometry.find(tile);
		if (b == sent.geometry.end() || b->second != g) {
			add(GEOMETRY, tile, false, GEO_BYTES, dist(tile) * 1e-3);
		}
	}
	for (const auto &[token, v] : want.entities) {
		auto b = sent.entities.find(token);
		if (b == sent.entities.end() || b->second != v) {
			const double dx = static_cast<double>(v.x64) / 64.0 - own.x, dy = static_cast<double>(v.y64) / 64.0 - own.y;
			add(v.level == 2 ? IDENTITY : TOKENS, Coord{token, 0}, false, v.level == 2 ? IDENTITY_BYTES : TOKEN_BYTES,
					(dx * dx + dy * dy) * 1e-3);
		}
	}
	for (const auto &[tile, v] : sent.tiles) {
		if (want.tiles.count(tile) == 0) {
			add(TILES, tile, true, TILE_REMOVE_BYTES, dist(tile) * 1e-3);
		}
	}
	for (const auto &[tile, v] : want.tiles) {
		auto b = sent.tiles.find(tile);
		if (b == sent.tiles.end() || b->second != v) {
			add(TILES, tile, false, TILE_BYTES, dist(tile) * 1e-3);
		}
	}
	const bool glow_changed = want.glow_mask != sent.glow_mask || want.glow_colour != sent.glow_colour;
	if (glow_changed) {
		add(GLOW, Coord{0, 0}, false, 4 + popcount32(want.glow_mask), 0.0);
	}
	std::stable_sort(cands.begin(), cands.end(), [](const Candidate &a, const Candidate &b) { return a.score < b.score; });

	// The budget: a token bucket, and never more than an unreliable message holds.
	if (bucket_ < 0.0) {
		bucket_ = static_cast<double>(p.burst_bytes);
	}
	bucket_ = std::min(static_cast<double>(p.burst_bytes), bucket_ + static_cast<double>(p.budget_bytes_per_tick));
	const size_t fixed = HEADER_BYTES + OWN_BYTES + COUNT_BYTES;
	const double limit = std::max(static_cast<double>(fixed), std::min(static_cast<double>(p.max_frame_bytes), bucket_));
	size_t used = fixed;
	std::set<std::pair<int, Coord>> chosen;
	size_t event_count = 0;
	for (const Candidate &c : cands) {
		if (c.category == EVENTS && event_count >= 255) {
			continue;
		}
		if (static_cast<double>(used + c.bytes) > limit) {
			continue;
		}
		used += c.bytes;
		chosen.insert({c.category * 2 + (c.removal ? 1 : 0), c.key});
		if (c.category == EVENTS) {
			event_count++;
		}
	}
	auto picked = [&](int category, Coord key, bool removal) { return chosen.count({category * 2 + (removal ? 1 : 0), key}) != 0; };
	pending_since_.clear();
	for (const auto &[id, first] : since) {
		if (chosen.count(id) == 0) {
			pending_since_[id] = first;
		}
	}

	// Write, in canonical order (tiles row-major, entities by token, events by number).
	ByteWriter w;
	w.u8(FRAME_VERSION);
	w.u32(tick);
	w.u16(full ? 0 : tick - base_tick);
	w.u16(action_ack);
	w.u16(input_ack);
	w.u8(input_depth);
	w.u8((full ? FLAG_FULL : 0) | (want.blinded ? FLAG_BLINDED : 0) | (want.dust ? FLAG_DUST : 0));
	w.i32(want.own.x256);
	w.i32(want.own.y256);
	w.u16(want.own.facing);
	w.u8(want.own.gait);
	w.u8(want.own.speed_q);
	w.u16(want.own.flags);
	w.u8(want.own.stamina_q);
	w.u8(want.own.lamp_radius_q);
	w.u8(want.own.flame);
	BuildStats st;
	st.full = full;
	// Tile changes.
	size_t at = w.size();
	w.u16(0);
	uint32_t n = 0;
	for (const auto &[tile, v] : want.tiles) {
		auto b = sent.tiles.find(tile);
		if (b != sent.tiles.end() && b->second == v) {
			continue;
		}
		if (!picked(TILES, tile, false)) {
			st.tiles_pending++;
			continue;
		}
		w.i8(static_cast<int32_t>(tile.x - own.x));
		w.i8(static_cast<int32_t>(tile.y - own.y));
		w.u8(v.light);
		w.u8(v.colour);
		w.u8(v.decals);
		n++;
	}
	w.patch_u16(at, n);
	st.tiles_sent = n;
	std::map<Coord, TileView> next_tiles = sent.tiles;
	for (const auto &[tile, v] : want.tiles) {
		if (picked(TILES, tile, false)) {
			next_tiles[tile] = v;
		}
	}
	// Tile removals.
	at = w.size();
	w.u16(0);
	n = 0;
	for (const auto &[tile, v] : sent.tiles) {
		if (want.tiles.count(tile) != 0) {
			continue;
		}
		if (!picked(TILES, tile, true)) {
			st.tiles_pending++;
			continue;
		}
		w.i8(static_cast<int32_t>(tile.x - own.x));
		w.i8(static_cast<int32_t>(tile.y - own.y));
		next_tiles.erase(tile);
		n++;
	}
	w.patch_u16(at, n);
	sent.tiles = std::move(next_tiles);
	// Geometry.
	at = w.size();
	w.u16(0);
	n = 0;
	for (const auto &[tile, g] : want.geometry) {
		auto b = sent.geometry.find(tile);
		if (b != sent.geometry.end() && b->second == g) {
			continue;
		}
		if (!picked(GEOMETRY, tile, false)) {
			st.geometry_pending++;
			continue;
		}
		w.i8(static_cast<int32_t>(tile.x - own.x));
		w.i8(static_cast<int32_t>(tile.y - own.y));
		w.u8(g.material);
		w.u8(g.state);
		n++;
	}
	w.patch_u16(at, n);
	st.geometry_sent = n;
	for (const auto &[tile, g] : want.geometry) {
		if (picked(GEOMETRY, tile, false)) {
			sent.geometry[tile] = g;
		}
	}
	// Entity changes.
	at = w.size();
	w.u16(0);
	n = 0;
	for (const auto &[token, v] : want.entities) {
		auto b = sent.entities.find(token);
		if (b != sent.entities.end() && b->second == v) {
			continue;
		}
		if (!picked(v.level == 2 ? IDENTITY : TOKENS, Coord{token, 0}, false)) {
			st.entities_pending++;
			continue;
		}
		w.u16(token);
		w.u8(v.level);
		w.u8(v.size_or_kind);
		w.i16(clamp_i(v.x64 - own.x * 64, -32768, 32767));
		w.i16(clamp_i(v.y64 - own.y * 64, -32768, 32767));
		if (v.level == 2) {
			w.u16(v.facing);
			w.u16(v.cues);
			w.u16(v.in_hand);
			w.u8(v.flame);
		}
		n++;
	}
	w.patch_u16(at, n);
	st.entities_sent = n;
	std::map<uint16_t, EntityView> next_entities = sent.entities;
	for (const auto &[token, v] : want.entities) {
		if (picked(v.level == 2 ? IDENTITY : TOKENS, Coord{token, 0}, false)) {
			EntityView stored = v;
			// What the client decodes: the relative position, clamped as written.
			stored.x64 = own.x * 64 + clamp_i(v.x64 - own.x * 64, -32768, 32767);
			stored.y64 = own.y * 64 + clamp_i(v.y64 - own.y * 64, -32768, 32767);
			next_entities[token] = stored;
		}
	}
	// Entity removals.
	at = w.size();
	w.u16(0);
	n = 0;
	for (const auto &[token, v] : sent.entities) {
		if (want.entities.count(token) != 0) {
			continue;
		}
		if (!picked(ENTITY_REMOVALS, Coord{token, 0}, true)) {
			st.entities_pending++;
			continue;
		}
		w.u16(token);
		next_entities.erase(token);
		n++;
	}
	w.patch_u16(at, n);
	sent.entities = std::move(next_entities);
	// Edge glow.
	if (glow_changed && picked(GLOW, Coord{0, 0}, false)) {
		w.u8(1);
		w.u32(want.glow_mask);
		for (size_t b = 0; b < GLOW_BUCKETS; b++) {
			if ((want.glow_mask >> b) & 1u) {
				w.u8(want.glow_colour[b]);
			}
		}
		sent.glow_mask = want.glow_mask;
		sent.glow_colour = want.glow_colour;
	} else {
		w.u8(0);
	}
	// Events.
	std::vector<const EventRec *> out_events;
	for (const EventRec &e : events_) {
		if (picked(EVENTS, Coord{e.number, 0}, false)) {
			out_events.push_back(&e);
		} else {
			st.events_pending++;
		}
	}
	w.u8(static_cast<uint32_t>(out_events.size()));
	std::set<uint16_t> numbers;
	for (const EventRec *e : out_events) {
		w.u16(e->number);
		w.u8(e->type);
		w.u32(e->start_tick);
		w.i16(clamp_i(e->ax16 - own.x * 16, -32768, 32767));
		w.i16(clamp_i(e->ay16 - own.y * 16, -32768, 32767));
		w.u8(e->remaining_q4);
		w.u8(e->level_q4);
		w.u8(e->duration_ds);
		w.u8(static_cast<uint32_t>(e->flags) | (e->voice >= 0 ? 0x80u : 0u));
		if (e->voice >= 0) {
			w.u8(static_cast<uint32_t>(e->voice));
		}
		w.i8(e->gain_db);
		w.u8(static_cast<uint32_t>(e->points.size()));
		for (const auto &pt : e->points) {
			w.i16(clamp_i(pt.first - e->ax16, -32768, 32767));
			w.i16(clamp_i(pt.second - e->ay16, -32768, 32767));
		}
		numbers.insert(e->number);
	}
	st.events_sent = out_events.size();

	history_[tick] = std::move(sent);
	frame_events_[tick] = std::move(numbers);
	while (!history_.empty() && static_cast<int64_t>(tick - history_.begin()->first) > p.history) {
		frame_events_.erase(history_.begin()->first);
		history_.erase(history_.begin());
	}
	bucket_ -= static_cast<double>(w.size());
	st.bytes = w.size();
	if (stats != nullptr) {
		*stats = st;
	}
	return w.take();
}

Decoded decode_frame(const std::vector<uint8_t> &bytes, const std::map<uint32_t, ViewState> &history, int64_t held_cells) {
	Decoded d;
	ByteReader r(bytes.data(), bytes.size());
	if (r.u8() != FRAME_VERSION) {
		return d;
	}
	d.tick = r.u32();
	const uint32_t age = r.u16();
	d.action_ack = static_cast<uint16_t>(r.u16());
	d.input_ack = static_cast<uint16_t>(r.u16());
	d.input_depth = static_cast<uint8_t>(r.u8());
	const uint32_t flags = r.u8();
	d.full = (flags & FLAG_FULL) != 0;
	if (age != 0) {
		d.baseline_tick = d.tick - age;
		auto b = history.find(d.baseline_tick);
		if (b == history.end()) {
			return d;
		}
		d.view = b->second;
	}
	d.view.own.x256 = r.i32();
	d.view.own.y256 = r.i32();
	d.view.own.facing = static_cast<uint16_t>(r.u16());
	d.view.own.gait = static_cast<uint8_t>(r.u8());
	d.view.own.speed_q = static_cast<uint8_t>(r.u8());
	d.view.own.flags = static_cast<uint16_t>(r.u16());
	d.view.own.stamina_q = static_cast<uint8_t>(r.u8());
	d.view.own.lamp_radius_q = static_cast<uint8_t>(r.u8());
	d.view.own.flame = static_cast<uint8_t>(r.u8());
	d.view.blinded = (flags & FLAG_BLINDED) != 0;
	d.view.dust = (flags & FLAG_DUST) != 0;
	apply_held_rule(d.view, held_cells);
	const Coord own = d.view.own.tile();
	for (uint32_t i = 0, n = r.u16(); i < n && r.ok(); i++) {
		const Coord t{own.x + r.i8(), own.y + r.i8()};
		TileView v;
		v.light = static_cast<uint8_t>(r.u8());
		v.colour = static_cast<uint8_t>(r.u8());
		v.decals = static_cast<uint8_t>(r.u8());
		d.view.tiles[t] = v;
	}
	for (uint32_t i = 0, n = r.u16(); i < n && r.ok(); i++) {
		const Coord t{own.x + r.i8(), own.y + r.i8()};
		d.view.tiles.erase(t);
	}
	for (uint32_t i = 0, n = r.u16(); i < n && r.ok(); i++) {
		const Coord t{own.x + r.i8(), own.y + r.i8()};
		GeoView g;
		g.material = static_cast<uint8_t>(r.u8());
		g.state = static_cast<uint8_t>(r.u8());
		d.view.geometry[t] = g;
	}
	for (uint32_t i = 0, n = r.u16(); i < n && r.ok(); i++) {
		const uint16_t token = static_cast<uint16_t>(r.u16());
		EntityView v;
		v.level = static_cast<uint8_t>(r.u8());
		v.size_or_kind = static_cast<uint8_t>(r.u8());
		v.x64 = own.x * 64 + r.i16();
		v.y64 = own.y * 64 + r.i16();
		if (v.level == 2) {
			v.facing = static_cast<uint16_t>(r.u16());
			v.cues = static_cast<uint16_t>(r.u16());
			v.in_hand = static_cast<uint16_t>(r.u16());
			v.flame = static_cast<uint8_t>(r.u8());
		}
		d.view.entities[token] = v;
	}
	for (uint32_t i = 0, n = r.u16(); i < n && r.ok(); i++) {
		d.view.entities.erase(static_cast<uint16_t>(r.u16()));
	}
	if (r.u8() == 1) {
		d.view.glow_mask = r.u32();
		d.view.glow_colour.fill(0);
		for (size_t b = 0; b < GLOW_BUCKETS; b++) {
			if ((d.view.glow_mask >> b) & 1u) {
				d.view.glow_colour[b] = static_cast<uint8_t>(r.u8());
			}
		}
	}
	for (uint32_t i = 0, n = r.u8(); i < n && r.ok(); i++) {
		EventRec e;
		e.number = static_cast<uint16_t>(r.u16());
		e.type = static_cast<uint8_t>(r.u8());
		e.start_tick = r.u32();
		e.ax16 = own.x * 16 + r.i16();
		e.ay16 = own.y * 16 + r.i16();
		e.remaining_q4 = static_cast<uint8_t>(r.u8());
		e.level_q4 = static_cast<uint8_t>(r.u8());
		e.duration_ds = static_cast<uint8_t>(r.u8());
		const uint32_t flags = r.u8();
		e.flags = static_cast<uint8_t>(flags & 0x7Fu);
		e.voice = (flags & 0x80u) != 0 ? static_cast<int32_t>(r.u8()) : -1;
		e.gain_db = static_cast<int8_t>(r.i8());
		for (uint32_t k = 0, np = r.u8(); k < np && k < MAX_EVENT_POINTS && r.ok(); k++) {
			const int64_t px = e.ax16 + r.i16();
			const int64_t py = e.ay16 + r.i16();
			e.points.emplace_back(px, py);
		}
		d.events.push_back(e);
	}
	d.ok = r.ok() && r.done();
	return d;
}

} // namespace lb::core::net

#include "godot/net/lb_replication.h"

#include "core/sim/entity_mirror.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>

#include <algorithm>

using namespace godot;
using lb::core::world::Coord;
namespace net = lb::core::net;

namespace lb::godot {

void LbReplication::_bind_methods() {
	ClassDB::bind_method(D_METHOD("attach", "vision", "mine"), &LbReplication::attach);
	ClassDB::bind_method(D_METHOD("set_params", "params"), &LbReplication::set_params);
	ClassDB::bind_method(D_METHOD("add_client", "slot", "secret"), &LbReplication::add_client);
	ClassDB::bind_method(D_METHOD("remove_client", "slot"), &LbReplication::remove_client);
	ClassDB::bind_method(D_METHOD("reset_client", "slot"), &LbReplication::reset_client);
	ClassDB::bind_method(D_METHOD("has_client", "slot"), &LbReplication::has_client);
	ClassDB::bind_method(D_METHOD("set_seen_kind", "entity_kind", "seen_kind"), &LbReplication::set_seen_kind);
	ClassDB::bind_method(D_METHOD("set_entity_facing", "entity", "facing"), &LbReplication::set_entity_facing);
	ClassDB::bind_method(D_METHOD("clear_entity_facing", "entity"), &LbReplication::clear_entity_facing);
	ClassDB::bind_method(D_METHOD("set_entity_cues", "entity", "cues"), &LbReplication::set_entity_cues);
	ClassDB::bind_method(D_METHOD("set_entity_held", "entity", "bits"), &LbReplication::set_entity_held);
	ClassDB::bind_method(D_METHOD("set_entity_attached", "entity", "attached"), &LbReplication::set_entity_attached);
	ClassDB::bind_method(D_METHOD("set_entity_flame", "entity", "bits"), &LbReplication::set_entity_flame);
	ClassDB::bind_method(D_METHOD("on_ack", "slot", "now", "ack16", "bits"), &LbReplication::on_ack);
	ClassDB::bind_method(D_METHOD("queue_event", "slot", "event"), &LbReplication::queue_event);
	ClassDB::bind_method(D_METHOD("build", "slot", "observer", "tick", "own", "action_ack", "input_depth", "input_ack"), &LbReplication::build, DEFVAL(0xFFFF));
	ClassDB::bind_method(D_METHOD("last_stats", "slot"), &LbReplication::last_stats);
	ClassDB::bind_method(D_METHOD("token_of", "slot", "entity"), &LbReplication::token_of);
	ClassDB::bind_method(D_METHOD("last_numbered", "slot"), &LbReplication::last_numbered);
	ClassDB::bind_method(D_METHOD("sent_view", "slot", "tick"), &LbReplication::sent_view);
}

void LbReplication::attach(const Ref<LbVision> &vision, const Ref<LbMine> &mine) {
	vision_ = vision;
	mine_ = mine;
}

void LbReplication::set_params(const Dictionary &d) {
	params_.budget_bytes_per_tick = static_cast<int64_t>(static_cast<double>(d.get("budget_kbps", 64.0)) * 1000.0 / 8.0 / 20.0 + 0.5);
	params_.burst_bytes = d.get("burst_bytes", params_.burst_bytes);
	params_.max_frame_bytes = d.get("max_frame_bytes", params_.max_frame_bytes);
	params_.history = d.get("history", params_.history);
	params_.token_cooldown = d.get("token_cooldown", params_.token_cooldown);
	params_.age_gain = d.get("age_gain", params_.age_gain);
	params_.held_cells = d.get("held_cells", params_.held_cells);
	params_.full_frames = d.get("full_frames", params_.full_frames);
	params_.margin_delay_ticks = d.get("margin_delay_ticks", params_.margin_delay_ticks);
}

void LbReplication::add_client(int64_t slot, int64_t secret) {
	clients_[slot] = std::make_unique<net::ClientView>(static_cast<uint64_t>(secret), static_cast<uint32_t>(slot));
}

void LbReplication::remove_client(int64_t slot) {
	clients_.erase(slot);
	stats_.erase(slot);
}

void LbReplication::reset_client(int64_t slot) {
	auto it = clients_.find(slot);
	if (it != clients_.end()) {
		it->second->reset();
	}
}

bool LbReplication::has_client(int64_t slot) const {
	return clients_.count(slot) != 0;
}

void LbReplication::set_seen_kind(int64_t entity_kind, int64_t seen_kind) {
	seen_kind_[static_cast<uint16_t>(entity_kind)] = static_cast<uint8_t>(seen_kind);
}

void LbReplication::set_entity_facing(int64_t entity, int64_t facing) {
	facing_[static_cast<uint32_t>(entity)] = static_cast<uint16_t>(facing & 0xFFFF);
}

void LbReplication::set_entity_cues(int64_t entity, int64_t cues) {
	if (cues == 0) {
		cues_.erase(static_cast<uint32_t>(entity));
	} else {
		cues_[static_cast<uint32_t>(entity)] = static_cast<uint16_t>(cues & 0xFFFF);
	}
}

void LbReplication::set_entity_held(int64_t entity, int64_t bits) {
	if (bits == 0) {
		in_hand_.erase(static_cast<uint32_t>(entity));
	} else {
		in_hand_[static_cast<uint32_t>(entity)] = static_cast<uint16_t>(bits & 0xFFFF);
	}
}

void LbReplication::clear_entity_facing(int64_t entity) {
	facing_.erase(static_cast<uint32_t>(entity));
}

void LbReplication::set_entity_attached(int64_t entity, bool attached) {
	if (attached) {
		attached_.insert(static_cast<uint32_t>(entity));
	} else {
		attached_.erase(static_cast<uint32_t>(entity));
	}
}

void LbReplication::set_entity_flame(int64_t entity, int64_t bits) {
	if (bits == 0) {
		flame_.erase(static_cast<uint32_t>(entity));
	} else {
		flame_[static_cast<uint32_t>(entity)] = static_cast<uint8_t>(bits & 0xFF);
	}
}

void LbReplication::on_ack(int64_t slot, int64_t now, int64_t ack16, int64_t bits) {
	auto it = clients_.find(slot);
	if (it != clients_.end()) {
		it->second->on_ack(static_cast<uint32_t>(now), static_cast<uint32_t>(ack16), static_cast<uint32_t>(bits));
	}
}

void LbReplication::queue_event(int64_t slot, const Dictionary &d) {
	auto it = clients_.find(slot);
	ERR_FAIL_COND_MSG(it == clients_.end(), "LbReplication.queue_event: no such client");
	net::EventIn e;
	e.type = static_cast<uint8_t>(static_cast<int64_t>(d.get("type", 0)));
	e.start_tick = static_cast<uint32_t>(static_cast<int64_t>(d.get("start_tick", 0)));
	const Vector2 a = d.get("apparent", Vector2());
	e.ax = a.x;
	e.ay = a.y;
	e.remaining_np = d.get("remaining_np", 0.0);
	e.level_np = d.get("level_np", e.remaining_np);
	e.duration_s = d.get("duration_s", 0.5);
	e.voice = static_cast<int32_t>(static_cast<int64_t>(d.get("voice", -1)));
	e.flags = static_cast<uint8_t>(static_cast<int64_t>(d.get("flags", 0)) & 0x7F);
	e.gain_db = static_cast<int32_t>(static_cast<int64_t>(d.get("gain_db", 0)));
	const Array points = d.get("points", Array());
	for (int64_t i = 0; i < points.size(); i++) {
		const Vector2 p = points[i];
		e.points.emplace_back(p.x, p.y);
	}
	it->second->queue_event(e);
}

PackedByteArray LbReplication::build(int64_t slot, int64_t observer, int64_t tick, const Dictionary &own, int64_t action_ack, int64_t input_depth, int64_t input_ack) {
	PackedByteArray out;
	auto it = clients_.find(slot);
	ERR_FAIL_COND_V_MSG(it == clients_.end(), out, "LbReplication.build: no such client");
	net::Desired desired;
	desired.own.x256 = static_cast<int32_t>(static_cast<double>(own.get("x", 0.0)) * 256.0);
	desired.own.y256 = static_cast<int32_t>(static_cast<double>(own.get("y", 0.0)) * 256.0);
	desired.own.facing = static_cast<uint16_t>(static_cast<int64_t>(own.get("facing", 0)) & 0xFFFF);
	desired.own.gait = static_cast<uint8_t>(static_cast<int64_t>(own.get("gait", 255)) & 0xFF);
	desired.own.speed_q = static_cast<uint8_t>(static_cast<int64_t>(own.get("speed_q", 100)));
	desired.own.flags = static_cast<uint16_t>(static_cast<int64_t>(own.get("flags", 0)));
	desired.own.stamina_q = static_cast<uint8_t>(static_cast<int64_t>(own.get("stamina_q", 120)));
	const double lamp_radius = own.get("lamp_radius", 0.0);
	desired.own.lamp_radius_q = static_cast<uint8_t>(lamp_radius <= 0.0 ? 0 : (lamp_radius * 16.0 >= 255.0 ? 255 : lamp_radius * 16.0 + 0.5));
	desired.own.flame = static_cast<uint8_t>(static_cast<int64_t>(own.get("flame", 0)) & 0xFF);
	desired.dust = own.get("dust", false);
	if (observer >= 0 && vision_.is_valid() && vision_->core() != nullptr) {
		const lb::core::vision::PerceptionFrame *frame = vision_->core()->last_frame(static_cast<uint32_t>(observer));
		if (frame != nullptr) {
			desired.frame = *frame;
		}
	}
	if (!attached_.empty()) {
		auto riding = [&](uint32_t entity) { return attached_.count(entity) != 0; };
		auto token_riding = [&](const lb::core::vision::FrameToken &t) { return riding(t.entity); };
		auto &tokens = desired.frame.tokens;
		tokens.erase(std::remove_if(tokens.begin(), tokens.end(), token_riding), tokens.end());
		auto &margin = desired.frame.margin_tokens;
		margin.erase(std::remove_if(margin.begin(), margin.end(), token_riding), margin.end());
		auto &identified = desired.frame.identified;
		identified.erase(std::remove_if(identified.begin(), identified.end(), riding), identified.end());
	}
	const lb::core::sim::EntityMirror &mirror = lb::core::sim::EntityMirror::current();
	for (uint32_t entity : desired.frame.identified) {
		auto e = mirror.find(entity);
		if (!e) {
			continue;
		}
		auto k = seen_kind_.find(e->kind);
		desired.identified_kind[entity] = k != seen_kind_.end() ? k->second : 0;
		desired.position[entity] = {e->x, e->y};
		auto f = facing_.find(entity);
		desired.facing[entity] = f != facing_.end() ? f->second : 0;
		auto cu = cues_.find(entity);
		if (cu != cues_.end()) {
			desired.cues[entity] = cu->second;
		}
		auto ih = in_hand_.find(entity);
		if (ih != in_hand_.end()) {
			desired.in_hand[entity] = ih->second;
		}
		auto fl = flame_.find(entity);
		if (fl != flame_.end()) {
			desired.flame[entity] = fl->second;
		}
	}
	if (mine_.is_valid()) {
		for (const Coord &t : desired.frame.margin_tiles) {
			const std::optional<lb::core::world::Tile> tile = mine_->map().tile_at(t);
			if (tile) {
				desired.geometry_now[t] = net::GeoView{static_cast<uint8_t>(tile->material), static_cast<uint8_t>(tile->state)};
			}
		}
		for (const lb::core::vision::FrameTile &t : desired.frame.tiles) {
			const std::optional<lb::core::world::Tile> tile = mine_->map().tile_at(t.tile);
			if (tile) {
				desired.geometry_now[t.tile] = net::GeoView{static_cast<uint8_t>(tile->material), static_cast<uint8_t>(tile->state)};
			}
		}
	}
	net::BuildStats st;
	const std::vector<uint8_t> bytes = it->second->build(static_cast<uint32_t>(tick), desired, static_cast<uint16_t>(action_ack & 0xFFFF),
			static_cast<uint8_t>(input_depth < 0 ? 0 : (input_depth > 255 ? 255 : input_depth)), params_, &st,
			static_cast<uint16_t>(input_ack & 0xFFFF));
	stats_[slot] = st;
	out.resize(static_cast<int64_t>(bytes.size()));
	for (size_t i = 0; i < bytes.size(); i++) {
		out.set(static_cast<int64_t>(i), bytes[i]);
	}
	return out;
}

Dictionary LbReplication::last_stats(int64_t slot) const {
	Dictionary out;
	auto it = stats_.find(slot);
	if (it == stats_.end()) {
		return out;
	}
	const net::BuildStats &s = it->second;
	out["bytes"] = static_cast<int64_t>(s.bytes);
	out["full"] = s.full;
	out["tiles_sent"] = static_cast<int64_t>(s.tiles_sent);
	out["tiles_pending"] = static_cast<int64_t>(s.tiles_pending);
	out["geometry_sent"] = static_cast<int64_t>(s.geometry_sent);
	out["geometry_pending"] = static_cast<int64_t>(s.geometry_pending);
	out["entities_sent"] = static_cast<int64_t>(s.entities_sent);
	out["entities_pending"] = static_cast<int64_t>(s.entities_pending);
	out["events_sent"] = static_cast<int64_t>(s.events_sent);
	out["events_pending"] = static_cast<int64_t>(s.events_pending);
	return out;
}

int64_t LbReplication::token_of(int64_t slot, int64_t entity) const {
	auto it = clients_.find(slot);
	return it == clients_.end() ? 0 : it->second->token_of(static_cast<uint32_t>(entity));
}

// FND-08: [{number, type, start_tick, ax16, ay16}] for the events numbered at this client's last
// build, so the QA overlay can name an illusion by its record number. Server-side only.
Array LbReplication::last_numbered(int64_t slot) const {
	Array out;
	auto it = clients_.find(slot);
	if (it == clients_.end()) {
		return out;
	}
	for (const net::EventRec &r : it->second->last_numbered()) {
		Dictionary d;
		d["number"] = static_cast<int64_t>(r.number);
		d["type"] = static_cast<int64_t>(r.type);
		d["start_tick"] = static_cast<int64_t>(r.start_tick);
		d["ax16"] = r.ax16;
		d["ay16"] = r.ay16;
		out.push_back(d);
	}
	return out;
}

void LbFrameCodec::_bind_methods() {
	ClassDB::bind_static_method("LbFrameCodec", D_METHOD("decode_records", "bytes"), &LbFrameCodec::decode_records);
}

Dictionary LbFrameCodec::decode_records(const PackedByteArray &bytes) {
	std::vector<uint8_t> raw(static_cast<size_t>(bytes.size()));
	for (int64_t i = 0; i < bytes.size(); i++) {
		raw[static_cast<size_t>(i)] = bytes[i];
	}
	// No baseline: decode as though against an empty view, so the view holds exactly the
	// records this frame carries (removals have nothing to remove).
	std::map<uint32_t, net::ViewState> history;
	if (raw.size() >= 9) {
		const uint32_t tick = raw[1] | (raw[2] << 8) | (raw[3] << 16) | (static_cast<uint32_t>(raw[4]) << 24);
		const uint32_t age = raw[5] | (raw[6] << 8);
		if (age != 0) {
			history[tick - age] = net::ViewState{};
		}
	}
	const net::Decoded d = net::decode_frame(raw, history, 1 << 20);
	Dictionary out;
	out["ok"] = d.ok;
	out["tick"] = static_cast<int64_t>(d.tick);
	out["full"] = d.full;
	PackedInt32Array tx, ty;
	for (const auto &[t, v] : d.view.tiles) {
		tx.push_back(static_cast<int32_t>(t.x));
		ty.push_back(static_cast<int32_t>(t.y));
	}
	out["tile_x"] = tx;
	out["tile_y"] = ty;
	Array entities;
	for (const auto &[token, v] : d.view.entities) {
		Dictionary e;
		e["token"] = static_cast<int64_t>(token);
		e["level"] = static_cast<int64_t>(v.level);
		e["size_or_kind"] = static_cast<int64_t>(v.size_or_kind);
		e["position"] = Vector2(static_cast<real_t>(v.x64 / 64.0), static_cast<real_t>(v.y64 / 64.0));
		if (v.level == 2) {
			e["facing"] = static_cast<int64_t>(v.facing);
			e["cues"] = static_cast<int64_t>(v.cues);
			e["in_hand"] = static_cast<int64_t>(v.in_hand);
			e["flame"] = static_cast<int64_t>(v.flame);
		}
		entities.push_back(e);
	}
	out["entities"] = entities;
	Array events;
	for (const net::EventRec &e : d.events) {
		Dictionary ev;
		ev["number"] = static_cast<int64_t>(e.number);
		ev["type"] = static_cast<int64_t>(e.type);
		ev["start_tick"] = static_cast<int64_t>(e.start_tick);
		ev["apparent"] = Vector2(static_cast<real_t>(e.ax16 / 16.0), static_cast<real_t>(e.ay16 / 16.0));
		ev["remaining_np"] = e.remaining_q4 / 4.0;
		ev["level_np"] = e.level_q4 / 4.0;
		ev["duration_s"] = e.duration_ds / 10.0;
		ev["flags"] = static_cast<int64_t>(e.flags);
		ev["gain_db"] = static_cast<int64_t>(e.gain_db);
		Array pts;
		for (const auto &pt : e.points) {
			pts.push_back(Vector2(static_cast<real_t>(pt.first / 16.0), static_cast<real_t>(pt.second / 16.0)));
		}
		ev["points"] = pts;
		if (e.voice >= 0) {
			ev["voice"] = static_cast<int64_t>(e.voice);
		}
		events.push_back(ev);
	}
	out["events"] = events;
	Dictionary own;
	own["x"] = d.view.own.x256 / 256.0;
	own["y"] = d.view.own.y256 / 256.0;
	own["facing"] = static_cast<int64_t>(d.view.own.facing);
	own["gait"] = static_cast<int64_t>(d.view.own.gait);
	own["stamina_q"] = static_cast<int64_t>(d.view.own.stamina_q);
	own["lamp_radius"] = d.view.own.lamp_radius_q / 16.0;
	own["flame"] = static_cast<int64_t>(d.view.own.flame);
	out["own"] = own;
	return out;
}

Dictionary LbReplication::sent_view(int64_t slot, int64_t tick) const {
	Dictionary out;
	auto c = clients_.find(slot);
	const net::ViewState *found = c == clients_.end() ? nullptr : c->second->sent_view(static_cast<uint32_t>(tick));
	if (found == nullptr) {
		return out;
	}
	const net::ViewState &v = *found;
	Dictionary tiles;
	for (const auto &[t, tv] : v.tiles) {
		PackedByteArray b;
		b.resize(3);
		b[0] = tv.light;
		b[1] = tv.colour;
		b[2] = tv.decals;
		tiles[Vector2i(static_cast<int32_t>(t.x), static_cast<int32_t>(t.y))] = b;
	}
	Dictionary geometry;
	for (const auto &[t, g] : v.geometry) {
		PackedByteArray b;
		b.resize(2);
		b[0] = g.material;
		b[1] = g.state;
		geometry[Vector2i(static_cast<int32_t>(t.x), static_cast<int32_t>(t.y))] = b;
	}
	Dictionary entities;
	for (const auto &[token, e] : v.entities) {
		Dictionary d;
		d["level"] = static_cast<int64_t>(e.level);
		d["size_or_kind"] = static_cast<int64_t>(e.size_or_kind);
		d["position"] = Vector2(static_cast<real_t>(e.x64 / 64.0), static_cast<real_t>(e.y64 / 64.0));
		if (e.level == 2) {
			d["facing"] = static_cast<int64_t>(e.facing);
			d["cues"] = static_cast<int64_t>(e.cues);
			d["in_hand"] = static_cast<int64_t>(e.in_hand);
			d["flame"] = static_cast<int64_t>(e.flame);
		}
		entities[static_cast<int64_t>(token)] = d;
	}
	PackedByteArray glow;
	glow.resize(static_cast<int64_t>(net::GLOW_BUCKETS));
	for (size_t b = 0; b < net::GLOW_BUCKETS; b++) {
		glow[static_cast<int64_t>(b)] = v.glow_colour[b];
	}
	Dictionary own;
	own["position"] = Vector2(static_cast<real_t>(v.own.x256 / 256.0), static_cast<real_t>(v.own.y256 / 256.0));
	own["facing"] = static_cast<int64_t>(v.own.facing);
	own["gait"] = static_cast<int64_t>(v.own.gait);
	own["speed_q"] = static_cast<int64_t>(v.own.speed_q);
	own["flags"] = static_cast<int64_t>(v.own.flags);
	own["stamina_q"] = static_cast<int64_t>(v.own.stamina_q);
	own["lamp_radius"] = v.own.lamp_radius_q / 16.0;
	own["flame"] = static_cast<int64_t>(v.own.flame);
	out["tiles"] = tiles;
	out["geometry"] = geometry;
	out["entities"] = entities;
	out["glow_mask"] = static_cast<int64_t>(v.glow_mask);
	out["glow_colour"] = glow;
	out["own"] = own;
	out["blinded"] = v.blinded;
	out["dust"] = v.dust;
	return out;
}

} // namespace lb::godot

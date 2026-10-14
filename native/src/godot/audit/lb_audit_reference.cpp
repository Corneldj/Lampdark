#include "godot/audit/lb_audit_reference.h"

#ifdef LB_DEBUG_TOOLS

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/rect2i.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector2i.hpp>

#include <cmath>

namespace lb::godot {

using namespace ::godot;
namespace ref = lb::audit;

namespace {

int64_t thousandths(double v) {
	return v < 0.0 ? -1 : static_cast<int64_t>(v * 1000.0 + 0.5);
}

ref::Pos pos_of(Vector2i v) {
	return {v.x, v.y};
}

} // namespace

void LbAuditReference::_bind_methods() {
	ClassDB::bind_method(D_METHOD("attach", "mine"), &LbAuditReference::attach);
	ClassDB::bind_method(D_METHOD("set_vision_defs", "defs"), &LbAuditReference::set_vision_defs);
	ClassDB::bind_method(D_METHOD("set_light_defs", "defs"), &LbAuditReference::set_light_defs);
	ClassDB::bind_method(D_METHOD("snapshot_light", "grid", "rects"), &LbAuditReference::snapshot_light);
	ClassDB::bind_method(D_METHOD("evaluate", "observer", "entities"), &LbAuditReference::evaluate);
	ClassDB::bind_method(D_METHOD("light_at", "tile"), &LbAuditReference::light_at);
	ClassDB::bind_method(D_METHOD("fov_contains", "from", "range", "tile"), &LbAuditReference::fov_contains);
	ClassDB::bind_method(D_METHOD("reach_cost", "origins", "to", "max_cost", "voice", "closed_cost"), &LbAuditReference::reach_cost);
	ClassDB::bind_method(D_METHOD("straight_line", "from", "to"), &LbAuditReference::straight_line);
	ClassDB::bind_integer_constant("LbAuditReference", "", "LEVEL_NONE", ref::LEVEL_NONE);
	ClassDB::bind_integer_constant("LbAuditReference", "", "LEVEL_TOKEN", ref::LEVEL_TOKEN);
	ClassDB::bind_integer_constant("LbAuditReference", "", "LEVEL_IDENTITY", ref::LEVEL_IDENTITY);
	ClassDB::bind_integer_constant("LbAuditReference", "", "LEVEL_MARGIN", ref::LEVEL_MARGIN);
}

void LbAuditReference::attach(const Ref<LbMine> &mine) {
	mine_ = mine;
}

void LbAuditReference::set_vision_defs(const Dictionary &d) {
	vision_.cone_deg = d.get("cone_deg", vision_.cone_deg);
	vision_.seen_min = thousandths(d.get("seen_min", 0.12));
	vision_.identity_min = thousandths(d.get("identity_min", 0.30));
	vision_.small_min = thousandths(d.get("small_min", 0.30));
	vision_.trail_min = thousandths(d.get("trail_min", 0.12));
	vision_.range = static_cast<int64_t>(static_cast<double>(d.get("range", 40.0)));
	vision_.view_w = d.get("view_w", vision_.view_w);
	vision_.view_h = d.get("view_h", vision_.view_h);
	vision_.squint_lead = d.get("squint_lead", vision_.squint_lead);
	vision_.detail_widen = d.get("detail_widen", vision_.detail_widen);
	vision_.bucket_deg = d.get("bucket_deg", vision_.bucket_deg);
	vision_.margin_geometry = d.get("margin_geometry", vision_.margin_geometry);
	vision_.margin_entity = d.get("margin_entity", vision_.margin_entity);
}

void LbAuditReference::set_light_defs(const Dictionary &d) {
	light_defs_.core_fraction = d.get("core_fraction", light_defs_.core_fraction);
	light_defs_.core_value = d.get("core_value", light_defs_.core_value);
	light_defs_.edge_value = d.get("edge_value", light_defs_.edge_value);
	light_defs_.cap = d.get("cap", light_defs_.cap);
	light_defs_.scale = static_cast<int64_t>(static_cast<double>(d.get("value_scale", 1000.0)));
}

int64_t LbAuditReference::snapshot_light(const Ref<LbLightGrid> &grid, const Array &rects) {
	ERR_FAIL_COND_V(mine_.is_null() || grid.is_null() || grid->core() == nullptr, 0);
	const auto *g = grid->core();
	sources_.clear();
	for (uint32_t id : g->source_ids()) {
		const auto d = g->source(id);
		if (!d) {
			continue;
		}
		ref::Source s;
		s.id = id;
		s.shape = static_cast<uint8_t>(d->shape);
		s.colour = static_cast<uint8_t>(d->colour);
		s.owner = d->owner;
		s.radius = d->radius;
		s.radius_mult = g->radius_mult(id);
		s.peak = d->peak;
		s.end_value = d->end_value;
		s.x = d->x;
		s.y = d->y;
		for (const auto &t : d->tiles) {
			s.tiles.push_back({t.x, t.y});
		}
		s.dir = {d->dir.x, d->dir.y};
		s.spot = {d->spot.x, d->spot.y};
		sources_.push_back(s);
	}
	const auto &map = mine_->map();
	light_.clear();
	for (int64_t i = 0; i < rects.size(); i++) {
		const Rect2i r = rects[i];
		const auto field = ref::light_window(sources_, light_defs_, [&map](ref::Pos p) { return !map.tile_at({p.x, p.y}).has_value() || map.is_opaque({p.x, p.y}); }, [&map](ref::Pos p) { return map.tile_at({p.x, p.y}).has_value(); }, r.position.x, r.position.y, r.position.x + r.size.x - 1, r.position.y + r.size.y - 1);
		light_.insert(field.begin(), field.end());
	}
	return static_cast<int64_t>(light_.size());
}

Dictionary LbAuditReference::evaluate(const Dictionary &observer, const Array &entities) const {
	Dictionary out;
	ERR_FAIL_COND_V(mine_.is_null(), out);
	ref::Observer o;
	o.self = static_cast<uint32_t>(static_cast<int64_t>(observer.get("self", 0)));
	const Vector2 p = observer.get("position", Vector2());
	o.x = p.x;
	o.y = p.y;
	o.facing = static_cast<uint32_t>(static_cast<int64_t>(observer.get("facing", 0)));
	o.blinded = observer.get("blinded", false);
	o.turn_band = observer.get("turn_band", 0.0);
	o.clamp = observer.get("clamp", 0.0);
	const Array bite = observer.get("bite", Array());
	for (int64_t i = 0; i < bite.size(); i++) {
		o.bite.insert(pos_of(bite[i]));
	}
	// The observer's own lights, from the snapshot: point sources it owns with a radius.
	for (const ref::Source &s : sources_) {
		if (s.owner == o.self && o.self != 0 && s.shape == ref::POINT && s.radius * s.radius_mult > 0.0) {
			o.own_lights.push_back({{s.x, s.y}, s.radius * s.radius_mult});
		}
	}
	std::vector<ref::Entity> ents;
	for (int64_t i = 0; i < entities.size(); i++) {
		const Dictionary e = entities[i];
		ref::Entity re;
		re.id = static_cast<uint32_t>(static_cast<int64_t>(e.get("id", 0)));
		re.size = static_cast<uint8_t>(static_cast<int64_t>(e.get("size", 0)));
		re.token_class = static_cast<uint8_t>(static_cast<int64_t>(e.get("token_class", 0)));
		re.footprint = e.get("footprint", 1);
		re.identity_min = thousandths(e.get("identity_min", -1.0));
		const Vector2 ep = e.get("position", Vector2());
		re.x = ep.x;
		re.y = ep.y;
		ents.push_back(re);
	}
	const auto &map = mine_->map();
	const ref::Expected x = ref::evaluate(o, vision_, light_, [&map](ref::Pos q) { return map.is_opaque({q.x, q.y}); }, ents);
	out["blinded"] = x.blinded;
	Dictionary detail;
	for (const auto &[t, l] : x.detail) {
		detail[Vector2i(static_cast<int32_t>(t.x), static_cast<int32_t>(t.y))] = l.value * 16 + l.colour;
	}
	out["detail"] = detail;
	Dictionary margin;
	for (const ref::Pos &t : x.margin) {
		margin[Vector2i(static_cast<int32_t>(t.x), static_cast<int32_t>(t.y))] = true;
	}
	out["margin"] = margin;
	PackedInt32Array glow;
	for (const auto &b : x.glow) {
		glow.push_back(b.first ? b.second : -1);
	}
	out["glow"] = glow;
	Dictionary ents_out;
	for (const auto &[id, lv] : x.entities) {
		ents_out[static_cast<int64_t>(id)] = static_cast<int64_t>(lv.first) * 256 + lv.second;
	}
	out["entities"] = ents_out;
	return out;
}

int64_t LbAuditReference::light_at(Vector2i tile) const {
	auto it = light_.find(pos_of(tile));
	return it == light_.end() ? 0 : it->second.value;
}

bool LbAuditReference::fov_contains(Vector2i from, int64_t range, Vector2i tile) const {
	ERR_FAIL_COND_V(mine_.is_null(), false);
	const auto &map = mine_->map();
	const auto fov = ref::symmetric_fov(pos_of(from), range, [&map](ref::Pos q) { return map.is_opaque({q.x, q.y}); });
	return fov.count(pos_of(tile)) != 0;
}

double LbAuditReference::reach_cost(const Array &origins, Vector2i to, double max_cost, bool voice, double closed_cost) const {
	ERR_FAIL_COND_V(mine_.is_null(), -1.0);
	const auto &map = mine_->map();
	std::vector<ref::Pos> from;
	for (int64_t i = 0; i < origins.size(); i++) {
		from.push_back(pos_of(origins[i]));
	}
	return ref::reach_cost(from, pos_of(to), max_cost, voice, closed_cost, [&map](ref::Pos p) -> uint8_t {
		const lb::core::world::Coord c{p.x, p.y};
		if (map.is_walkable(c)) {
			return ref::OPEN;
		}
		const auto t = map.tile_at(c);
		if (t && (t->material == static_cast<uint8_t>(lb::core::world::TileMaterial::STEEL) || t->material == static_cast<uint8_t>(lb::core::world::TileMaterial::WOODEN_DOOR))) {
			return ref::PORTAL_CLOSED;
		}
		return ref::SOLID;
	});
}

Dictionary LbAuditReference::straight_line(Vector2i from, Vector2i to) const {
	Dictionary out;
	ERR_FAIL_COND_V(mine_.is_null(), out);
	const auto &map = mine_->map();
	auto material = [&map](ref::Pos p) {
		const auto t = map.tile_at({p.x, p.y});
		return t ? static_cast<lb::core::world::TileMaterial>(t->material) : lb::core::world::TileMaterial::ROCK;
	};
	const ref::Line l = ref::straight_line(pos_of(from), pos_of(to), [&map](ref::Pos p) { return map.is_solid({p.x, p.y}); }, [&material](ref::Pos p) { return material(p) == lb::core::world::TileMaterial::BRICK; }, [&material](ref::Pos p) {
				const auto m = material(p);
				return m == lb::core::world::TileMaterial::STEEL || m == lb::core::world::TileMaterial::WOODEN_DOOR; });
	out["solid"] = l.solid;
	out["brick"] = l.brick;
	out["door"] = l.door;
	out["distance"] = l.distance;
	return out;
}

} // namespace lb::godot

#endif

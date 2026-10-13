#include "godot/vision/lb_vision.h"

#include <cmath>

#include "core/sim/entity_mirror.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>

using namespace godot;
using lb::core::world::Coord;
namespace vision = lb::core::vision;

namespace lb::godot {

#define REQUIRE_VISION(ret) ERR_FAIL_NULL_V_MSG(vision_, ret, "LbVision: attach() a mine and a light grid first")

void LbVision::_bind_methods() {
	ClassDB::bind_method(D_METHOD("attach", "mine", "light"), &LbVision::attach);
	ClassDB::bind_method(D_METHOD("set_params", "params"), &LbVision::set_params);
	ClassDB::bind_method(D_METHOD("set_perception_class", "kind", "size_class", "footprint", "identity_min", "motionless_always"), &LbVision::set_perception_class);
	ClassDB::bind_method(D_METHOD("set_motionless_flag", "flag"), &LbVision::set_motionless_flag);
	ClassDB::bind_method(D_METHOD("set_observer", "id", "self", "position", "facing"), &LbVision::set_observer);
	ClassDB::bind_method(D_METHOD("remove_observer", "id"), &LbVision::remove_observer);
	ClassDB::bind_method(D_METHOD("set_blinded", "id", "on"), &LbVision::set_blinded);
	ClassDB::bind_method(D_METHOD("lit_in_sight", "from", "range", "min_light", "excluded"), &LbVision::lit_in_sight);
	ClassDB::bind_method(D_METHOD("set_radius_clamp", "id", "tiles"), &LbVision::set_radius_clamp);
	ClassDB::bind_method(D_METHOD("set_bite_tiles", "id", "tiles"), &LbVision::set_bite_tiles);
	ClassDB::bind_method(D_METHOD("set_identity_threshold", "entity", "light"), &LbVision::set_identity_threshold);
	ClassDB::bind_method(D_METHOD("set_decals", "tile", "bits"), &LbVision::set_decals);
	ClassDB::bind_method(D_METHOD("set_shadow_params", "params"), &LbVision::set_shadow_params);
	ClassDB::bind_method(D_METHOD("update_shadows"), &LbVision::update_shadows);
	ClassDB::bind_method(D_METHOD("shade_at", "tile"), &LbVision::shade_at);
	ClassDB::bind_method(D_METHOD("on_tiles_changed", "cell", "rect", "reason"), &LbVision::on_tiles_changed);
	ClassDB::bind_method(D_METHOD("compute", "id"), &LbVision::compute);
	ClassDB::bind_method(D_METHOD("in_cone", "id", "point"), &LbVision::in_cone);
	ClassDB::bind_method(D_METHOD("tile_seen", "id", "tile"), &LbVision::tile_seen);
	ClassDB::bind_method(D_METHOD("sees_entity", "id", "entity"), &LbVision::sees_entity);
	ClassDB::bind_method(D_METHOD("seen_entities", "id"), &LbVision::seen_entities);
	ClassDB::bind_method(D_METHOD("unseen_reason", "id", "entity"), &LbVision::unseen_reason);
	ClassDB::bind_method(D_METHOD("is_seen_by_any", "tile"), &LbVision::is_seen_by_any);
	ClassDB::bind_method(D_METHOD("is_seen_or_margin_of_any", "tile"), &LbVision::is_seen_or_margin_of_any);
	ClassDB::bind_method(D_METHOD("margin_band", "id", "tile"), &LbVision::margin_band);
	ClassDB::bind_method(D_METHOD("detail_rect", "id"), &LbVision::detail_rect);
	ClassDB::bind_method(D_METHOD("glow_bucket", "id", "point"), &LbVision::glow_bucket);
	ClassDB::bind_method(D_METHOD("recasts"), &LbVision::recasts);
	ClassDB::bind_method(D_METHOD("margin_nanos"), &LbVision::margin_nanos);
	ClassDB::bind_integer_constant("LbVision", "", "SIZE_NONE", 0);
	ClassDB::bind_integer_constant("LbVision", "", "SIZE_MINER", 1);
	ClassDB::bind_integer_constant("LbVision", "", "SIZE_LARGE", 2);
	ClassDB::bind_integer_constant("LbVision", "", "SIZE_LARGE_MOTIONLESS", 3);
	ClassDB::bind_integer_constant("LbVision", "", "SIZE_SMALL", 4);
	ClassDB::bind_integer_constant("LbVision", "", "LEVEL_NONE", 0);
	ClassDB::bind_integer_constant("LbVision", "", "LEVEL_TOKEN", 1);
	ClassDB::bind_integer_constant("LbVision", "", "LEVEL_IDENTITY", 2);
	ClassDB::bind_integer_constant("LbVision", "", "UNSEEN_SEEN", 0);
	ClassDB::bind_integer_constant("LbVision", "", "UNSEEN_DARK", 1);
	ClassDB::bind_integer_constant("LbVision", "", "UNSEEN_OUTSIDE_CONE", 2);
	ClassDB::bind_integer_constant("LbVision", "", "UNSEEN_BITE", 3);
	ClassDB::bind_integer_constant("LbVision", "", "UNSEEN_NO_LOS", 4);
	ClassDB::bind_integer_constant("LbVision", "", "UNSEEN_BEYOND_RANGE", 5);
	ClassDB::bind_integer_constant("LbVision", "", "UNSEEN_BLINDED", 6);
	ClassDB::bind_integer_constant("LbVision", "", "UNSEEN_UNKNOWN", 7);
	ClassDB::bind_integer_constant("LbVision", "", "DECAL_BLOOD", 1);
	ClassDB::bind_integer_constant("LbVision", "", "DECAL_CHALK", 2);
	ClassDB::bind_integer_constant("LbVision", "", "DECAL_LINE_NUMBER", 4);
}

void LbVision::attach(const Ref<LbMine> &mine, const Ref<LbLightGrid> &light) {
	ERR_FAIL_COND(mine.is_null() || light.is_null() || light->core() == nullptr);
	mine_ = mine;
	light_ = light;
	vision_ = std::make_unique<vision::Vision>(mine_->map(), *light_->core());
}

static int64_t thousandths(double light) {
	return static_cast<int64_t>(light * 1000.0 + 0.5);
}

void LbVision::set_params(const Dictionary &d) {
	REQUIRE_VISION();
	vision::VisionParams &p = vision_->params;
	p.cone_deg = d.get("cone_deg", p.cone_deg);
	p.seen_min = thousandths(d.get("seen_min", p.seen_min / 1000.0));
	p.identity_min = thousandths(d.get("identity_min", p.identity_min / 1000.0));
	p.small_min = thousandths(d.get("small_min", p.small_min / 1000.0));
	p.trail_min = thousandths(d.get("trail_min", p.trail_min / 1000.0));
	p.range = static_cast<int64_t>(static_cast<double>(d.get("range", static_cast<double>(p.range))) + 0.5);
	p.view_w = d.get("view_w", p.view_w);
	p.view_h = d.get("view_h", p.view_h);
	p.squint_lead = d.get("squint_lead", p.squint_lead);
	p.detail_widen = d.get("detail_widen", p.detail_widen);
	p.bucket_deg = d.get("bucket_deg", p.bucket_deg);
	p.margin_geometry = d.get("margin_geometry", p.margin_geometry);
	p.margin_entity = d.get("margin_entity", p.margin_entity);
}

void LbVision::set_perception_class(int64_t kind, int64_t size_class, int64_t footprint, double identity_min, bool motionless_always) {
	REQUIRE_VISION();
	vision::PerceptionClass c;
	c.size = static_cast<vision::SizeClass>(size_class);
	c.footprint = footprint;
	c.identity_min = identity_min < 0.0 ? -1 : thousandths(identity_min);
	c.motionless_always = motionless_always;
	vision_->table.set(static_cast<uint16_t>(kind), c);
}

void LbVision::set_motionless_flag(int64_t flag) {
	REQUIRE_VISION();
	vision_->table.motionless_flag = static_cast<uint32_t>(flag);
}

void LbVision::set_observer(int64_t id, int64_t self, Vector2 position, int64_t facing) {
	REQUIRE_VISION();
	vision_->set_observer(static_cast<uint32_t>(id), static_cast<uint32_t>(self), position.x, position.y, static_cast<uint32_t>(facing));
}

void LbVision::remove_observer(int64_t id) {
	REQUIRE_VISION();
	vision_->remove_observer(static_cast<uint32_t>(id));
}

void LbVision::set_blinded(int64_t id, bool on) {
	REQUIRE_VISION();
	vision_->set_blinded(static_cast<uint32_t>(id), on);
}

PackedInt64Array LbVision::lit_in_sight(Vector2i from, double range, double min_light, const PackedInt64Array &excluded) const {
	PackedInt64Array out;
	if (!vision_) {
		return out;
	}
	std::vector<uint32_t> ex;
	for (int64_t i = 0; i < excluded.size(); i++) {
		ex.push_back(static_cast<uint32_t>(excluded[i]));
	}
	for (const auto &t : vision_->lit_in_sight({from.x, from.y}, range, static_cast<int64_t>(std::llround(min_light * 1000.0)), ex)) {
		out.push_back(t.tile.x);
		out.push_back(t.tile.y);
		out.push_back(t.value);
		out.push_back(static_cast<int64_t>(t.source));
		out.push_back(static_cast<int64_t>(t.colour));
	}
	return out;
}

void LbVision::set_radius_clamp(int64_t id, double tiles) {
	REQUIRE_VISION();
	vision_->set_radius_clamp(static_cast<uint32_t>(id), tiles);
}

void LbVision::set_bite_tiles(int64_t id, const Array &tiles) {
	REQUIRE_VISION();
	std::set<Coord> set;
	for (int64_t i = 0; i < tiles.size(); i++) {
		const Vector2i t = tiles[i];
		set.insert(Coord{t.x, t.y});
	}
	vision_->set_bite_tiles(static_cast<uint32_t>(id), std::move(set));
}

void LbVision::set_identity_threshold(int64_t entity, double light) {
	REQUIRE_VISION();
	vision_->set_identity_threshold(static_cast<uint32_t>(entity), light < 0.0 ? -1 : thousandths(light));
}

void LbVision::set_decals(Vector2i tile, int64_t bits) {
	REQUIRE_VISION();
	vision_->set_decals(Coord{tile.x, tile.y}, static_cast<uint8_t>(bits));
}

void LbVision::on_tiles_changed(Vector2i, Rect2i rect, const String &) {
	REQUIRE_VISION();
	vision_->on_tiles_changed(rect.position.x, rect.position.y, rect.position.x + rect.size.x - 1, rect.position.y + rect.size.y - 1);
}

void LbVision::set_shadow_params(const Dictionary &d) {
	REQUIRE_VISION();
	vision::ShadowParams &p = vision_->shadow;
	p.enabled = d.get("enabled", p.enabled);
	p.min_light = static_cast<int64_t>(std::llround(static_cast<double>(d.get("min_light", p.min_light / 1000.0)) * 1000.0));
	p.lit_min = static_cast<int64_t>(std::llround(static_cast<double>(d.get("lit_min", p.lit_min / 1000.0)) * 1000.0));
	p.levels = static_cast<int>(static_cast<int64_t>(d.get("levels", static_cast<int64_t>(p.levels))));
	p.width = d.get("width", p.width);
	if (d.has("never_cast")) {
		p.never_cast.clear();
		const Array kinds = d["never_cast"];
		for (int64_t i = 0; i < kinds.size(); i++) {
			p.never_cast.insert(static_cast<uint16_t>(static_cast<int64_t>(kinds[i])));
		}
	}
}

void LbVision::update_shadows() {
	REQUIRE_VISION();
	vision_->update_shadows(lb::core::sim::EntityMirror::current().entities());
}

int64_t LbVision::shade_at(Vector2i tile) const {
	REQUIRE_VISION(0);
	return vision_->shade_at(Coord{tile.x, tile.y});
}

Dictionary LbVision::compute(int64_t id) {
	Dictionary out;
	REQUIRE_VISION(out);
	const vision::PerceptionFrame f = vision_->compute(static_cast<uint32_t>(id), lb::core::sim::EntityMirror::current().entities());
	PackedInt32Array xs, ys;
	PackedByteArray lights, colours, decals;
	for (const vision::FrameTile &t : f.tiles) {
		xs.push_back(static_cast<int32_t>(t.tile.x));
		ys.push_back(static_cast<int32_t>(t.tile.y));
		lights.push_back(t.light);
		colours.push_back(t.colour);
		decals.push_back(t.decals);
	}
	Dictionary tiles;
	tiles["x"] = xs;
	tiles["y"] = ys;
	tiles["light"] = lights;
	tiles["colour"] = colours;
	tiles["decals"] = decals;
	PackedByteArray sizes;
	PackedVector2Array positions;
	for (const vision::FrameToken &t : f.tokens) {
		sizes.push_back(static_cast<uint8_t>(t.size));
		positions.push_back(Vector2(static_cast<real_t>(t.x), static_cast<real_t>(t.y)));
	}
	Dictionary tokens;
	tokens["size"] = sizes;
	tokens["position"] = positions;
	PackedInt64Array identified;
	for (uint32_t e : f.identified) {
		identified.push_back(e);
	}
	PackedByteArray glow_present, glow_colour;
	for (const vision::GlowBucket &g : f.glow) {
		glow_present.push_back(g.present ? 1 : 0);
		glow_colour.push_back(g.colour);
	}
	out["tiles"] = tiles;
	out["tokens"] = tokens;
	out["identified"] = identified;
	out["glow_present"] = glow_present;
	out["glow_colour"] = glow_colour;
	PackedInt32Array mx, my;
	for (const Coord &t : f.margin_tiles) {
		mx.push_back(static_cast<int32_t>(t.x));
		my.push_back(static_cast<int32_t>(t.y));
	}
	Dictionary margin;
	margin["x"] = mx;
	margin["y"] = my;
	PackedByteArray msizes;
	PackedVector2Array mpositions;
	for (const vision::FrameToken &t : f.margin_tokens) {
		msizes.push_back(static_cast<uint8_t>(t.size));
		mpositions.push_back(Vector2(static_cast<real_t>(t.x), static_cast<real_t>(t.y)));
	}
	Dictionary mtokens;
	mtokens["size"] = msizes;
	mtokens["position"] = mpositions;
	out["margin_tiles"] = margin;
	out["margin_tokens"] = mtokens;
	out["blinded"] = f.blinded;
	return out;
}

bool LbVision::in_cone(int64_t id, Vector2 point) const {
	REQUIRE_VISION(false);
	return vision_->in_cone(static_cast<uint32_t>(id), point.x, point.y);
}

bool LbVision::tile_seen(int64_t id, Vector2i tile) {
	REQUIRE_VISION(false);
	return vision_->tile_seen(static_cast<uint32_t>(id), Coord{tile.x, tile.y});
}

int64_t LbVision::sees_entity(int64_t id, int64_t entity) {
	REQUIRE_VISION(0);
	auto e = lb::core::sim::EntityMirror::current().find(static_cast<uint32_t>(entity));
	return e ? static_cast<int64_t>(vision_->sees_entity(static_cast<uint32_t>(id), *e)) : 0;
}

Array LbVision::seen_entities(int64_t id) {
	Array out;
	REQUIRE_VISION(out);
	for (const lb::core::sim::MirrorEntity &e : lb::core::sim::EntityMirror::current().entities()) {
		const vision::Level level = vision_->sees_entity(static_cast<uint32_t>(id), e);
		if (level != vision::Level::NONE) {
			Array pair;
			pair.push_back(static_cast<int64_t>(e.id));
			pair.push_back(static_cast<int64_t>(level));
			out.push_back(pair);
		}
	}
	return out;
}

int64_t LbVision::unseen_reason(int64_t id, int64_t entity) {
	REQUIRE_VISION(7);
	auto e = lb::core::sim::EntityMirror::current().find(static_cast<uint32_t>(entity));
	return e ? static_cast<int64_t>(vision_->unseen_reason(static_cast<uint32_t>(id), *e)) : 7;
}

bool LbVision::is_seen_or_margin_of_any(Vector2i tile) {
	REQUIRE_VISION(false);
	return vision_->is_seen_or_margin_of_any(Coord{tile.x, tile.y});
}

int64_t LbVision::margin_band(int64_t id, Vector2i tile) {
	REQUIRE_VISION(0);
	return vision_->margin_band(static_cast<uint32_t>(id), Coord{tile.x, tile.y});
}

bool LbVision::is_seen_by_any(Vector2i tile) {
	REQUIRE_VISION(false);
	return vision_->is_seen_by_any(Coord{tile.x, tile.y});
}

Rect2 LbVision::detail_rect(int64_t id) const {
	REQUIRE_VISION(Rect2());
	const std::array<double, 4> r = vision_->detail_rect(static_cast<uint32_t>(id));
	return Rect2(static_cast<real_t>(r[0]), static_cast<real_t>(r[1]), static_cast<real_t>(r[2] - r[0]), static_cast<real_t>(r[3] - r[1]));
}

int64_t LbVision::glow_bucket(int64_t id, Vector2 point) const {
	REQUIRE_VISION(-1);
	return vision_->glow_bucket(static_cast<uint32_t>(id), point.x, point.y);
}

int64_t LbVision::recasts() const {
	REQUIRE_VISION(0);
	return static_cast<int64_t>(vision_->recasts());
}

int64_t LbVision::margin_nanos() const {
	REQUIRE_VISION(0);
	return vision_->margin_nanos();
}

} // namespace lb::godot

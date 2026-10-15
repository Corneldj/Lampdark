#pragma once
// GDScript face of core/vision (VIS-03): per-miner seen sets and the vision queries. Attach a
// mine and a light grid; entities come from NET-01's entity mirror. Server-only.

#include "core/vision/seen_set.h"
#include "godot/light/lb_light.h"
#include "godot/world/lb_mine.h"

#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>

#include <memory>

namespace lb::godot {

class LbVision : public ::godot::RefCounted {
	GDCLASS(LbVision, ::godot::RefCounted)

protected:
	static void _bind_methods();

public:
	void attach(const ::godot::Ref<LbMine> &mine, const ::godot::Ref<LbLightGrid> &light);
	// Keys: cone_deg, seen_min, identity_min, small_min, trail_min (light 0-1), range, view_w,
	// view_h, squint_lead, detail_widen, bucket_deg.
	void set_params(const ::godot::Dictionary &params);
	void set_perception_class(int64_t kind, int64_t size_class, int64_t footprint, double identity_min, bool motionless_always);
	void set_motionless_flag(int64_t flag);

	void set_observer(int64_t id, int64_t self, ::godot::Vector2 position, int64_t facing);
	void remove_observer(int64_t id);
	void set_blinded(int64_t id, bool on);
	// CRT-04: the awake Moth\'s sight, flattened [x, y, value (thousandths), source, colour] per tile.
	::godot::PackedInt64Array lit_in_sight(::godot::Vector2i from, double range, double min_light, const ::godot::PackedInt64Array &excluded) const;
	void set_radius_clamp(int64_t id, double tiles);
	void set_bite_tiles(int64_t id, const ::godot::Array &tiles);
	// VIS-10: the bite round a point (core/vision/bite.h), as tiles; and whether the last frame left
	// out a bitten tile the observer would have seen.
	::godot::Array bite_tiles(::godot::Vector2 at, int64_t range, double below) const;
	bool bite_seen(int64_t id) const;
	void set_identity_threshold(int64_t entity, double light);
	void set_decals(::godot::Vector2i tile, int64_t bits);
	// VIS-09: {enabled, min_light (0-1), lit_min (0-1), levels, width, never_cast: [kinds]}.
	void set_shadow_params(const ::godot::Dictionary &d);
	void update_shadows();
	void set_turn_band(int64_t id, double degrees);
	int64_t shade_at(::godot::Vector2i tile) const;
	void on_tiles_changed(::godot::Vector2i cell, ::godot::Rect2i rect, const ::godot::String &reason);

	// {tiles: {x, y, light, colour, decals}, tokens: {size, position}, identified, glow_present,
	// glow_colour, margin_tiles: {x, y}, margin_tokens: {size, position}, blinded}
	::godot::Dictionary compute(int64_t id);
	bool in_cone(int64_t id, ::godot::Vector2 point) const;
	bool tile_seen(int64_t id, ::godot::Vector2i tile);
	int64_t sees_entity(int64_t id, int64_t entity);
	// [[entity id, level], ...] for every entity the observer sees, ascending.
	::godot::Array seen_entities(int64_t id);
	int64_t unseen_reason(int64_t id, int64_t entity);
	bool is_seen_by_any(::godot::Vector2i tile);
	bool is_seen_or_margin_of_any(::godot::Vector2i tile);
	int64_t margin_band(int64_t id, ::godot::Vector2i tile);
	::godot::Rect2 detail_rect(int64_t id) const;
	int64_t glow_bucket(int64_t id, ::godot::Vector2 point) const;
	int64_t recasts() const;
	int64_t margin_nanos() const;
	// The core vision, for NET-04's replication; null before attach().
	lb::core::vision::Vision *core() { return vision_.get(); }

private:
	::godot::Ref<LbMine> mine_;
	::godot::Ref<LbLightGrid> light_;
	std::unique_ptr<lb::core::vision::Vision> vision_;
};

} // namespace lb::godot

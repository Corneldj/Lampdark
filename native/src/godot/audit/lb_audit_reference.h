#pragma once
// GDScript face of NET-08's reference visibility (audit/reference_vis.h), for the stream audit
// (tools/stream_audit/). Dev and QA builds only: compiled with LB_DEBUG_TOOLS, never registered in
// a release library (check_debug_tools.sh holds it to that). It reads the mine's geometry and the
// light grid's source descriptions as data; every value it returns is its own computation.

#ifdef LB_DEBUG_TOOLS

#include "audit/reference_reach.h"
#include "audit/reference_vis.h"
#include "godot/light/lb_light.h"
#include "godot/world/lb_mine.h"

#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>

#include <map>
#include <vector>

namespace lb::godot {

class LbAuditReference : public ::godot::RefCounted {
	GDCLASS(LbAuditReference, ::godot::RefCounted)

protected:
	static void _bind_methods();

public:
	void attach(const ::godot::Ref<LbMine> &mine);
	// Keys as VisionSystem's (light values 0-1): cone_deg, seen_min, identity_min, small_min,
	// trail_min, range, view_w, view_h, squint_lead, detail_widen, bucket_deg, margin_geometry,
	// margin_entity.
	void set_vision_defs(const ::godot::Dictionary &defs);
	// core_fraction, core_value, edge_value, cap, value_scale.
	void set_light_defs(const ::godot::Dictionary &defs);
	// The grid's sources as they stand (call when the grid was last summed), and the light the
	// reference computes from them over each rectangle. Returns the number of lit tiles.
	int64_t snapshot_light(const ::godot::Ref<LbLightGrid> &grid, const ::godot::Array &rects);
	// One observer: {self, position, facing, blinded, turn_band, clamp, bite: [Vector2i]}; entities:
	// [{id, size, token_class, footprint, identity_min (0-1, or -1), position}]. Returns {blinded,
	// detail: {Vector2i: value * 16 + colour} (seen tiles in the detail rectangle),
	// margin: {Vector2i: true}, glow: PackedInt32Array (-1 none, else the colour class),
	// entities: {id: level * 256 + class}}.
	::godot::Dictionary evaluate(const ::godot::Dictionary &observer, const ::godot::Array &entities) const;
	// The light the reference computed for a tile (thousandths), and whether it is in sight of a
	// point within a range (tests, and the audit's voice and event rules).
	int64_t light_at(::godot::Vector2i tile) const;
	bool fov_contains(::godot::Vector2i from, int64_t range, ::godot::Vector2i tile) const;
	// The cheapest reach from any origin tile to `to` (-1 if none within max_cost): a step to any of
	// eight neighbours costs 1, a closed door or shut gate closed_cost more, or stops voice.
	double reach_cost(const ::godot::Array &origins, ::godot::Vector2i to, double max_cost, bool voice, double closed_cost) const;
	// The straight line between two tile centres: {solid, brick, door, distance}.
	::godot::Dictionary straight_line(::godot::Vector2i from, ::godot::Vector2i to) const;

private:
	::godot::Ref<LbMine> mine_;
	lb::audit::VisionDefs vision_;
	lb::audit::LightDefs light_defs_;
	std::vector<lb::audit::Source> sources_;
	std::map<lb::audit::Pos, lb::audit::TileLight> light_;
};

} // namespace lb::godot

#endif

#pragma once
// GDScript face of core/sound's Road Graph (SND-01). Server-only. Deliveries returned here
// include true_source, which SND-03's client record must never carry.

#include "core/sound/road_graph.h"
#include "godot/world/lb_mine.h"

#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>

#include <memory>

namespace lb::godot {

class LbRoadGraph : public ::godot::RefCounted {
	GDCLASS(LbRoadGraph, ::godot::RefCounted)

protected:
	static void _bind_methods();

public:
	void attach(const ::godot::Ref<LbMine> &mine);
	void set_params(double closed_cost, double jitter_per_tile, double search_cap_air, int64_t run_seed);

	// Builds a committed cell's tables from its own Road Graph block (GEN-01 cell data).
	bool stitch(::godot::Vector2i cell);
	bool unload(::godot::Vector2i cell);
	void on_tiles_changed(::godot::Vector2i cell, ::godot::Rect2i rect, const ::godot::String &reason);
	bool is_stitched(::godot::Vector2i cell) const;
	int64_t epoch() const;

	void set_listener(int64_t id, ::godot::Vector2i tile, double threshold, double multiplier);
	void remove_listener(int64_t id);
	// MODE_AIR or MODE_VOICE. Array of delivery Dictionaries, sorted by listener id.
	::godot::Array propagate(int64_t event_id, const ::godot::Array &origins, double level, int64_t mode);
	// One delivery from outside the graph (illusions); {} when inaudible.
	::godot::Dictionary deliver(::godot::Vector2i source, double level, ::godot::Vector2i listener_tile, int64_t mode,
			double threshold, double multiplier, int64_t key) const;
	// -1 when unreachable within max.
	double path_cost(::godot::Vector2i a, ::godot::Vector2i b, int64_t mode, double max) const;
	::godot::Dictionary nearest_open_tile(::godot::Vector2i rock_tile, int64_t max_radius) const;
	::godot::Dictionary rock_line(::godot::Vector2i from, ::godot::Vector2i to) const;
	int64_t tables_digest() const;

	// Validates a block against a committed cell: a list of problems, empty when valid.
	::godot::PackedStringArray validate(::godot::Vector2i cell) const;

private:
	::godot::Ref<LbMine> mine_;
	std::unique_ptr<lb::core::sound::RoadGraph> graph_;
};

} // namespace lb::godot

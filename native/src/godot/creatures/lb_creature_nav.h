#pragma once
// GDScript face of core/creatures/creature_nav (CRT-02). Attach a mine and (optionally) a light
// grid; parameters arrive as a Dictionary per call over the defaults set_defaults gave. Paths
// come back as {tiles: Array[Vector2i], cost (tiles), found, hit_limit, touched_unloaded,
// expansions}. Server-only.

#include "core/creatures/creature_nav.h"
#include "godot/light/lb_light.h"
#include "godot/world/lb_mine.h"

#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/typed_array.hpp>

#include <memory>

namespace lb::godot {

class LbCreatureNav : public ::godot::RefCounted {
	GDCLASS(LbCreatureNav, ::godot::RefCounted)

protected:
	static void _bind_methods();

public:
	enum Mode { WALKER = 0, CRAWLER = 1, DARK = 2, ROCK = 3 };

	void attach(const ::godot::Ref<LbMine> &mine, const ::godot::Ref<LbLightGrid> &light);
	// Keys: dark_threshold (0-1), max_tiles, max_expansions, crawl_open_cost, rock_crosses_floor,
	// brick_clearance.
	void set_defaults(const ::godot::Dictionary &params);

	bool passable(int64_t mode, ::godot::Vector2i tile, const ::godot::Dictionary &params) const;
	bool wall_adjacent(::godot::Vector2i tile) const;
	::godot::Dictionary path(int64_t mode, ::godot::Vector2i from, ::godot::Vector2i to, const ::godot::Dictionary &params) const;
	::godot::Dictionary path_to_any(int64_t mode, ::godot::Vector2i from, const ::godot::TypedArray<::godot::Vector2i> &goals, const ::godot::Dictionary &params) const;
	bool still_valid(int64_t mode, const ::godot::TypedArray<::godot::Vector2i> &tiles, const ::godot::Dictionary &params) const;
	::godot::Variant nearest_dark_tile(::godot::Vector2 point, double threshold, int64_t max_radius) const;
	::godot::Variant reachable_dark_tile_nearest(::godot::Vector2i target, ::godot::Vector2i from, const ::godot::Dictionary &params) const;
	::godot::TypedArray<::godot::Vector2i> light_edge_ring(::godot::Vector2i seed, double threshold, int64_t max_tiles) const;
	::godot::TypedArray<::godot::Vector2i> usable_faces_within(::godot::Vector2 point, double r) const;
	::godot::Variant nearest_usable_face(::godot::Vector2 point, int64_t max_radius) const;
	::godot::Variant rock_tile_behind(::godot::Vector2i tile) const;
	::godot::Dictionary moth_path_within(::godot::Vector2i from, ::godot::Vector2 miner, double max_tiles, int64_t max_expansions) const;
	::godot::Dictionary tapper_rock_path_within(::godot::Vector2i from, ::godot::Vector2 miner, double max_tiles, double reach, const ::godot::Dictionary &params) const;
	::godot::Dictionary stythe_dark_path_within(::godot::Vector2i from, ::godot::Vector2 miner, double max_tiles, double within, const ::godot::Dictionary &params) const;

private:
	::godot::Ref<LbMine> mine_;
	::godot::Ref<LbLightGrid> light_;
	std::unique_ptr<lb::core::creatures::CreatureNav> nav_;
	lb::core::creatures::NavParams defaults_;

	lb::core::creatures::NavParams merged(const ::godot::Dictionary &params) const;
};

} // namespace lb::godot

VARIANT_ENUM_CAST(lb::godot::LbCreatureNav::Mode);

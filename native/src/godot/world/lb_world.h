#pragma once
// GDScript face of core/world (FND-07): coordinates, rings and entity IDs.

#include "core/world/entity_id.h"

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <godot_cpp/variant/vector2i.hpp>

namespace lb::godot {

class LbWorld : public ::godot::RefCounted {
	GDCLASS(LbWorld, ::godot::RefCounted)

protected:
	static void _bind_methods();

public:
	static ::godot::Vector2i cell_of(::godot::Vector2i tile);
	static ::godot::Vector2i local_of(::godot::Vector2i tile);
	static ::godot::Vector2i tile_of(::godot::Vector2i cell, ::godot::Vector2i local);
	static ::godot::Vector2i block_of_cell(::godot::Vector2i cell);
	static ::godot::Vector2i region_of_cell(::godot::Vector2i cell);
	static int64_t cell_chebyshev(::godot::Vector2i a, ::godot::Vector2i b);
	static int64_t cell_manhattan(::godot::Vector2i a, ::godot::Vector2i b);
	// Rings by depth.ring_start_tiles from the tuning mirror; -1 with an error if unloaded.
	static int64_t ring_of_tile(::godot::Vector2i tile);
	static int64_t ring_of_point(double x, double y);
	// Rings by explicit bounds, for tools and tests.
	static int64_t ring_of_tile_with(::godot::Vector2i tile, const ::godot::PackedInt64Array &bounds);
	static int64_t ring_of_point_with(double x, double y, const ::godot::PackedInt64Array &bounds);
};

class LbEntityIds : public ::godot::RefCounted {
	GDCLASS(LbEntityIds, ::godot::RefCounted)

protected:
	static void _bind_methods();

public:
	// The next ID (from 1, never reused); 0 with an error once the run's IDs are spent.
	int64_t allocate();
	int64_t get_next() const;
	void restore(int64_t next);

private:
	lb::core::world::EntityIdAllocator ids_;
};

} // namespace lb::godot

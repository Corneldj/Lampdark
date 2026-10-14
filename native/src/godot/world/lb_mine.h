#pragma once
// GDScript faces of core/world's mine (GEN-01). Server-only: no cell data, anchor or material
// table ever goes to a client.

#include "core/world/mine_map.h"

#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/rect2i.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector2i.hpp>

#include <memory>

namespace lb::godot {

// A cell under construction (a fixed file, a template, GEN-11's worker output). Safe to build
// on a worker thread; LbMine.commit() moves its contents into the mine.
class LbCellData : public ::godot::RefCounted {
	GDCLASS(LbCellData, ::godot::RefCounted)

protected:
	static void _bind_methods();

public:
	LbCellData();

	void set_coord(::godot::Vector2i cell);
	::godot::Vector2i get_coord() const;
	void set_tile(::godot::Vector2i local, int64_t material, int64_t state, int64_t zone);
	::godot::Dictionary get_tile(::godot::Vector2i local) const;
	// Returns false for an unknown anchor type name.
	bool add_anchor(const ::godot::String &type, ::godot::Vector2i at, ::godot::Vector2i size,
			const ::godot::PackedStringArray &tags, const ::godot::String &kind);
	void add_barrier(int64_t id, int64_t portal, const ::godot::PackedInt32Array &local_indices, bool open);
	void add_collapse(int64_t id, const ::godot::PackedInt32Array &standing_indices, const ::godot::PackedByteArray &standing_materials,
			const ::godot::PackedInt32Array &fallen_indices, const ::godot::PackedByteArray &fallen_materials, bool is_fallen);
	void set_road_graph(const ::godot::PackedByteArray &bytes);
	::godot::Array get_anchors() const;
	::godot::Array get_barriers() const;
	::godot::Array get_collapses() const;
	::godot::PackedByteArray get_road_graph() const;
	int64_t digest() const;

	std::unique_ptr<lb::core::world::Cell> take();
	bool is_taken() const { return cell_ == nullptr; }

private:
	std::unique_ptr<lb::core::world::Cell> cell_;
};

class LbMine : public ::godot::RefCounted {
	GDCLASS(LbMine, ::godot::RefCounted)

protected:
	static void _bind_methods();

public:
	// name -> {solid, opaque, tapper_moves, tapper_face, voice_crosses, taps_cross, caption_key}
	bool set_material_table(const ::godot::Dictionary &table);
	void set_path_costs(int64_t orthogonal_milli, int64_t diagonal_milli);

	bool commit(const ::godot::Ref<LbCellData> &data);
	bool unload(::godot::Vector2i cell);
	bool is_loaded(::godot::Vector2i cell) const;
	::godot::Array loaded_cells() const;

	int64_t material_at(::godot::Vector2i tile) const;
	int64_t state_at(::godot::Vector2i tile) const;
	// SND-01's zone id of a tile (0: none, or not loaded), for GEN-03's validation.
	int64_t zone_at(::godot::Vector2i tile) const;
	int64_t effective_material(::godot::Vector2i tile) const;
	bool is_walkable(::godot::Vector2i tile, bool doors_open) const;
	bool is_solid(::godot::Vector2i tile) const;
	bool is_opaque(::godot::Vector2i tile) const;
	bool tapper_face_usable(::godot::Vector2i tile) const;
	// Thousandths of a tile; -1 beyond the field's reach.
	int64_t strike_milli(::godot::Vector2i tile) const;
	int64_t depth_milli(::godot::Vector2i tile) const;
	int64_t thickness(::godot::Vector2i tile) const;

	bool set_barrier(::godot::Vector2i cell, int64_t barrier_id, bool open);
	bool set_collapse(::godot::Vector2i cell, int64_t collapse_id, bool fallen);

	// {distance_milli (-1 if unreachable), touched_unloaded, hit_max}
	::godot::Dictionary path_distance(::godot::Vector2i from, ::godot::Vector2i to, int64_t max_milli, bool doors_open) const;
	int64_t flood_count(::godot::Vector2i from, int64_t max_milli, bool doors_open) const;
	// {found, tile}
	::godot::Dictionary nearest_open_tile(::godot::Vector2 point, const ::godot::Array &exclude, int64_t max_radius) const;

	int64_t digest(::godot::Vector2i cell) const;
	::godot::Array anchors(::godot::Vector2i cell) const;
	// GEN-15: a loaded cell's barriers: [{id, portal, open, material (of the tiles), tiles (world)}].
	::godot::Array barriers(::godot::Vector2i cell) const;

	// For other native systems (the light grid, the Road Graph) attached to this mine.
	const lb::core::world::MineMap &map() const { return map_; }

private:
	lb::core::world::MineMap map_;
	void emit_changes();
};

} // namespace lb::godot

#include "godot/world/lb_world.h"

#include "core/tuning/tuning_table.h"
#include "core/world/coords.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;
namespace world = lb::core::world;

namespace lb::godot {

namespace {

world::Coord to_coord(Vector2i v) {
	return {v.x, v.y};
}

Vector2i to_vec(world::Coord c) {
	return Vector2i(static_cast<int32_t>(c.x), static_cast<int32_t>(c.y));
}

std::vector<int64_t> to_bounds(const PackedInt64Array &bounds) {
	return std::vector<int64_t>(bounds.ptr(), bounds.ptr() + bounds.size());
}

bool tuned_bounds(std::vector<int64_t> &out) {
	std::optional<std::vector<int64_t>> bounds = lb::core::TuningTable::current()->get_i64_list("depth.ring_start_tiles");
	if (!bounds) {
		UtilityFunctions::push_error("LbWorld: depth.ring_start_tiles is not in the tuning mirror; load tuning first");
		return false;
	}
	out = std::move(*bounds);
	return true;
}

} // namespace

void LbWorld::_bind_methods() {
	ClassDB::bind_static_method("LbWorld", D_METHOD("cell_of", "tile"), &LbWorld::cell_of);
	ClassDB::bind_static_method("LbWorld", D_METHOD("local_of", "tile"), &LbWorld::local_of);
	ClassDB::bind_static_method("LbWorld", D_METHOD("tile_of", "cell", "local"), &LbWorld::tile_of);
	ClassDB::bind_static_method("LbWorld", D_METHOD("block_of_cell", "cell"), &LbWorld::block_of_cell);
	ClassDB::bind_static_method("LbWorld", D_METHOD("region_of_cell", "cell"), &LbWorld::region_of_cell);
	ClassDB::bind_static_method("LbWorld", D_METHOD("cell_chebyshev", "a", "b"), &LbWorld::cell_chebyshev);
	ClassDB::bind_static_method("LbWorld", D_METHOD("cell_manhattan", "a", "b"), &LbWorld::cell_manhattan);
	ClassDB::bind_static_method("LbWorld", D_METHOD("ring_of_tile", "tile"), &LbWorld::ring_of_tile);
	ClassDB::bind_static_method("LbWorld", D_METHOD("ring_of_point", "x", "y"), &LbWorld::ring_of_point);
	ClassDB::bind_static_method("LbWorld", D_METHOD("ring_of_tile_with", "tile", "bounds"), &LbWorld::ring_of_tile_with);
	ClassDB::bind_static_method("LbWorld", D_METHOD("ring_of_point_with", "x", "y", "bounds"), &LbWorld::ring_of_point_with);
}

Vector2i LbWorld::cell_of(Vector2i tile) { return to_vec(world::cell_of(to_coord(tile))); }
Vector2i LbWorld::local_of(Vector2i tile) { return to_vec(world::local_of(to_coord(tile))); }
Vector2i LbWorld::tile_of(Vector2i cell, Vector2i local) { return to_vec(world::tile_of(to_coord(cell), to_coord(local))); }
Vector2i LbWorld::block_of_cell(Vector2i cell) { return to_vec(world::block_of_cell(to_coord(cell))); }
Vector2i LbWorld::region_of_cell(Vector2i cell) { return to_vec(world::region_of_cell(to_coord(cell))); }
int64_t LbWorld::cell_chebyshev(Vector2i a, Vector2i b) { return world::cell_chebyshev(to_coord(a), to_coord(b)); }
int64_t LbWorld::cell_manhattan(Vector2i a, Vector2i b) { return world::cell_manhattan(to_coord(a), to_coord(b)); }

int64_t LbWorld::ring_of_tile(Vector2i tile) {
	std::vector<int64_t> bounds;
	return tuned_bounds(bounds) ? world::ring_of_tile(to_coord(tile), bounds) : -1;
}

int64_t LbWorld::ring_of_point(double x, double y) {
	std::vector<int64_t> bounds;
	return tuned_bounds(bounds) ? world::ring_of_point(x, y, bounds) : -1;
}

int64_t LbWorld::ring_of_tile_with(Vector2i tile, const PackedInt64Array &bounds) {
	return world::ring_of_tile(to_coord(tile), to_bounds(bounds));
}

int64_t LbWorld::ring_of_point_with(double x, double y, const PackedInt64Array &bounds) {
	return world::ring_of_point(x, y, to_bounds(bounds));
}

void LbEntityIds::_bind_methods() {
	ClassDB::bind_method(D_METHOD("allocate"), &LbEntityIds::allocate);
	ClassDB::bind_method(D_METHOD("get_next"), &LbEntityIds::get_next);
	ClassDB::bind_method(D_METHOD("restore", "next"), &LbEntityIds::restore);
}

int64_t LbEntityIds::allocate() {
	std::optional<world::EntityId> id = ids_.allocate();
	if (!id) {
		UtilityFunctions::push_error("LbEntityIds: the run has spent all 2^32 - 1 entity IDs");
		return 0;
	}
	return *id;
}

int64_t LbEntityIds::get_next() const {
	return static_cast<int64_t>(ids_.next());
}

void LbEntityIds::restore(int64_t next) {
	ids_.restore(next < 0 ? 0 : static_cast<uint64_t>(next));
}

} // namespace lb::godot

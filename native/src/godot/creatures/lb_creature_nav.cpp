#include "godot/creatures/lb_creature_nav.h"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;
using lb::core::creatures::NavMode;
using lb::core::creatures::NavParams;
using lb::core::creatures::NavPath;
using lb::core::world::Coord;

namespace lb::godot {

#define REQUIRE_NAV(ret) ERR_FAIL_COND_V_MSG(nav_ == nullptr, ret, "LbCreatureNav: attach() a mine first")

namespace {

Coord c(Vector2i v) {
	return {v.x, v.y};
}

TypedArray<Vector2i> tiles_of(const std::vector<Coord> &tiles) {
	TypedArray<Vector2i> out;
	for (const Coord &t : tiles) {
		out.push_back(Vector2i(static_cast<int32_t>(t.x), static_cast<int32_t>(t.y)));
	}
	return out;
}

std::vector<Coord> coords_of(const TypedArray<Vector2i> &tiles) {
	std::vector<Coord> out;
	for (int64_t i = 0; i < tiles.size(); i++) {
		const Vector2i v = tiles[i];
		out.push_back(c(v));
	}
	return out;
}

Dictionary path_dict(const NavPath &p) {
	Dictionary d;
	d["tiles"] = tiles_of(p.tiles);
	d["cost"] = p.found ? static_cast<double>(p.cost_milli) / 1000.0 : -1.0;
	d["found"] = p.found;
	d["hit_limit"] = p.hit_limit;
	d["touched_unloaded"] = p.touched_unloaded;
	d["expansions"] = static_cast<int64_t>(p.expansions);
	return d;
}

Variant maybe(const std::optional<Coord> &t) {
	if (!t) {
		return Variant();
	}
	return Vector2i(static_cast<int32_t>(t->x), static_cast<int32_t>(t->y));
}

} // namespace

void LbCreatureNav::_bind_methods() {
	ClassDB::bind_method(D_METHOD("attach", "mine", "light"), &LbCreatureNav::attach);
	ClassDB::bind_method(D_METHOD("set_defaults", "params"), &LbCreatureNav::set_defaults);
	ClassDB::bind_method(D_METHOD("passable", "mode", "tile", "params"), &LbCreatureNav::passable, DEFVAL(Dictionary()));
	ClassDB::bind_method(D_METHOD("wall_adjacent", "tile"), &LbCreatureNav::wall_adjacent);
	ClassDB::bind_method(D_METHOD("path", "mode", "from", "to", "params"), &LbCreatureNav::path, DEFVAL(Dictionary()));
	ClassDB::bind_method(D_METHOD("path_to_any", "mode", "from", "goals", "params"), &LbCreatureNav::path_to_any, DEFVAL(Dictionary()));
	ClassDB::bind_method(D_METHOD("still_valid", "mode", "tiles", "params"), &LbCreatureNav::still_valid, DEFVAL(Dictionary()));
	ClassDB::bind_method(D_METHOD("nearest_dark_tile", "point", "threshold", "max_radius"), &LbCreatureNav::nearest_dark_tile);
	ClassDB::bind_method(D_METHOD("reachable_dark_tile_nearest", "target", "from", "params"), &LbCreatureNav::reachable_dark_tile_nearest, DEFVAL(Dictionary()));
	ClassDB::bind_method(D_METHOD("light_edge_ring", "seed", "threshold", "max_tiles"), &LbCreatureNav::light_edge_ring);
	ClassDB::bind_method(D_METHOD("usable_faces_within", "point", "r"), &LbCreatureNav::usable_faces_within);
	ClassDB::bind_method(D_METHOD("nearest_usable_face", "point", "max_radius"), &LbCreatureNav::nearest_usable_face);
	ClassDB::bind_method(D_METHOD("rock_tile_behind", "tile"), &LbCreatureNav::rock_tile_behind);
	ClassDB::bind_method(D_METHOD("moth_path_within", "from", "miner", "max_tiles", "max_expansions"), &LbCreatureNav::moth_path_within);
	ClassDB::bind_method(D_METHOD("tapper_rock_path_within", "from", "miner", "max_tiles", "reach", "params"), &LbCreatureNav::tapper_rock_path_within, DEFVAL(Dictionary()));
	ClassDB::bind_method(D_METHOD("stythe_dark_path_within", "from", "miner", "max_tiles", "within", "params"), &LbCreatureNav::stythe_dark_path_within, DEFVAL(Dictionary()));
	BIND_ENUM_CONSTANT(WALKER);
	BIND_ENUM_CONSTANT(CRAWLER);
	BIND_ENUM_CONSTANT(DARK);
	BIND_ENUM_CONSTANT(ROCK);
}

void LbCreatureNav::attach(const Ref<LbMine> &mine, const Ref<LbLightGrid> &light) {
	ERR_FAIL_COND(mine.is_null());
	mine_ = mine;
	light_ = light;
	nav_ = std::make_unique<lb::core::creatures::CreatureNav>(mine_->map(), light_.is_valid() ? light_->core() : nullptr);
}

void LbCreatureNav::set_defaults(const Dictionary &params) {
	defaults_ = merged(params);
}

NavParams LbCreatureNav::merged(const Dictionary &d) const {
	NavParams p = defaults_;
	if (d.has("dark_threshold")) {
		p.dark_threshold_milli = static_cast<int64_t>(static_cast<double>(d["dark_threshold"]) * 1000.0 + 0.5);
	}
	if (d.has("max_tiles")) {
		const double t = d["max_tiles"];
		p.max_cost_milli = t < 0.0 ? -1 : static_cast<int64_t>(t * 1000.0 + 0.5);
	}
	if (d.has("max_expansions")) {
		p.max_expansions = d["max_expansions"];
	}
	if (d.has("crawl_open_cost")) {
		p.crawl_open_cost = d["crawl_open_cost"];
	}
	if (d.has("rock_crosses_floor")) {
		p.rock_crosses_floor = d["rock_crosses_floor"];
	}
	if (d.has("brick_clearance")) {
		p.brick_clearance = d["brick_clearance"];
	}
	return p;
}

bool LbCreatureNav::passable(int64_t mode, Vector2i tile, const Dictionary &params) const {
	REQUIRE_NAV(false);
	return nav_->passable(static_cast<NavMode>(mode), c(tile), merged(params));
}

bool LbCreatureNav::wall_adjacent(Vector2i tile) const {
	REQUIRE_NAV(false);
	return nav_->wall_adjacent(c(tile));
}

Dictionary LbCreatureNav::path(int64_t mode, Vector2i from, Vector2i to, const Dictionary &params) const {
	REQUIRE_NAV(Dictionary());
	return path_dict(nav_->path(static_cast<NavMode>(mode), c(from), c(to), merged(params)));
}

Dictionary LbCreatureNav::path_to_any(int64_t mode, Vector2i from, const TypedArray<Vector2i> &goals, const Dictionary &params) const {
	REQUIRE_NAV(Dictionary());
	return path_dict(nav_->path_to_any(static_cast<NavMode>(mode), c(from), coords_of(goals), merged(params)));
}

bool LbCreatureNav::still_valid(int64_t mode, const TypedArray<Vector2i> &tiles, const Dictionary &params) const {
	REQUIRE_NAV(false);
	return nav_->still_valid(static_cast<NavMode>(mode), coords_of(tiles), merged(params));
}

Variant LbCreatureNav::nearest_dark_tile(Vector2 point, double threshold, int64_t max_radius) const {
	REQUIRE_NAV(Variant());
	return maybe(nav_->nearest_dark_tile(point.x, point.y, static_cast<int64_t>(threshold * 1000.0 + 0.5), max_radius));
}

Variant LbCreatureNav::reachable_dark_tile_nearest(Vector2i target, Vector2i from, const Dictionary &params) const {
	REQUIRE_NAV(Variant());
	return maybe(nav_->reachable_dark_tile_nearest(c(target), c(from), merged(params)));
}

TypedArray<Vector2i> LbCreatureNav::light_edge_ring(Vector2i seed, double threshold, int64_t max_tiles) const {
	REQUIRE_NAV(TypedArray<Vector2i>());
	return tiles_of(nav_->light_edge_ring(c(seed), static_cast<int64_t>(threshold * 1000.0 + 0.5), max_tiles));
}

TypedArray<Vector2i> LbCreatureNav::usable_faces_within(Vector2 point, double r) const {
	REQUIRE_NAV(TypedArray<Vector2i>());
	return tiles_of(nav_->usable_faces_within(point.x, point.y, r));
}

Variant LbCreatureNav::nearest_usable_face(Vector2 point, int64_t max_radius) const {
	REQUIRE_NAV(Variant());
	return maybe(nav_->nearest_usable_face(point.x, point.y, max_radius));
}

Variant LbCreatureNav::rock_tile_behind(Vector2i tile) const {
	REQUIRE_NAV(Variant());
	return maybe(nav_->rock_tile_behind(c(tile)));
}

Dictionary LbCreatureNav::moth_path_within(Vector2i from, Vector2 miner, double max_tiles, int64_t max_expansions) const {
	REQUIRE_NAV(Dictionary());
	return path_dict(nav_->moth_path_within(c(from), miner.x, miner.y, max_tiles, max_expansions));
}

Dictionary LbCreatureNav::tapper_rock_path_within(Vector2i from, Vector2 miner, double max_tiles, double reach, const Dictionary &params) const {
	REQUIRE_NAV(Dictionary());
	return path_dict(nav_->tapper_rock_path_within(c(from), miner.x, miner.y, max_tiles, reach, merged(params)));
}

Dictionary LbCreatureNav::stythe_dark_path_within(Vector2i from, Vector2 miner, double max_tiles, double within, const Dictionary &params) const {
	REQUIRE_NAV(Dictionary());
	return path_dict(nav_->stythe_dark_path_within(c(from), miner.x, miner.y, max_tiles, within, merged(params)));
}

} // namespace lb::godot

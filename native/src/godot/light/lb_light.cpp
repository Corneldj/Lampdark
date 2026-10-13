#include "godot/light/lb_light.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <cmath>

using namespace godot;
namespace light = lb::core::light;
using lb::core::world::Coord;

namespace lb::godot {

namespace {

std::string to_std(const String &s) {
	CharString utf8 = s.utf8();
	return std::string(utf8.get_data(), static_cast<size_t>(utf8.length()));
}

std::vector<Coord> coords_from(const Array &tiles) {
	std::vector<Coord> out;
	for (int64_t i = 0; i < tiles.size(); i++) {
		const Vector2i t = tiles[i];
		out.push_back({t.x, t.y});
	}
	return out;
}

} // namespace

#define REQUIRE_GRID(ret) ERR_FAIL_NULL_V_MSG(grid_, ret, "LbLightGrid: attach() a mine first")

void LbLightGrid::_bind_methods() {
	ClassDB::bind_method(D_METHOD("attach", "mine"), &LbLightGrid::attach);
	ClassDB::bind_method(D_METHOD("set_params", "core_fraction", "core_value", "edge_value", "cap", "scale"), &LbLightGrid::set_params);
	ClassDB::bind_method(D_METHOD("add_point", "kind", "colour", "owner", "flags", "radius", "peak", "position", "lifetime_ticks"), &LbLightGrid::add_point);
	ClassDB::bind_method(D_METHOD("add_area", "kind", "colour", "owner", "value", "tiles"), &LbLightGrid::add_area);
	ClassDB::bind_method(D_METHOD("add_spill", "kind", "colour", "owner", "doorway", "outward", "length", "start_value", "end_value"), &LbLightGrid::add_spill);
	ClassDB::bind_method(D_METHOD("add_spot", "owner", "tile", "value", "lifetime_ticks"), &LbLightGrid::add_spot);
	ClassDB::bind_method(D_METHOD("update_point", "id", "position", "radius", "peak"), &LbLightGrid::update_point);
	ClassDB::bind_method(D_METHOD("set_radius_modifier", "id", "multiplier", "cause"), &LbLightGrid::set_radius_modifier);
	ClassDB::bind_method(D_METHOD("set_flags", "id", "flags"), &LbLightGrid::set_flags);
	ClassDB::bind_method(D_METHOD("remove_source", "id"), &LbLightGrid::remove_source);
	ClassDB::bind_method(D_METHOD("has_source", "id"), &LbLightGrid::has_source);
	ClassDB::bind_method(D_METHOD("velocity", "id"), &LbLightGrid::velocity);
	ClassDB::bind_method(D_METHOD("on_cell_loaded", "cell"), &LbLightGrid::on_cell_loaded);
	ClassDB::bind_method(D_METHOD("on_cell_unloading", "cell"), &LbLightGrid::on_cell_unloading);
	ClassDB::bind_method(D_METHOD("on_tiles_changed", "cell", "rect", "reason"), &LbLightGrid::on_tiles_changed);
	ClassDB::bind_method(D_METHOD("begin_tick", "tick_hz"), &LbLightGrid::begin_tick);
	ClassDB::bind_method(D_METHOD("update"), &LbLightGrid::update);
	ClassDB::bind_method(D_METHOD("value", "tile"), &LbLightGrid::value);
	ClassDB::bind_method(D_METHOD("value_at", "position"), &LbLightGrid::value_at);
	ClassDB::bind_method(D_METHOD("value_from", "tile", "owners"), &LbLightGrid::value_from);
	ClassDB::bind_method(D_METHOD("colour_class", "tile"), &LbLightGrid::colour_class);
	ClassDB::bind_method(D_METHOD("brightest_source", "tile"), &LbLightGrid::brightest_source);
	ClassDB::bind_method(D_METHOD("source_info", "id"), &LbLightGrid::source_info);
	ClassDB::bind_method(D_METHOD("tiles_at_or_above", "threshold", "rect"), &LbLightGrid::tiles_at_or_above);
	ClassDB::bind_method(D_METHOD("flame_sources", "rect"), &LbLightGrid::flame_sources);
	ClassDB::bind_method(D_METHOD("digest"), &LbLightGrid::digest);
	ClassDB::bind_method(D_METHOD("last_update_usec"), &LbLightGrid::last_update_usec);
	ClassDB::bind_method(D_METHOD("source_count"), &LbLightGrid::source_count);
	ClassDB::bind_method(D_METHOD("owned_radius", "owner"), &LbLightGrid::owned_radius);
	ADD_SIGNAL(MethodInfo("source_added", PropertyInfo(Variant::INT, "id"), PropertyInfo(Variant::STRING, "kind"), PropertyInfo(Variant::VECTOR2, "position")));
	ADD_SIGNAL(MethodInfo("source_removed", PropertyInfo(Variant::INT, "id")));
	ADD_SIGNAL(MethodInfo("light_changed", PropertyInfo(Variant::INT, "id"), PropertyInfo(Variant::STRING, "kind"), PropertyInfo(Variant::STRING, "cause")));
	ClassDB::bind_integer_constant("LbLightGrid", "", "COLOUR_NONE", static_cast<int64_t>(light::ColourClass::NONE));
	ClassDB::bind_integer_constant("LbLightGrid", "", "COLOUR_AMBER", static_cast<int64_t>(light::ColourClass::AMBER));
	ClassDB::bind_integer_constant("LbLightGrid", "", "COLOUR_PALE_AMBER", static_cast<int64_t>(light::ColourClass::PALE_AMBER));
	ClassDB::bind_integer_constant("LbLightGrid", "", "COLOUR_WHITE", static_cast<int64_t>(light::ColourClass::WHITE));
	ClassDB::bind_integer_constant("LbLightGrid", "", "COLOUR_EGG_GLOW", static_cast<int64_t>(light::ColourClass::EGG_GLOW));
	ClassDB::bind_integer_constant("LbLightGrid", "", "COLOUR_GOB_ORANGE", static_cast<int64_t>(light::ColourClass::GOB_ORANGE));
	ClassDB::bind_integer_constant("LbLightGrid", "", "FLAG_FLAME", light::flag::FLAME);
	ClassDB::bind_integer_constant("LbLightGrid", "", "FLAG_CARRIED", light::flag::CARRIED);
	ClassDB::bind_integer_constant("LbLightGrid", "", "FLAG_UNHELD", light::flag::UNHELD);
	ClassDB::bind_integer_constant("LbLightGrid", "", "FLAG_CANNOT_TAKE", light::flag::CANNOT_TAKE);
	ClassDB::bind_integer_constant("LbLightGrid", "", "FLAG_NO_FLAME_STATES", light::flag::NO_FLAME_STATES);
	ClassDB::bind_integer_constant("LbLightGrid", "", "FLAG_BEYOND_SNUFF", light::flag::BEYOND_SNUFF);
}

void LbLightGrid::attach(const Ref<LbMine> &mine) {
	ERR_FAIL_COND(mine.is_null());
	mine_ = mine;
	grid_ = std::make_unique<light::LightGrid>(mine_->map());
	for (const Coord &c : mine_->map().loaded_cells()) {
		grid_->on_cell_loaded(c);
	}
}

void LbLightGrid::set_params(double core_fraction, double core_value, double edge_value, double cap, int64_t scale) {
	REQUIRE_GRID();
	grid_->params = {core_fraction, core_value, edge_value, cap, scale};
}

void LbLightGrid::emit_events() {
	for (const light::LightEvent &e : grid_->take_events()) {
		switch (e.type) {
			case light::LightEvent::Type::ADDED:
				emit_signal("source_added", static_cast<int64_t>(e.id), String::utf8(e.kind.c_str()), Vector2(static_cast<real_t>(e.x), static_cast<real_t>(e.y)));
				break;
			case light::LightEvent::Type::REMOVED:
				emit_signal("source_removed", static_cast<int64_t>(e.id));
				break;
			case light::LightEvent::Type::CHANGED:
				emit_signal("light_changed", static_cast<int64_t>(e.id), String::utf8(e.kind.c_str()), String::utf8(e.cause.c_str()));
				break;
		}
	}
}

int64_t LbLightGrid::add_point(const String &kind, int64_t colour, int64_t owner, int64_t flags, double radius, double peak,
		Vector2 position, int64_t lifetime_ticks) {
	REQUIRE_GRID(0);
	light::SourceDesc d;
	d.shape = light::Shape::POINT;
	d.kind = to_std(kind);
	d.colour = static_cast<light::ColourClass>(colour);
	d.owner = static_cast<uint32_t>(owner);
	d.flags = static_cast<uint32_t>(flags);
	d.radius = radius;
	d.peak = peak;
	d.x = position.x;
	d.y = position.y;
	d.lifetime_ticks = lifetime_ticks;
	const uint32_t id = grid_->add_source(d);
	emit_events();
	return id;
}

int64_t LbLightGrid::add_area(const String &kind, int64_t colour, int64_t owner, double value, const Array &tiles) {
	REQUIRE_GRID(0);
	light::SourceDesc d;
	d.shape = light::Shape::AREA;
	d.kind = to_std(kind);
	d.colour = static_cast<light::ColourClass>(colour);
	d.owner = static_cast<uint32_t>(owner);
	d.peak = value;
	d.tiles = coords_from(tiles);
	const uint32_t id = grid_->add_source(d);
	emit_events();
	return id;
}

int64_t LbLightGrid::add_spill(const String &kind, int64_t colour, int64_t owner, const Array &doorway, Vector2i outward,
		double length, double start_value, double end_value) {
	REQUIRE_GRID(0);
	light::SourceDesc d;
	d.shape = light::Shape::SPILL;
	d.kind = to_std(kind);
	d.colour = static_cast<light::ColourClass>(colour);
	d.owner = static_cast<uint32_t>(owner);
	d.tiles = coords_from(doorway);
	d.dir = {outward.x, outward.y};
	d.radius = length;
	d.peak = start_value;
	d.end_value = end_value;
	const uint32_t id = grid_->add_source(d);
	emit_events();
	return id;
}

int64_t LbLightGrid::add_spot(int64_t owner, Vector2i tile, double value, int64_t lifetime_ticks) {
	REQUIRE_GRID(0);
	light::SourceDesc d;
	d.shape = light::Shape::SPOT;
	d.kind = "spot";
	d.colour = light::ColourClass::AMBER;
	d.owner = static_cast<uint32_t>(owner);
	d.spot = {tile.x, tile.y};
	d.x = tile.x + 0.5;
	d.y = tile.y + 0.5;
	d.peak = value;
	d.lifetime_ticks = lifetime_ticks;
	const uint32_t id = grid_->add_source(d);
	emit_events();
	return id;
}

bool LbLightGrid::update_point(int64_t id, Vector2 position, double radius, double peak) {
	REQUIRE_GRID(false);
	const bool ok = grid_->update_point(static_cast<uint32_t>(id), position.x, position.y, radius, peak);
	emit_events();
	return ok;
}

bool LbLightGrid::set_radius_modifier(int64_t id, double multiplier, const String &cause) {
	REQUIRE_GRID(false);
	const bool ok = grid_->set_radius_modifier(static_cast<uint32_t>(id), multiplier, to_std(cause));
	emit_events();
	return ok;
}

bool LbLightGrid::set_flags(int64_t id, int64_t flags) {
	REQUIRE_GRID(false);
	return grid_->set_flags(static_cast<uint32_t>(id), static_cast<uint32_t>(flags));
}

bool LbLightGrid::remove_source(int64_t id) {
	REQUIRE_GRID(false);
	const bool ok = grid_->remove_source(static_cast<uint32_t>(id));
	emit_events();
	return ok;
}

bool LbLightGrid::has_source(int64_t id) const {
	return grid_ && grid_->has_source(static_cast<uint32_t>(id));
}

Vector2 LbLightGrid::velocity(int64_t id) const {
	REQUIRE_GRID(Vector2());
	const auto v = grid_->velocity(static_cast<uint32_t>(id));
	return Vector2(static_cast<real_t>(v.first), static_cast<real_t>(v.second));
}

void LbLightGrid::on_cell_loaded(Vector2i cell) {
	REQUIRE_GRID();
	grid_->on_cell_loaded({cell.x, cell.y});
}

void LbLightGrid::on_cell_unloading(Vector2i cell) {
	REQUIRE_GRID();
	grid_->on_cell_unloading({cell.x, cell.y});
}

void LbLightGrid::on_tiles_changed(Vector2i, Rect2i rect, const String &) {
	REQUIRE_GRID();
	grid_->on_tiles_changed(rect.position.x, rect.position.y, rect.position.x + rect.size.x - 1, rect.position.y + rect.size.y - 1);
}

void LbLightGrid::begin_tick(double tick_hz) {
	REQUIRE_GRID();
	grid_->begin_tick(tick_hz);
	emit_events();
}

void LbLightGrid::update() {
	REQUIRE_GRID();
	grid_->update();
	emit_events();
}

int64_t LbLightGrid::value(Vector2i tile) const {
	REQUIRE_GRID(0);
	return grid_->value({tile.x, tile.y});
}

int64_t LbLightGrid::value_at(Vector2 position) const {
	REQUIRE_GRID(0);
	return grid_->value_at(position.x, position.y);
}

int64_t LbLightGrid::value_from(Vector2i tile, const PackedInt64Array &owners) const {
	REQUIRE_GRID(0);
	std::vector<uint32_t> list;
	for (int64_t i = 0; i < owners.size(); i++) {
		list.push_back(static_cast<uint32_t>(owners[i]));
	}
	return grid_->value_from({tile.x, tile.y}, list);
}

int64_t LbLightGrid::colour_class(Vector2i tile) const {
	REQUIRE_GRID(0);
	return static_cast<int64_t>(grid_->tile_light({tile.x, tile.y}).colour);
}

Dictionary LbLightGrid::brightest_source(Vector2i tile) const {
	Dictionary out;
	REQUIRE_GRID(out);
	const uint32_t id = grid_->tile_light({tile.x, tile.y}).brightest;
	out["id"] = static_cast<int64_t>(id);
	if (std::optional<light::SourceDesc> d = grid_->source(id)) {
		out["position"] = Vector2(static_cast<real_t>(d->x), static_cast<real_t>(d->y));
		out["radius"] = d->radius;
		out["owner"] = static_cast<int64_t>(d->owner);
		out["kind"] = String::utf8(d->kind.c_str());
	}
	return out;
}

Dictionary LbLightGrid::source_info(int64_t id) const {
	Dictionary out;
	REQUIRE_GRID(out);
	if (std::optional<light::SourceDesc> d = grid_->source(static_cast<uint32_t>(id))) {
		out["kind"] = String::utf8(d->kind.c_str());
		out["owner"] = static_cast<int64_t>(d->owner);
		out["flags"] = static_cast<int64_t>(d->flags);
		out["shape"] = static_cast<int64_t>(d->shape);
		out["colour"] = static_cast<int64_t>(d->colour);
		out["radius_mult"] = grid_->radius_mult(static_cast<uint32_t>(id));
		out["position"] = Vector2(static_cast<real_t>(d->x), static_cast<real_t>(d->y));
		out["radius"] = d->radius;
		out["peak"] = d->peak;
	}
	return out;
}

Array LbLightGrid::tiles_at_or_above(int64_t threshold, Rect2i rect) const {
	Array out;
	REQUIRE_GRID(out);
	for (const Coord &c : grid_->tiles_at_or_above(threshold, rect.position.x, rect.position.y,
				 rect.position.x + rect.size.x - 1, rect.position.y + rect.size.y - 1)) {
		out.push_back(Vector2i(static_cast<int32_t>(c.x), static_cast<int32_t>(c.y)));
	}
	return out;
}

PackedInt64Array LbLightGrid::flame_sources(Rect2 rect) const {
	PackedInt64Array out;
	REQUIRE_GRID(out);
	for (uint32_t id : grid_->flame_sources(rect.position.x, rect.position.y, rect.position.x + rect.size.x, rect.position.y + rect.size.y)) {
		out.push_back(id);
	}
	return out;
}

int64_t LbLightGrid::digest() const {
	REQUIRE_GRID(0);
	return static_cast<int64_t>(grid_->digest());
}

int64_t LbLightGrid::last_update_usec() const {
	return grid_ ? grid_->last_update_usec : 0;
}

int64_t LbLightGrid::source_count() const {
	return grid_ ? static_cast<int64_t>(grid_->source_count()) : 0;
}

double LbLightGrid::owned_radius(int64_t owner) const {
	if (!grid_) {
		return 0.0;
	}
	double best = 0.0;
	for (const light::LightGrid::OwnLight &l : grid_->owned_lights(static_cast<uint32_t>(owner))) {
		best = l.radius > best ? l.radius : best;
	}
	return best;
}

void LbLightMath::_bind_methods() {
	ClassDB::bind_static_method("LbLightMath", D_METHOD("falloff_milli", "distance", "radius", "peak", "core_fraction", "core_value", "edge_value"), &LbLightMath::falloff_milli);
}

int64_t LbLightMath::falloff_milli(double distance, double radius, double peak, double core_fraction, double core_value, double edge_value) {
	light::LightParams p;
	p.core_fraction = core_fraction;
	p.core_value = core_value;
	p.edge_value = edge_value;
	return light::falloff_milli(distance, radius, peak, p);
}

} // namespace lb::godot

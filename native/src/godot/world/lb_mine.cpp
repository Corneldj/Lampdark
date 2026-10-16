#include "godot/world/lb_mine.h"

#include "core/gen/template.h"
#include "core/sound/zone_block.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <set>

using namespace godot;
namespace world = lb::core::world;

namespace lb::godot {

namespace {

const char *const ANCHOR_NAMES[] = {"timber_hook", "rubble_heap", "landmark", "chamber", "remains", "item",
	"wall_fixture", "door_site", "trap_site", "low_road", "gas_area", "gas_dead_end", "rich_rock",
	"collapse", "poi_slot"};
static_assert(sizeof(ANCHOR_NAMES) / sizeof(ANCHOR_NAMES[0]) == static_cast<size_t>(world::AnchorType::COUNT));

std::string to_std(const String &s) {
	CharString utf8 = s.utf8();
	return std::string(utf8.get_data(), static_cast<size_t>(utf8.length()));
}

world::Coord coord(Vector2i v) {
	return {v.x, v.y};
}

Vector2i vec(world::Coord c) {
	return Vector2i(static_cast<int32_t>(c.x), static_cast<int32_t>(c.y));
}

Array tile_writes(const std::vector<world::TileWrite> &writes) {
	Array out;
	for (const world::TileWrite &w : writes) {
		Array pair;
		pair.push_back(static_cast<int64_t>(w.index));
		pair.push_back(static_cast<int64_t>(w.material));
		out.push_back(pair);
	}
	return out;
}

std::vector<world::TileWrite> writes_from(const PackedInt32Array &indices, const PackedByteArray &materials) {
	std::vector<world::TileWrite> out;
	for (int64_t i = 0; i < indices.size() && i < materials.size(); i++) {
		out.push_back({static_cast<uint16_t>(indices[i]), materials[i]});
	}
	return out;
}

} // namespace

// ---- LbCellData ----

void LbCellData::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_coord", "cell"), &LbCellData::set_coord);
	ClassDB::bind_method(D_METHOD("get_coord"), &LbCellData::get_coord);
	ClassDB::bind_method(D_METHOD("set_tile", "local", "material", "state", "zone"), &LbCellData::set_tile);
	ClassDB::bind_method(D_METHOD("get_tile", "local"), &LbCellData::get_tile);
	ClassDB::bind_method(D_METHOD("add_anchor", "type", "at", "size", "tags", "kind"), &LbCellData::add_anchor);
	ClassDB::bind_method(D_METHOD("add_barrier", "id", "portal", "local_indices", "open"), &LbCellData::add_barrier);
	ClassDB::bind_method(D_METHOD("add_collapse", "id", "standing_indices", "standing_materials", "fallen_indices", "fallen_materials", "is_fallen"), &LbCellData::add_collapse);
	ClassDB::bind_method(D_METHOD("set_road_graph", "bytes"), &LbCellData::set_road_graph);
	ClassDB::bind_method(D_METHOD("set_collapse_zones", "id", "indices", "standing", "fallen", "fallen_road_graph"), &LbCellData::set_collapse_zones);
	ClassDB::bind_method(D_METHOD("cut_zones", "room_kind"), &LbCellData::cut_zones);
	ClassDB::bind_method(D_METHOD("get_anchors"), &LbCellData::get_anchors);
	ClassDB::bind_method(D_METHOD("get_barriers"), &LbCellData::get_barriers);
	ClassDB::bind_method(D_METHOD("get_collapses"), &LbCellData::get_collapses);
	ClassDB::bind_method(D_METHOD("get_road_graph"), &LbCellData::get_road_graph);
	ClassDB::bind_method(D_METHOD("digest"), &LbCellData::digest);
	ClassDB::bind_method(D_METHOD("is_taken"), &LbCellData::is_taken);
}

LbCellData::LbCellData() : cell_(std::make_unique<world::Cell>()) {}

void LbCellData::set_coord(Vector2i cell) {
	ERR_FAIL_NULL(cell_);
	cell_->coord = coord(cell);
}

Vector2i LbCellData::get_coord() const {
	return cell_ ? vec(cell_->coord) : Vector2i();
}

void LbCellData::set_tile(Vector2i local, int64_t material, int64_t state, int64_t zone) {
	ERR_FAIL_NULL(cell_);
	ERR_FAIL_COND(local.x < 0 || local.y < 0 || local.x >= world::CELL_TILES || local.y >= world::CELL_TILES);
	ERR_FAIL_COND(material < 0 || material >= static_cast<int64_t>(world::MATERIAL_COUNT));
	world::Tile &t = cell_->tiles[world::Cell::index_of(local.x, local.y)];
	t.material = static_cast<uint8_t>(material);
	t.state = static_cast<uint8_t>(state);
	t.zone = static_cast<uint16_t>(zone);
}

Dictionary LbCellData::get_tile(Vector2i local) const {
	Dictionary out;
	ERR_FAIL_NULL_V(cell_, out);
	ERR_FAIL_COND_V(local.x < 0 || local.y < 0 || local.x >= world::CELL_TILES || local.y >= world::CELL_TILES, out);
	const world::Tile &t = cell_->tiles[world::Cell::index_of(local.x, local.y)];
	out["material"] = static_cast<int64_t>(t.material);
	out["state"] = static_cast<int64_t>(t.state);
	out["zone"] = static_cast<int64_t>(t.zone);
	return out;
}

bool LbCellData::add_anchor(const String &type, Vector2i at, Vector2i size, const PackedStringArray &tags, const String &kind) {
	ERR_FAIL_NULL_V(cell_, false);
	const std::string name = to_std(type);
	for (size_t i = 0; i < static_cast<size_t>(world::AnchorType::COUNT); i++) {
		if (name == ANCHOR_NAMES[i]) {
			world::Anchor a;
			a.type = static_cast<world::AnchorType>(i);
			a.x = at.x;
			a.y = at.y;
			a.w = size.x;
			a.h = size.y;
			for (int64_t t = 0; t < tags.size(); t++) {
				a.tags.push_back(to_std(tags[t]));
			}
			a.kind = to_std(kind);
			cell_->anchors.push_back(std::move(a));
			return true;
		}
	}
	UtilityFunctions::push_error("LbCellData: unknown anchor type '", type, "'");
	return false;
}

void LbCellData::add_barrier(int64_t id, int64_t portal, const PackedInt32Array &local_indices, bool open) {
	ERR_FAIL_NULL(cell_);
	world::Barrier b;
	b.id = static_cast<uint32_t>(id);
	b.portal = static_cast<uint32_t>(portal);
	for (int64_t i = 0; i < local_indices.size(); i++) {
		b.tiles.push_back(static_cast<uint16_t>(local_indices[i]));
	}
	b.open = open;
	cell_->barriers.push_back(std::move(b));
}

void LbCellData::add_collapse(int64_t id, const PackedInt32Array &standing_indices, const PackedByteArray &standing_materials,
		const PackedInt32Array &fallen_indices, const PackedByteArray &fallen_materials, bool is_fallen) {
	ERR_FAIL_NULL(cell_);
	world::Collapse c;
	c.id = static_cast<uint32_t>(id);
	c.standing = writes_from(standing_indices, standing_materials);
	c.fallen = writes_from(fallen_indices, fallen_materials);
	c.is_fallen = is_fallen;
	cell_->collapses.push_back(std::move(c));
}

void LbCellData::set_road_graph(const PackedByteArray &bytes) {
	ERR_FAIL_NULL(cell_);
	cell_->road_graph.assign(bytes.ptr(), bytes.ptr() + bytes.size());
}

bool LbCellData::set_collapse_zones(int64_t id, const PackedInt32Array &indices, const PackedInt32Array &standing,
		const PackedInt32Array &fallen, const PackedByteArray &fallen_road_graph) {
	ERR_FAIL_NULL_V(cell_, false);
	for (world::Collapse &c : cell_->collapses) {
		if (c.id != static_cast<uint32_t>(id)) {
			continue;
		}
		c.zones.clear();
		for (int64_t i = 0; i < indices.size() && i < standing.size() && i < fallen.size(); i++) {
			c.zones.push_back({static_cast<uint16_t>(indices[i]), static_cast<uint16_t>(standing[i]), static_cast<uint16_t>(fallen[i])});
		}
		c.fallen_road_graph.assign(fallen_road_graph.ptr(), fallen_road_graph.ptr() + fallen_road_graph.size());
		return true;
	}
	return false;
}

bool LbCellData::cut_zones(const String &room_kind) {
	ERR_FAIL_NULL_V(cell_, false);
	const std::string kind = to_std(room_kind);
	uint8_t room = static_cast<uint8_t>(lb::core::sound::ZoneKind::CHAMBER);
	if (kind == "poi") {
		room = static_cast<uint8_t>(lb::core::sound::ZoneKind::POI);
	} else if (kind != "chamber" && kind != "base_camp") {
		UtilityFunctions::push_error("LbCellData: unknown room kind '", room_kind, "'");
		return false;
	}
	lb::core::gen::cut_zones(*cell_, room, kind == "base_camp");
	lb::core::gen::cut_collapses(*cell_, room, kind == "base_camp");
	return true;
}

Array LbCellData::get_anchors() const {
	Array out;
	ERR_FAIL_NULL_V(cell_, out);
	for (const world::Anchor &a : cell_->anchors) {
		Dictionary d;
		d["type"] = String(ANCHOR_NAMES[static_cast<size_t>(a.type)]);
		d["x"] = a.x;
		d["y"] = a.y;
		d["w"] = a.w;
		d["h"] = a.h;
		PackedStringArray tags;
		for (const std::string &t : a.tags) {
			tags.push_back(String::utf8(t.c_str()));
		}
		d["tags"] = tags;
		d["kind"] = String::utf8(a.kind.c_str());
		out.push_back(d);
	}
	return out;
}

Array LbCellData::get_barriers() const {
	Array out;
	ERR_FAIL_NULL_V(cell_, out);
	for (const world::Barrier &b : cell_->barriers) {
		Dictionary d;
		d["id"] = static_cast<int64_t>(b.id);
		d["portal"] = static_cast<int64_t>(b.portal);
		PackedInt32Array tiles;
		for (uint16_t i : b.tiles) {
			tiles.push_back(i);
		}
		d["tiles"] = tiles;
		d["open"] = b.open;
		out.push_back(d);
	}
	return out;
}

Array LbCellData::get_collapses() const {
	Array out;
	ERR_FAIL_NULL_V(cell_, out);
	for (const world::Collapse &c : cell_->collapses) {
		Dictionary d;
		d["id"] = static_cast<int64_t>(c.id);
		d["standing"] = tile_writes(c.standing);
		d["fallen"] = tile_writes(c.fallen);
		d["is_fallen"] = c.is_fallen;
		Array zones;
		for (const world::ZoneWrite &z : c.zones) {
			Array triple;
			triple.push_back(static_cast<int64_t>(z.index));
			triple.push_back(static_cast<int64_t>(z.standing));
			triple.push_back(static_cast<int64_t>(z.fallen));
			zones.push_back(triple);
		}
		d["zones"] = zones;
		PackedByteArray block;
		block.resize(static_cast<int64_t>(c.fallen_road_graph.size()));
		for (size_t i = 0; i < c.fallen_road_graph.size(); i++) {
			block.set(static_cast<int64_t>(i), c.fallen_road_graph[i]);
		}
		d["fallen_road_graph"] = block;
		out.push_back(d);
	}
	return out;
}

PackedByteArray LbCellData::get_road_graph() const {
	PackedByteArray out;
	if (cell_) {
		out.resize(static_cast<int64_t>(cell_->road_graph.size()));
		for (size_t i = 0; i < cell_->road_graph.size(); i++) {
			out.set(static_cast<int64_t>(i), cell_->road_graph[i]);
		}
	}
	return out;
}

int64_t LbCellData::digest() const {
	ERR_FAIL_NULL_V(cell_, 0);
	return static_cast<int64_t>(world::content_digest(*cell_));
}

std::unique_ptr<world::Cell> LbCellData::take() {
	return std::move(cell_);
}

Ref<LbCellData> LbCellData::wrap(const world::Cell &cell) {
	Ref<LbCellData> out;
	out.instantiate();
	*out->cell_ = cell;
	return out;
}

// ---- LbMine ----

void LbMine::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_material_table", "table"), &LbMine::set_material_table);
	ClassDB::bind_method(D_METHOD("set_path_costs", "orthogonal_milli", "diagonal_milli"), &LbMine::set_path_costs);
	ClassDB::bind_method(D_METHOD("commit", "data"), &LbMine::commit);
	ClassDB::bind_method(D_METHOD("unload", "cell"), &LbMine::unload);
	ClassDB::bind_method(D_METHOD("is_loaded", "cell"), &LbMine::is_loaded);
	ClassDB::bind_method(D_METHOD("loaded_cells"), &LbMine::loaded_cells);
	ClassDB::bind_method(D_METHOD("loaded_count"), &LbMine::loaded_count);
	ClassDB::bind_method(D_METHOD("missing_cells", "centres", "radius"), &LbMine::missing_cells);
	ClassDB::bind_method(D_METHOD("material_at", "tile"), &LbMine::material_at);
	ClassDB::bind_method(D_METHOD("state_at", "tile"), &LbMine::state_at);
	ClassDB::bind_method(D_METHOD("zone_at", "tile"), &LbMine::zone_at);
	ClassDB::bind_method(D_METHOD("effective_material", "tile"), &LbMine::effective_material);
	ClassDB::bind_method(D_METHOD("is_walkable", "tile", "doors_open"), &LbMine::is_walkable, DEFVAL(false));
	ClassDB::bind_method(D_METHOD("is_solid", "tile"), &LbMine::is_solid);
	ClassDB::bind_method(D_METHOD("is_opaque", "tile"), &LbMine::is_opaque);
	ClassDB::bind_method(D_METHOD("tapper_face_usable", "tile"), &LbMine::tapper_face_usable);
	ClassDB::bind_method(D_METHOD("strike_milli", "tile"), &LbMine::strike_milli);
	ClassDB::bind_method(D_METHOD("depth_milli", "tile"), &LbMine::depth_milli);
	ClassDB::bind_method(D_METHOD("thickness", "tile"), &LbMine::thickness);
	ClassDB::bind_method(D_METHOD("set_barrier", "cell", "barrier_id", "open"), &LbMine::set_barrier);
	ClassDB::bind_method(D_METHOD("set_collapse", "cell", "collapse_id", "fallen"), &LbMine::set_collapse);
	ClassDB::bind_method(D_METHOD("path_distance", "from", "to", "max_milli", "doors_open"), &LbMine::path_distance, DEFVAL(false));
	ClassDB::bind_method(D_METHOD("flood_count", "from", "max_milli", "doors_open"), &LbMine::flood_count, DEFVAL(false));
	ClassDB::bind_method(D_METHOD("nearest_open_tile", "point", "exclude", "max_radius"), &LbMine::nearest_open_tile);
	ClassDB::bind_method(D_METHOD("digest", "cell"), &LbMine::digest);
	ClassDB::bind_method(D_METHOD("anchors", "cell"), &LbMine::anchors);
	ClassDB::bind_method(D_METHOD("barriers", "cell"), &LbMine::barriers);
	ADD_SIGNAL(MethodInfo("tiles_changed", PropertyInfo(Variant::VECTOR2I, "cell"), PropertyInfo(Variant::RECT2I, "rect"), PropertyInfo(Variant::STRING, "reason")));
	ADD_SIGNAL(MethodInfo("cell_loaded", PropertyInfo(Variant::VECTOR2I, "cell")));
	ADD_SIGNAL(MethodInfo("cell_unloading", PropertyInfo(Variant::VECTOR2I, "cell")));
}

bool LbMine::set_material_table(const Dictionary &table) {
	world::MaterialTable result = world::MaterialTable::defaults();
	const char *names[] = {"FLOOR", "ROCK", "COAL", "BRICK", "TIMBER", "STEEL", "WOODEN_DOOR"};
	for (size_t i = 0; i < world::MATERIAL_COUNT; i++) {
		if (!table.has(names[i])) {
			UtilityFunctions::push_error("LbMine.set_material_table: missing ", names[i]);
			return false;
		}
		Dictionary row = table[names[i]];
		world::MaterialProps p;
		p.solid = row.get("solid", false);
		p.opaque = row.get("opaque", false);
		p.tapper_moves = row.get("tapper_moves", false);
		p.tapper_face = row.get("tapper_face", false);
		p.voice_crosses = row.get("voice_crosses", false);
		p.taps_cross = row.get("taps_cross", false);
		p.caption_key = to_std(row.get("caption_key", ""));
		result.set(static_cast<world::TileMaterial>(i), p);
	}
	map_.materials = result;
	return true;
}

void LbMine::set_path_costs(int64_t orthogonal_milli, int64_t diagonal_milli) {
	map_.orthogonal_cost_milli = orthogonal_milli;
	map_.diagonal_cost_milli = diagonal_milli;
}

bool LbMine::commit(const Ref<LbCellData> &data) {
	ERR_FAIL_COND_V(data.is_null() || data->is_taken(), false);
	LbCellData *raw = const_cast<LbCellData *>(data.ptr());
	std::unique_ptr<world::Cell> cell = raw->take();
	const Vector2i c = vec(cell->coord);
	map_.commit(std::move(cell));
	emit_signal("cell_loaded", c);
	return true;
}

bool LbMine::unload(Vector2i cell) {
	if (!map_.is_loaded(coord(cell))) {
		return false;
	}
	emit_signal("cell_unloading", cell);
	return map_.unload(coord(cell));
}

bool LbMine::is_loaded(Vector2i cell) const { return map_.is_loaded(coord(cell)); }

Array LbMine::loaded_cells() const {
	Array out;
	for (const world::Coord &c : map_.loaded_cells()) {
		out.push_back(vec(c));
	}
	return out;
}

int64_t LbMine::loaded_count() const { return static_cast<int64_t>(map_.loaded_count()); }

TypedArray<Vector2i> LbMine::missing_cells(const TypedArray<Vector2i> &centres, int64_t radius) const {
	std::set<world::Coord> missing;
	for (int64_t i = 0; i < centres.size(); i++) {
		const Vector2i c = centres[i];
		for (int64_t y = c.y - radius; y <= c.y + radius; y++) {
			for (int64_t x = c.x - radius; x <= c.x + radius; x++) {
				if (!map_.is_loaded({x, y})) {
					missing.insert({x, y});
				}
			}
		}
	}
	TypedArray<Vector2i> out;
	for (const world::Coord &m : missing) {
		out.push_back(vec(m));
	}
	return out;
}

int64_t LbMine::material_at(Vector2i tile) const {
	std::optional<world::Tile> t = map_.tile_at(coord(tile));
	return t ? t->material : -1;
}

int64_t LbMine::zone_at(Vector2i tile) const {
	const auto t = map_.tile_at(coord(tile));
	return t ? static_cast<int64_t>(t->zone) : 0;
}

int64_t LbMine::state_at(Vector2i tile) const {
	std::optional<world::Tile> t = map_.tile_at(coord(tile));
	return t ? t->state : -1;
}

int64_t LbMine::effective_material(Vector2i tile) const { return static_cast<int64_t>(map_.effective_material(coord(tile))); }
bool LbMine::is_walkable(Vector2i tile, bool doors_open) const { return map_.is_walkable(coord(tile), doors_open); }
bool LbMine::is_solid(Vector2i tile) const { return map_.is_solid(coord(tile)); }
bool LbMine::is_opaque(Vector2i tile) const { return map_.is_opaque(coord(tile)); }
bool LbMine::tapper_face_usable(Vector2i tile) const { return map_.tapper_face_usable(coord(tile)); }

int64_t LbMine::strike_milli(Vector2i tile) const {
	const uint32_t v = map_.strike_milli(coord(tile));
	return v == world::MineMap::FIELD_FAR ? -1 : static_cast<int64_t>(v);
}

int64_t LbMine::depth_milli(Vector2i tile) const {
	const uint32_t v = map_.depth_milli(coord(tile));
	return v == world::MineMap::FIELD_FAR ? -1 : static_cast<int64_t>(v);
}

int64_t LbMine::thickness(Vector2i tile) const { return map_.thickness(coord(tile)); }

void LbMine::emit_changes() {
	for (const world::TileChange &c : map_.take_changes()) {
		const Rect2i rect(static_cast<int32_t>(c.x0), static_cast<int32_t>(c.y0),
				static_cast<int32_t>(c.x1 - c.x0 + 1), static_cast<int32_t>(c.y1 - c.y0 + 1));
		emit_signal("tiles_changed", vec(c.cell), rect, String(c.reason.c_str()));
	}
}

bool LbMine::set_barrier(Vector2i cell, int64_t barrier_id, bool open) {
	const bool ok = map_.set_barrier(coord(cell), static_cast<uint32_t>(barrier_id), open);
	emit_changes();
	return ok;
}

bool LbMine::set_collapse(Vector2i cell, int64_t collapse_id, bool fallen) {
	const bool ok = map_.set_collapse(coord(cell), static_cast<uint32_t>(collapse_id), fallen);
	emit_changes();
	return ok;
}

Dictionary LbMine::path_distance(Vector2i from, Vector2i to, int64_t max_milli, bool doors_open) const {
	const world::PathResult r = map_.path_distance(coord(from), coord(to), max_milli, doors_open);
	Dictionary out;
	out["distance_milli"] = r.distance_milli;
	out["touched_unloaded"] = r.touched_unloaded;
	out["hit_max"] = r.hit_max;
	return out;
}

int64_t LbMine::flood_count(Vector2i from, int64_t max_milli, bool doors_open) const {
	return static_cast<int64_t>(map_.flood_count(coord(from), max_milli, doors_open));
}

Dictionary LbMine::nearest_open_tile(Vector2 point, const Array &exclude, int64_t max_radius) const {
	std::set<world::Coord> skip;
	for (int64_t i = 0; i < exclude.size(); i++) {
		const Vector2i t = exclude[i];
		skip.insert(coord(t));
	}
	std::optional<world::Coord> found = map_.nearest_open_tile(point.x, point.y, skip, max_radius);
	Dictionary out;
	out["found"] = found.has_value();
	out["tile"] = found ? vec(*found) : Vector2i();
	return out;
}

int64_t LbMine::digest(Vector2i cell) const {
	const world::Cell *c = map_.cell(coord(cell));
	return c ? static_cast<int64_t>(world::content_digest(*c)) : 0;
}

Array LbMine::anchors(Vector2i cell) const {
	Array out;
	const world::Cell *c = map_.cell(coord(cell));
	if (c == nullptr) {
		return out;
	}
	for (const world::Anchor &a : c->anchors) {
		Dictionary d;
		d["type"] = String(ANCHOR_NAMES[static_cast<size_t>(a.type)]);
		d["x"] = a.x;
		d["y"] = a.y;
		d["w"] = a.w;
		d["h"] = a.h;
		d["kind"] = String::utf8(a.kind.c_str());
		PackedStringArray tags;
		for (const std::string &t : a.tags) {
			tags.push_back(String::utf8(t.c_str()));
		}
		d["tags"] = tags;
		out.push_back(d);
	}
	return out;
}

Array LbMine::barriers(Vector2i cell) const {
	Array out;
	const world::Cell *c = map_.cell(coord(cell));
	if (c == nullptr) {
		return out;
	}
	for (const world::Barrier &b : c->barriers) {
		Dictionary d;
		d["id"] = static_cast<int64_t>(b.id);
		d["portal"] = static_cast<int64_t>(b.portal);
		d["open"] = b.open;
		TypedArray<Vector2i> tiles;
		int64_t material = -1;
		for (uint16_t i : b.tiles) {
			tiles.push_back(Vector2i(static_cast<int32_t>(cell.x * world::CELL_TILES + i % world::CELL_TILES),
					static_cast<int32_t>(cell.y * world::CELL_TILES + i / world::CELL_TILES)));
			if (material < 0) {
				material = c->tiles[i].material;
			}
		}
		d["tiles"] = tiles;
		d["material"] = material;
		out.push_back(d);
	}
	return out;
}

} // namespace lb::godot

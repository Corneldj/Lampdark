#include "godot/gen/lb_templates.h"

#include "core/gen/template.h"
#include "godot/world/lb_mine.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/variant/vector2i.hpp>

#include <cstring>

using namespace godot;
namespace gen = lb::core::gen;
namespace world = lb::core::world;

namespace lb::godot {

namespace {

const char *const EDGE_NAMES[] = {"north", "east", "south", "west"};

std::string to_std(const String &s) {
	CharString utf8 = s.utf8();
	return std::string(utf8.get_data(), static_cast<size_t>(utf8.length()));
}

String from_std(const std::string &s) {
	return String::utf8(s.c_str(), static_cast<int>(s.size()));
}

int64_t num(const Variant &v, int64_t fallback = 0) {
	return v.get_type() == Variant::INT || v.get_type() == Variant::FLOAT ? static_cast<int64_t>(static_cast<double>(v)) : fallback;
}

world::Coord pair_coord(const Variant &v) {
	if (v.get_type() == Variant::VECTOR2I) {
		const Vector2i c = v;
		return {c.x, c.y};
	}
	const Array a = v.get_type() == Variant::ARRAY ? Array(v) : Array();
	return a.size() == 2 ? world::Coord{num(a[0]), num(a[1])} : world::Coord{-1, -1};
}

Array coord_pair(world::Coord c) {
	Array a;
	a.push_back(c.x);
	a.push_back(c.y);
	return a;
}

bool template_from(const Dictionary &d, gen::Template &t, std::string &why) {
	t.id = to_std(String(d.get("id", "")));
	const std::optional<gen::TemplateKind> kind = gen::kind_from(to_std(String(d.get("kind", ""))));
	if (!kind) {
		why = "unknown template kind '" + to_std(String(d.get("kind", ""))) + "'";
		return false;
	}
	t.kind = *kind;
	t.biome = to_std(String(d.get("biome", "")));
	t.poi_kind = to_std(String(d.get("poi_kind", "")));
	const world::Coord fp = pair_coord(d.get("footprint", Array()));
	t.footprint_w = static_cast<int32_t>(fp.x);
	t.footprint_h = static_cast<int32_t>(fp.y);
	const Variant weight = d.get("weight", 1.0);
	t.weight = weight.get_type() == Variant::INT || weight.get_type() == Variant::FLOAT ? static_cast<double>(weight) : 1.0;
	t.author_version = static_cast<uint32_t>(num(d.get("author_version", 1), 1));
	const Array stubs = d.get("stubs", Array());
	for (int64_t i = 0; i < stubs.size(); i++) {
		const Dictionary s = stubs[i];
		gen::Stub stub;
		stub.cell = pair_coord(s.get("cell", Array()));
		const std::string edge = to_std(String(s.get("edge", "")));
		bool found = false;
		for (size_t e = 0; e < static_cast<size_t>(gen::Edge::COUNT); e++) {
			if (edge == EDGE_NAMES[e]) {
				stub.edge = static_cast<gen::Edge>(e);
				found = true;
			}
		}
		if (!found) {
			why = "stub " + std::to_string(i) + " has an unknown edge '" + edge + "'";
			return false;
		}
		stub.offset = static_cast<int32_t>(num(s.get("offset", 0)));
		stub.max_width = static_cast<int32_t>(num(s.get("max_width", 0)));
		stub.depth = static_cast<int32_t>(num(s.get("depth", 2), 2));
		stub.door = static_cast<bool>(s.get("door", false));
		t.stubs.push_back(stub);
	}
	const Array rib = d.get("rib", Array());
	for (int64_t i = 0; i < rib.size(); i++) {
		const Dictionary r = rib[i];
		t.rib.push_back(gen::RibOffset{pair_coord(r.get("cell", Array())), static_cast<uint16_t>(num(r.get("index", 0))),
				static_cast<uint32_t>(num(r.get("milli", 0)))});
	}
	const Array cells = d.get("cells", Array());
	for (int64_t i = 0; i < cells.size(); i++) {
		const Ref<LbCellData> cell = cells[i];
		if (cell.is_null() || cell->peek() == nullptr) {
			why = "cell " + std::to_string(i) + " is not an LbCellData";
			return false;
		}
		t.cells.push_back(*cell->peek());
	}
	return true;
}

Dictionary dict_from(const gen::Template &t) {
	Dictionary d;
	d["id"] = from_std(t.id);
	d["kind"] = String(gen::kind_name(t.kind));
	d["biome"] = from_std(t.biome);
	Array fp;
	fp.push_back(t.footprint_w);
	fp.push_back(t.footprint_h);
	d["footprint"] = fp;
	d["poi_kind"] = from_std(t.poi_kind);
	d["weight"] = t.weight;
	d["author_version"] = static_cast<int64_t>(t.author_version);
	Array stubs;
	for (const gen::Stub &s : t.stubs) {
		Dictionary o;
		o["cell"] = coord_pair(s.cell);
		o["edge"] = String(EDGE_NAMES[static_cast<size_t>(s.edge)]);
		o["offset"] = s.offset;
		o["max_width"] = s.max_width;
		o["depth"] = s.depth;
		o["door"] = s.door;
		stubs.push_back(o);
	}
	d["stubs"] = stubs;
	Array rib;
	for (const gen::RibOffset &r : t.rib) {
		Dictionary o;
		o["cell"] = coord_pair(r.cell);
		o["index"] = static_cast<int64_t>(r.index);
		o["milli"] = static_cast<int64_t>(r.milli);
		rib.push_back(o);
	}
	d["rib"] = rib;
	Array cells;
	for (const world::Cell &c : t.cells) {
		cells.push_back(LbCellData::wrap(c));
	}
	d["cells"] = cells;
	return d;
}

gen::ValidateParams params_from(const Dictionary &d) {
	gen::ValidateParams p;
	auto i32 = [&](const char *key, int32_t &field) {
		if (d.has(key)) {
			field = static_cast<int32_t>(num(d[key], field));
		}
	};
	auto u32 = [&](const char *key, uint32_t &field) {
		if (d.has(key)) {
			field = static_cast<uint32_t>(num(d[key], field));
		}
	};
	i32("road_width_min", p.road_width_min);
	i32("road_width_max", p.road_width_max);
	i32("chamber_min", p.chamber_min);
	i32("chamber_max", p.chamber_max);
	i32("chamber_forbidden_width", p.chamber_forbidden_width);
	u32("rib_wander_max_milli", p.rib_wander_max_milli);
	u32("tapper_reach_milli", p.tapper_reach_milli);
	i32("hook_reach_tiles", p.hook_reach_tiles);
	i32("rubble_min", p.rubble_min);
	i32("rubble_max", p.rubble_max);
	i32("rich_rock_min_thickness", p.rich_rock_min_thickness);
	i32("gas_area_min", p.gas_area_min);
	i32("gas_area_max", p.gas_area_max);
	i32("gas_dead_end_min", p.gas_dead_end_min);
	i32("gas_dead_end_max", p.gas_dead_end_max);
	i32("collapse_length_max", p.collapse_length_max);
	i32("biome_stub_width_max", p.biome_stub_width_max);
	if (d.has("poi_slots")) {
		const Dictionary slots = d["poi_slots"];
		const Array keys = slots.keys();
		for (int64_t i = 0; i < keys.size(); i++) {
			p.poi_slots[to_std(String(keys[i]))] = static_cast<int32_t>(num(slots[keys[i]]));
		}
	}
	if (d.has("poi_phone_kinds")) {
		const Array kinds = d["poi_phone_kinds"];
		for (int64_t i = 0; i < kinds.size(); i++) {
			p.poi_phone_kinds.insert(to_std(String(kinds[i])));
		}
	}
	if (d.has("lair_kind")) {
		p.lair_kind = to_std(String(d["lair_kind"]));
	}
	return p;
}

} // namespace

void LbTemplates::_bind_methods() {
	ClassDB::bind_static_method("LbTemplates", D_METHOD("validate", "template_dict", "params"), &LbTemplates::validate);
	ClassDB::bind_static_method("LbTemplates", D_METHOD("encode_pack", "set_version", "templates"), &LbTemplates::encode_pack);
	ClassDB::bind_static_method("LbTemplates", D_METHOD("decode_pack", "bytes"), &LbTemplates::decode_pack);
	ClassDB::bind_integer_constant("LbTemplates", "", "PACK_FORMAT", static_cast<int64_t>(gen::PACK_FORMAT));
}

Array LbTemplates::validate(const Dictionary &template_dict, const Dictionary &params) {
	Array out;
	gen::Template t;
	std::string why;
	std::vector<gen::Problem> problems;
	if (!template_from(template_dict, t, why)) {
		gen::Problem p;
		p.rule = "format";
		p.message = why;
		problems.push_back(p);
	} else {
		problems = gen::validate(t, params_from(params));
	}
	for (const gen::Problem &p : problems) {
		Dictionary d;
		d["rule"] = from_std(p.rule);
		d["cell"] = Vector2i(static_cast<int32_t>(p.cell.x), static_cast<int32_t>(p.cell.y));
		d["x"] = p.x;
		d["y"] = p.y;
		d["message"] = from_std(p.message);
		d["text"] = from_std(gen::describe(t, p));
		out.push_back(d);
	}
	return out;
}

PackedByteArray LbTemplates::encode_pack(const String &set_version, const Array &templates) {
	PackedByteArray out;
	std::vector<gen::Template> list;
	for (int64_t i = 0; i < templates.size(); i++) {
		gen::Template t;
		std::string why;
		if (!template_from(templates[i], t, why)) {
			UtilityFunctions::push_error("LbTemplates: template ", i, ": ", from_std(why));
			return out;
		}
		list.push_back(std::move(t));
	}
	const std::vector<uint8_t> bytes = gen::encode_pack(to_std(set_version), list);
	out.resize(static_cast<int64_t>(bytes.size()));
	if (!bytes.empty()) {
		std::memcpy(out.ptrw(), bytes.data(), bytes.size());
	}
	return out;
}

Dictionary LbTemplates::decode_pack(const PackedByteArray &bytes) {
	Dictionary out;
	const std::vector<uint8_t> in(bytes.ptr(), bytes.ptr() + bytes.size());
	const std::optional<gen::Pack> pack = gen::decode_pack(in);
	if (!pack) {
		return out;
	}
	out["set_version"] = from_std(pack->set_version);
	Array templates;
	for (const gen::Template &t : pack->templates) {
		templates.push_back(dict_from(t));
	}
	out["templates"] = templates;
	return out;
}

} // namespace lb::godot

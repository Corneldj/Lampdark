#include "godot/gen/lb_layouts.h"

#include "godot/gen/lb_templates.h"
#include "godot/world/lb_mine.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/rect2i.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <cmath>

using namespace godot;
namespace gen = lb::core::gen;

namespace lb::godot {

namespace {

const char *const SIDES[] = {"north", "east", "south", "west"};

std::optional<gen::Edge> side_from(const String &side) {
	for (int e = 0; e < 4; e++) {
		if (side == SIDES[e]) {
			return static_cast<gen::Edge>(e);
		}
	}
	return std::nullopt;
}

Dictionary socket_dict(const gen::Socket &s) {
	Dictionary d;
	d["open"] = s.open;
	d["offset"] = s.offset;
	d["width"] = s.width;
	d["forced"] = s.forced;
	return d;
}

std::string to_std(const String &s) {
	const CharString utf8 = s.utf8();
	return std::string(utf8.get_data(), static_cast<size_t>(utf8.length()));
}

// GEN-06's table from {rings: [[[biome, weight], ...], ...], widths: {biome: [min, max]}, ring_bounds}.
gen::BiomeTable biome_table(const Dictionary &d) {
	gen::BiomeTable t;
	const Array rings = d.get("rings", Array());
	for (int64_t r = 0; r < rings.size(); r++) {
		const Array pairs = rings[r];
		std::vector<std::pair<std::string, double>> ring;
		for (int64_t i = 0; i < pairs.size(); i++) {
			const Array pair = pairs[i];
			if (pair.size() == 2) {
				ring.emplace_back(to_std(String(pair[0])), static_cast<double>(pair[1]));
			}
		}
		t.rings.push_back(ring);
	}
	const Dictionary widths = d.get("widths", Dictionary());
	const Array names = widths.keys();
	for (int64_t i = 0; i < names.size(); i++) {
		const Array range = widths[names[i]];
		if (range.size() == 2) {
			t.widths[to_std(String(names[i]))] = {static_cast<int32_t>(static_cast<int64_t>(range[0])), static_cast<int32_t>(static_cast<int64_t>(range[1]))};
		}
	}
	const Array bounds = d.get("ring_bounds", Array());
	if (bounds.size() > 0) {
		t.ring_bounds.clear();
		for (int64_t i = 0; i < bounds.size(); i++) {
			t.ring_bounds.push_back(static_cast<int64_t>(bounds[i]));
		}
	}
	return t;
}

std::vector<int32_t> ints(const Variant &v, std::vector<int32_t> fallback) {
	if (v.get_type() != Variant::ARRAY && v.get_type() != Variant::PACKED_INT32_ARRAY && v.get_type() != Variant::PACKED_INT64_ARRAY) {
		return fallback;
	}
	const Array a = v;
	std::vector<int32_t> out;
	for (int64_t i = 0; i < a.size(); i++) {
		out.push_back(static_cast<int32_t>(static_cast<int64_t>(a[i])));
	}
	return out;
}

std::vector<std::string> strings(const Variant &v) {
	std::vector<std::string> out;
	if (v.get_type() != Variant::ARRAY && v.get_type() != Variant::PACKED_STRING_ARRAY) {
		return out;
	}
	const Array a = v;
	for (int64_t i = 0; i < a.size(); i++) {
		out.push_back(to_std(String(a[i])));
	}
	return out;
}

// Three [lo, hi] pairs, one per list kind (Short, Standard, Full).
void pairs3(const Variant &v, std::array<std::pair<int64_t, int64_t>, 3> &out) {
	if (v.get_type() != Variant::ARRAY) {
		return;
	}
	const Array a = v;
	for (int64_t i = 0; i < a.size() && i < 3; i++) {
		const Array pair = a[i];
		if (pair.size() == 2) {
			out[static_cast<size_t>(i)] = {static_cast<int64_t>(pair[0]), static_cast<int64_t>(pair[1])};
		}
	}
}

int64_t whole(const Dictionary &d, const char *key, int64_t fallback) {
	return d.has(key) ? static_cast<int64_t>(std::llround(static_cast<double>(d[key]))) : fallback;
}

uint32_t ppm(const Dictionary &d, const char *key, uint32_t fallback) {
	return d.has(key) ? static_cast<uint32_t>(std::llround(static_cast<double>(d[key]) * 1000000.0)) : fallback;
}

// GEN-08's numbers from the tuning dictionary run_plan.gd builds; anything missing keeps its default.
gen::PlanParams plan_params(const Dictionary &t, const std::vector<int64_t> &ring_bounds) {
	gen::PlanParams p;
	p.ring_bounds = ring_bounds;
	pairs3(t.get("substation", Variant()), p.substation);
	pairs3(t.get("hoard", Variant()), p.hoard);
	pairs3(t.get("lair", Variant()), p.lair);
	pairs3(t.get("parts_rings", Variant()), p.parts_rings);
	if (t.has("lair_min_bearing_deg")) {
		p.lair_min_bearing_deg = static_cast<double>(t["lair_min_bearing_deg"]);
	}
	p.drum_gear_ring = whole(t, "drum_gear_ring", p.drum_gear_ring);
	p.tools_ring = whole(t, "tools_ring", p.tools_ring);
	p.paraffin_factor = whole(t, "paraffin_factor", p.paraffin_factor);
	p.paraffin_max_ring = whole(t, "paraffin_max_ring", p.paraffin_max_ring);
	p.fuel_cans_min = whole(t, "fuel_cans_min", p.fuel_cans_min);
	p.fuel_cans_max = whole(t, "fuel_cans_max", p.fuel_cans_max);
	p.spare_ppm = ppm(t, "spare_probability", p.spare_ppm);
	p.revolver_ppm = ppm(t, "revolver_probability", p.revolver_ppm);
	p.boxes_min = whole(t, "boxes_min", p.boxes_min);
	p.boxes_max = whole(t, "boxes_max", p.boxes_max);
	p.max_retries = static_cast<int32_t>(whole(t, "max_retries", p.max_retries));
	p.max_per_region = static_cast<int32_t>(whole(t, "max_per_region", p.max_per_region));
	const Dictionary fw = t.get("footprint_w", Dictionary());
	const Dictionary fh = t.get("footprint_h", Dictionary());
	const Dictionary rmin = t.get("ring_min", Dictionary());
	const Dictionary rmax = t.get("ring_max", Dictionary());
	for (size_t k = 0; k < static_cast<size_t>(gen::PoiKind::COUNT); k++) {
		const String name = String::utf8(gen::poi_kind_name(static_cast<gen::PoiKind>(k)));
		if (fw.has(name) && fh.has(name)) {
			p.footprint[k] = {static_cast<int32_t>(static_cast<int64_t>(fw[name])), static_cast<int32_t>(static_cast<int64_t>(fh[name]))};
		}
		if (rmin.has(name) && rmax.has(name)) {
			p.rings[k] = {static_cast<int64_t>(rmin[name]), static_cast<int64_t>(rmax[name])};
		}
	}
	return p;
}

// GEN-09's numbers from the poi dictionary mine_layouts.gd builds; anything missing keeps its default.
void poi_params(const Dictionary &d, const std::vector<int64_t> &ring_bounds, gen::PoiParams &p, gen::PoiContentsParams &c) {
	p.ring_bounds = ring_bounds;
	p.per_region_min = static_cast<int32_t>(whole(d, "per_region_min", p.per_region_min));
	p.per_region_max = static_cast<int32_t>(whole(d, "per_region_max", p.per_region_max));
	p.two_ppm = ppm(d, "two_probability", p.two_ppm);
	for (const auto &[key, out] : {std::pair<const char *, uint32_t *>{"lamp_cabin_regions_per", &p.lamp_cabin_ppm},
				 std::pair<const char *, uint32_t *>{"first_aid_regions_per", &p.first_aid_ppm}}) {
		if (d.has(key) && static_cast<double>(d[key]) > 0.0) {
			*out = static_cast<uint32_t>(std::llround(1000000.0 / static_cast<double>(d[key])));
		}
	}
	p.fit_tries = static_cast<int32_t>(whole(d, "fit_tries", p.fit_tries));
	p.canary_max = static_cast<int32_t>(whole(d, "canary_max_per_run", p.canary_max));
	p.min_ring = whole(d, "min_ring", p.min_ring);
	if (d.has("lair_biome")) {
		p.lair_biome = to_std(String(d["lair_biome"]));
	}
	const Dictionary rmin = d.get("ring_min", Dictionary());
	const Dictionary rmax = d.get("ring_max", Dictionary());
	const Dictionary contents = d.get("contents", Dictionary());
	for (size_t k = 0; k < static_cast<size_t>(gen::PoiKind::COUNT); k++) {
		const String name = String::utf8(gen::poi_kind_name(static_cast<gen::PoiKind>(k)));
		if (rmin.has(name) && rmax.has(name)) {
			p.rings[k] = {static_cast<int64_t>(rmin[name]), static_cast<int64_t>(rmax[name])};
		}
		if (contents.has(name)) {
			const Dictionary table = contents[name];
			const Array keys = table.keys();
			for (int64_t i = 0; i < keys.size(); i++) {
				c.tables[k][to_std(String(keys[i]))] = static_cast<double>(table[keys[i]]);
			}
		}
	}
	const Array weights = d.get("weights", Array());
	if (weights.size() > 0) {
		p.weights.assign(static_cast<size_t>(weights.size()), {});
		for (int64_t r = 0; r < weights.size(); r++) {
			const Dictionary row = weights[r];
			for (size_t k = 0; k < static_cast<size_t>(gen::PoiKind::COUNT); k++) {
				const String name = String::utf8(gen::poi_kind_name(static_cast<gen::PoiKind>(k)));
				p.weights[static_cast<size_t>(r)][k] = row.has(name) ? static_cast<double>(row[name]) : 0.0;
			}
		}
	}
	c.fuel_cans_min = whole(d, "fuel_cans_min", c.fuel_cans_min);
	c.fuel_cans_max = whole(d, "fuel_cans_max", c.fuel_cans_max);
	const Array oil = d.get("found_oil", Array());
	if (oil.size() == 2) {
		c.found_oil_min = static_cast<double>(oil[0]);
		c.found_oil_max = static_cast<double>(oil[1]);
	}
	const Array notches = d.get("found_notches", Array());
	if (notches.size() == 2) {
		c.found_notches_min = static_cast<int64_t>(std::llround(static_cast<double>(notches[0])));
		c.found_notches_max = static_cast<int64_t>(std::llround(static_cast<double>(notches[1])));
	}
	const Dictionary chances = d.get("remains_chances", Dictionary());
	for (auto &[name, chance] : c.remains_chances) {
		if (chances.has(String::utf8(name.c_str()))) {
			chance = static_cast<double>(chances[String::utf8(name.c_str())]);
		}
	}
	c.remains_items_max = whole(d, "remains_items_max", c.remains_items_max);
	if (d.has("dry_stores_factor")) {
		c.dry_stores_factor = static_cast<double>(d["dry_stores_factor"]);
	}
}

Vector2i v2(const lb::core::world::Coord &c) {
	return Vector2i(static_cast<int32_t>(c.x), static_cast<int32_t>(c.y));
}

Array cells_array(const std::vector<lb::core::world::Coord> &cells) {
	Array out;
	for (const lb::core::world::Coord &c : cells) {
		out.append(v2(c));
	}
	return out;
}

Dictionary poi_dict(const gen::Poi &p) {
	Dictionary d;
	d["region"] = v2(p.id.region);
	d["index"] = p.id.index;
	d["kind"] = String::utf8(gen::poi_kind_name(p.kind));
	d["planned"] = p.planned;
	d["template"] = p.shape != nullptr ? String::utf8(p.shape->base->id.c_str()) : String();
	d["orientation"] = p.shape != nullptr ? p.shape->orientation : 0;
	d["origin"] = v2(p.origin);
	d["size"] = Vector2i(p.w, p.h);
	d["door"] = v2(p.door);
	d["door_side"] = String(SIDES[static_cast<size_t>(p.door_side)]);
	d["cells"] = cells_array(p.cells());
	d["biome"] = String::utf8(p.biome.c_str());
	Array slots;
	for (const gen::TileRect &r : p.slots()) {
		slots.append(Rect2i(static_cast<int32_t>(r.x), static_cast<int32_t>(r.y), r.w, r.h));
	}
	d["slots"] = slots;
	return d;
}

PackedByteArray packed(const std::vector<uint8_t> &bytes) {
	PackedByteArray out;
	out.resize(static_cast<int64_t>(bytes.size()));
	for (size_t i = 0; i < bytes.size(); i++) {
		out.set(static_cast<int64_t>(i), bytes[i]);
	}
	return out;
}

std::vector<uint8_t> unpacked(const PackedByteArray &bytes) {
	return std::vector<uint8_t>(bytes.ptr(), bytes.ptr() + bytes.size());
}


int64_t ppm_of(const Dictionary &d, const char *key, int64_t fallback) {
	return d.has(key) ? static_cast<int64_t>(std::llround(static_cast<double>(d[key]) * 1000000.0)) : fallback;
}

int64_t int_of(const Dictionary &d, const char *key, int64_t fallback) {
	return d.has(key) ? static_cast<int64_t>(std::llround(static_cast<double>(d[key]))) : fallback;
}

void pair_of(const Dictionary &d, const char *key, int64_t &lo, int64_t &hi, double scale = 1.0) {
	if (!d.has(key)) {
		return;
	}
	const Array a = d[key];
	if (a.size() == 2) {
		lo = static_cast<int64_t>(std::llround(static_cast<double>(a[0]) * scale));
		hi = static_cast<int64_t>(std::llround(static_cast<double>(a[1]) * scale));
	}
}

// GEN-10's numbers (MineLayouts.place_params builds them from tuning).
gen::PlacementParams place_params(const Dictionary &d) {
	gen::PlacementParams p;
	p.remains_ppm = ppm_of(d, "remains_probability", p.remains_ppm);
	pair_of(d, "remains_rings", p.remains_ring_min, p.remains_ring_max);
	if (d.has("remains_items")) {
		// The table's order: lamp, flare, kit, tool, note (the first two kept).
		const Dictionary items = d["remains_items"];
		std::vector<std::pair<std::string, int64_t>> list;
		for (const char *name : {"lamp", "flare", "kit", "tool", "note"}) {
			if (items.has(name)) {
				list.emplace_back(name, static_cast<int64_t>(std::llround(static_cast<double>(items[name]) * 1000000.0)));
			}
		}
		p.remains_items = list;
	}
	p.remains_items_max = int_of(d, "remains_items_max", p.remains_items_max);
	pair_of(d, "found_oil", p.found_oil_min_milli, p.found_oil_max_milli, 1000.0);
	pair_of(d, "found_notches", p.found_notches_min, p.found_notches_max);
	p.paraffin_ppm = ppm_of(d, "paraffin_probability", p.paraffin_ppm);
	pair_of(d, "paraffin_rings", p.paraffin_ring_min, p.paraffin_ring_max);
	p.electric_lamp_ppm = ppm_of(d, "electric_lamp_probability", p.electric_lamp_ppm);
	p.electric_lamp_max = int_of(d, "electric_lamp_max", p.electric_lamp_max);
	p.electric_lamp_min_ring = int_of(d, "electric_lamp_min_ring", p.electric_lamp_min_ring);
	p.revolver_rounds = int_of(d, "revolver_rounds", p.revolver_rounds);
	p.box_rounds = int_of(d, "box_rounds", p.box_rounds);
	p.phone_ring12_ppm = ppm_of(d, "phone_ring12_probability", p.phone_ring12_ppm);
	p.phone_beyond_ppm = ppm_of(d, "phone_beyond_probability", p.phone_beyond_ppm);
	p.phones_near_gates = int_of(d, "phones_near_gates", p.phones_near_gates);
	pair_of(d, "phones_near_gates_path", p.phones_near_gates_min_path, p.phones_near_gates_max_path);
	p.air_door_ppm = ppm_of(d, "air_door_probability", p.air_door_ppm);
	p.collapse_ppm = ppm_of(d, "collapse_probability", p.collapse_ppm);
	p.collapse_min_from_basecamp = int_of(d, "collapse_min_from_basecamp", p.collapse_min_from_basecamp);
	p.collapse_min_spacing = int_of(d, "collapse_min_spacing", p.collapse_min_spacing);
	p.collapse_min_from_sites = int_of(d, "collapse_min_from_sites", p.collapse_min_from_sites);
	p.firedamp_ring2_ppm = ppm_of(d, "firedamp_ring2_probability", p.firedamp_ring2_ppm);
	p.firedamp_beyond_ppm = ppm_of(d, "firedamp_beyond_probability", p.firedamp_beyond_ppm);
	p.firedamp_black_seam_ppm = ppm_of(d, "firedamp_black_seam_probability", p.firedamp_black_seam_ppm);
	p.blackdamp_ppm = ppm_of(d, "blackdamp_probability", p.blackdamp_ppm);
	p.man_trap_ppm = ppm_of(d, "man_trap_probability", p.man_trap_ppm);
	p.man_trap_min_ring = int_of(d, "man_trap_min_ring", p.man_trap_min_ring);
	p.staple_pit_ppm = ppm_of(d, "staple_pit_probability", p.staple_pit_ppm);
	p.staple_pit_min_ring = int_of(d, "staple_pit_min_ring", p.staple_pit_min_ring);
	p.sump_mud_ppm = ppm_of(d, "sump_mud_probability", p.sump_mud_ppm);
	p.sump_mud_min_ring = int_of(d, "sump_mud_min_ring", p.sump_mud_min_ring);
	p.traps_min_ring = int_of(d, "traps_min_ring", p.traps_min_ring);
	for (const auto &[key, table] : {std::pair<const char *, std::vector<int64_t> *>{"staged_traps_min_ring", &p.staged_traps_min_ring},
				 std::pair<const char *, std::vector<int64_t> *>{"staged_roost_min_from_shaft", &p.staged_roost_min_from_shaft}}) {
		if (d.has(key)) {
			const Array a = d[key];
			table->clear();
			for (int64_t i = 0; i < a.size(); i++) {
				table->push_back(static_cast<int64_t>(std::llround(static_cast<double>(a[i]))));
			}
		}
	}
	p.roost_min_from_shaft = int_of(d, "roost_min_from_shaft", p.roost_min_from_shaft);
	pair_of(d, "roosts", p.roosts_min, p.roosts_max);
	p.roost_max_from_hoard = int_of(d, "roost_max_from_hoard", p.roost_max_from_hoard);
	p.coat_heap_near_hoard = int_of(d, "coat_heap_near_hoard", p.coat_heap_near_hoard);
	p.coat_heap_near_ppm = ppm_of(d, "coat_heap_near_probability", p.coat_heap_near_ppm);
	p.coat_heap_far_ppm = ppm_of(d, "coat_heap_far_probability", p.coat_heap_far_ppm);
	pair_of(d, "coat_heaps", p.coat_heaps_min, p.coat_heaps_max);
	p.rich_rock_per_region = int_of(d, "rich_rock_per_region", p.rich_rock_per_region);
	p.rich_rock_min_thickness = int_of(d, "rich_rock_min_thickness", p.rich_rock_min_thickness);
	p.landmark_no_repeat_cells = int_of(d, "landmark_no_repeat_cells", p.landmark_no_repeat_cells);
	p.landmark_palette = int_of(d, "landmark_palette", p.landmark_palette);
	p.canary_max = int_of(d, "canary_max", p.canary_max);
	return p;
}

String placement_id(uint64_t id) {
	return String("p") + String::num_uint64(id, 16).lpad(16, "0");
}

Dictionary placement_dict(const gen::Placement &x) {
	Dictionary d;
	d["kind"] = String(gen::placed_kind_name(x.kind));
	d["thing"] = String::utf8(x.thing.c_str());
	d["source"] = String::utf8(x.source.c_str());
	d["anchor"] = x.anchor;
	d["tile"] = Vector2i(static_cast<int32_t>(x.tile.x), static_cast<int32_t>(x.tile.y));
	d["size"] = Vector2i(x.w, x.h);
	d["count"] = x.count;
	d["oil_milli"] = x.oil_milli;
	d["notches"] = x.notches;
	d["variant"] = x.variant;
	d["collapse"] = static_cast<int64_t>(x.collapse);
	d["with"] = x.with;
	d["id"] = placement_id(x.id);
	return d;
}

Rect2i box_rect(const gen::TileBox &b) {
	return Rect2i(static_cast<int32_t>(b.x), static_cast<int32_t>(b.y), b.w, b.h);
}

} // namespace

void LbLayouts::_bind_methods() {
	ClassDB::bind_method(D_METHOD("load_pack", "bytes"), &LbLayouts::load_pack);
	ClassDB::bind_method(D_METHOD("set_version"), &LbLayouts::set_version);
	ClassDB::bind_method(D_METHOD("configure", "seed", "params"), &LbLayouts::configure);
	ClassDB::bind_method(D_METHOD("force_socket", "cell", "side", "socket"), &LbLayouts::force_socket);
	ClassDB::bind_method(D_METHOD("socket", "cell", "side"), &LbLayouts::socket);
	ClassDB::bind_method(D_METHOD("biome_of", "cell"), &LbLayouts::biome_of);
	ClassDB::bind_method(D_METHOD("road_of", "cell"), &LbLayouts::road_of);
	ClassDB::bind_method(D_METHOD("derive", "cell", "reroll"), &LbLayouts::derive);
	ClassDB::bind_method(D_METHOD("derive_final", "cell"), &LbLayouts::derive_final);
	ClassDB::bind_method(D_METHOD("placement_report", "cell"), &LbLayouts::placement_report);
	ClassDB::bind_method(D_METHOD("validate_run_start"), &LbLayouts::validate_run_start);
	ClassDB::bind_method(D_METHOD("validator_stats"), &LbLayouts::validator_stats);
	ClassDB::bind_method(D_METHOD("fallback_coverage", "biome", "widths"), &LbLayouts::fallback_coverage);
	ClassDB::bind_method(D_METHOD("plan", "params"), &LbLayouts::plan);
	ClassDB::bind_method(D_METHOD("load_plan", "bytes"), &LbLayouts::load_plan);
	ClassDB::bind_method(D_METHOD("plan_bytes"), &LbLayouts::plan_bytes);
	ClassDB::bind_method(D_METHOD("plan_dict"), &LbLayouts::plan_dict);
	ClassDB::bind_method(D_METHOD("is_spine_cell", "cell"), &LbLayouts::is_spine_cell);
	ClassDB::bind_method(D_METHOD("set_home", "name", "bytes"), &LbLayouts::set_home);
	ClassDB::bind_method(D_METHOD("home", "name"), &LbLayouts::home);
	ClassDB::bind_method(D_METHOD("poi_at", "cell"), &LbLayouts::poi_at);
	ClassDB::bind_method(D_METHOD("poi_region", "region"), &LbLayouts::poi_region);
	ClassDB::bind_method(D_METHOD("poi_contents", "region", "index"), &LbLayouts::poi_contents);
	ClassDB::bind_static_method("LbLayouts", D_METHOD("canary_home", "region"), &LbLayouts::canary_home);
	ClassDB::bind_method(D_METHOD("make_homes"), &LbLayouts::make_homes);
	ClassDB::bind_method(D_METHOD("homes_dict"), &LbLayouts::homes_dict);
	ClassDB::bind_method(D_METHOD("place", "cell"), &LbLayouts::place);
	ClassDB::bind_method(D_METHOD("dress", "cell", "data"), &LbLayouts::dress);
	ClassDB::bind_method(D_METHOD("find_counts", "cells"), &LbLayouts::find_counts);
	ClassDB::bind_method(D_METHOD("rich_rock_masses", "region"), &LbLayouts::rich_rock_masses);
	ClassDB::bind_method(D_METHOD("set_caching", "on"), &LbLayouts::set_caching);
	ClassDB::bind_method(D_METHOD("clear_caches"), &LbLayouts::clear_caches);
	ClassDB::bind_method(D_METHOD("set_verify", "on"), &LbLayouts::set_verify);
	ClassDB::bind_method(D_METHOD("verify_failures"), &LbLayouts::verify_failures);
	ClassDB::bind_method(D_METHOD("start_pool", "threads", "background"), &LbLayouts::start_pool, DEFVAL(false));
	ClassDB::bind_method(D_METHOD("stop_pool"), &LbLayouts::stop_pool);
	ClassDB::bind_method(D_METHOD("want", "cell", "priority"), &LbLayouts::want);
	ClassDB::bind_method(D_METHOD("unwant", "cell"), &LbLayouts::unwant);
	ClassDB::bind_method(D_METHOD("take", "max"), &LbLayouts::take);
	ClassDB::bind_method(D_METHOD("pool_stats"), &LbLayouts::pool_stats);
	ClassDB::bind_method(D_METHOD("set_window", "radius", "prefetch_radius"), &LbLayouts::set_window);
	ClassDB::bind_method(D_METHOD("update_window", "holders", "mine"), &LbLayouts::update_window);
	ClassDB::bind_method(D_METHOD("evictions_now", "mine", "pinned", "evict", "max_live"), &LbLayouts::evictions_now);
	ClassDB::bind_static_method("LbLayouts", D_METHOD("required_cells", "holders", "radius"), &LbLayouts::required_cells);
	ClassDB::bind_static_method("LbLayouts", D_METHOD("evictions", "loaded", "holders", "pinned", "generate", "evict", "max_live"),
			&LbLayouts::evictions);
}

LbLayouts::LbLayouts() : set_(std::make_shared<gen::TemplateSet>()) {
#ifdef DEBUG_ENABLED
	verify_ = true; // debug builds derive every layout twice, caches bypassed, and compare (GEN-05)
#endif
	cells_ = std::make_unique<gen::UniformCells>("", header_.sockets.widths);
	rebuild();
}

void LbLayouts::rebuild() {
	pool_.reset(); // its jobs belong to the old deriver
	gen::DeriveInputs in;
	in.header = &header_;
	in.templates = set_.get();
	in.cells = cells_.get();
	deriver_.reset();
	spine_sockets_.reset();
	poi_sockets_.reset();
	road_sockets_.reset();
	poi_cells_.reset();
	pois_.reset();
	road_cells_.reset();
	roads_.reset();
	if (has_roads_) {
		// The arches run into the cells beyond base camp's open edges (GEN-02): no old fall there.
		std::set<lb::core::world::Coord> arch_cells;
		for (int e = 0; e < 4; e++) {
			const std::optional<gen::Socket> s = header_.forced.query(gen::edge_of({0, 0}, static_cast<gen::Edge>(e)));
			if (s && s->open) {
				arch_cells.insert(gen::neighbour({0, 0}, static_cast<gen::Edge>(e)));
			}
		}
		roads_ = std::make_unique<gen::MainRoads>(header_.seed, road_params_, ring_bounds_, arch_cells);
		road_cells_ = std::make_unique<gen::MainRoadCells>(*roads_, *cells_);
		in.cells = road_cells_.get();
	}
	// GEN-09: points of interest over the roads and biomes, their sockets first among the rules.
	std::function<bool(lb::core::world::Coord)> is_main_road;
	if (roads_) {
		const gen::MainRoads *roads = roads_.get();
		is_main_road = [roads](lb::core::world::Coord c) { return roads->is_main_road_cell(c); };
	}
	if (has_poi_) {
		gen::PoiWorld world;
		world.is_main_road_cell = is_main_road;
		if (roads_) {
			const gen::MainRoads *roads = roads_.get();
			world.is_old_fall = [roads](lb::core::world::Coord c) { return roads->old_fall(c); };
		}
		poi_params_.ring_bounds = ring_bounds_;
		if (!poi_shapes_ || poi_shapes_set_ != set_ || poi_shapes_offsets_ != header_.sockets.offsets) {
			poi_shapes_ = std::make_shared<const gen::PoiShapes>(*set_, header_.sockets.offsets);
			poi_shapes_set_ = set_;
			poi_shapes_offsets_ = header_.sockets.offsets;
		}
		pois_ = std::make_unique<gen::PointsOfInterest>(header_, poi_shapes_, poi_params_, world);
		pois_->set_caching(caching_);
		std::function<std::vector<int32_t>(const std::string &)> widths;
		if (const auto *biomes = dynamic_cast<const gen::BiomeCells *>(cells_.get())) {
			const gen::BiomeTable table = biomes->table();
			const gen::SocketParams params = header_.sockets;
			widths = [table, params](const std::string &biome) { return gen::biome_widths(table, biome, params); };
		}
		poi_cells_ = std::make_unique<gen::PoiCells>(*in.cells, *pois_, widths);
		in.cells = poi_cells_.get();
		poi_sockets_ = std::make_unique<gen::PoiSockets>(*pois_, *in.cells, header_.sockets, header_.seed, is_main_road);
		in.providers.push_back(poi_sockets_.get());
	}
	if (roads_) {
		road_sockets_ = std::make_unique<gen::MainRoadSockets>(*roads_, *in.cells, header_.sockets);
		in.providers.push_back(road_sockets_.get());
	}
	// GEN-08: spine edges forced open after main roads; spine cells take no old fall.
	if (!header_.plan.spines.empty()) {
		spine_sockets_ = std::make_unique<gen::SpineSockets>(header_.seed, header_.plan, *in.cells, header_.sockets);
		in.providers.push_back(spine_sockets_.get());
	}
	if (roads_) {
		const gen::SpineSockets *spines = spine_sockets_.get();
		roads_->is_spine = [spines](lb::core::world::Coord c) { return spines != nullptr && spines->is_spine_cell(c); };
	}
	// GEN-12: each cell's final layout passes the validator's phase 1; its counts start again.
	in.validator = has_validator_ ? &validator_params_ : nullptr;
	in.counters = counters_.get();
	counters_->clear();
	deriver_ = std::make_unique<gen::Deriver>(in);
	deriver_->set_caching(caching_);
	deriver_->set_verify(verify_);
	place_world_ = std::make_unique<gen::DerivedWorld>(header_, *deriver_, *cells_, roads_.get(), spine_sockets_.get(), pois_.get(),
			&contents_params_, ring_bounds_);
	if (pool_threads_ >= 0) {
		pool_ = std::make_unique<gen::GenPool>(*deriver_, static_cast<int32_t>(pool_threads_), pool_background_);
	}
	reset_window();
}

void LbLayouts::reset_window() {
	window_ = std::make_unique<gen::Window>(window_radius_, window_prefetch_);
	asked_.clear();
}

bool LbLayouts::load_pack(const PackedByteArray &bytes) {
	auto next = std::make_shared<gen::TemplateSet>();
	const bool ok = next->load(std::vector<uint8_t>(bytes.ptr(), bytes.ptr() + bytes.size()));
	set_ = next;
	rebuild();
	return ok;
}

String LbLayouts::set_version() const {
	return String::utf8(set_->set_version().c_str());
}

void LbLayouts::configure(int64_t seed, const Dictionary &params) {
	header_.seed = static_cast<uint64_t>(seed);
	if (params.has("open_probability")) {
		header_.sockets.open_ppm = static_cast<uint32_t>(std::llround(static_cast<double>(params["open_probability"]) * 1000000.0));
	}
	header_.sockets.offsets = ints(params.get("offsets", Variant()), header_.sockets.offsets);
	header_.sockets.widths = ints(params.get("widths", Variant()), header_.sockets.widths);
	if (params.has("reroll_limit")) {
		header_.reroll_limit = static_cast<int32_t>(static_cast<int64_t>(params["reroll_limit"]));
	}
	if (params.has("biomes")) {
		const gen::BiomeTable table = biome_table(params["biomes"]);
		ring_bounds_ = table.ring_bounds;
		cells_ = std::make_unique<gen::BiomeCells>(header_.seed, table, header_.sockets);
	} else {
		cells_ = std::make_unique<gen::UniformCells>(to_std(String(params.get("biome", ""))), header_.sockets.widths);
	}
	has_poi_ = params.has("poi");
	if (has_poi_) {
		poi_params_ = gen::PoiParams();
		contents_params_ = gen::PoiContentsParams();
		poi_params(params["poi"], ring_bounds_, poi_params_, contents_params_);
	}
	has_place_ = params.has("place");
	place_params_ = has_place_ ? place_params(params["place"]) : gen::PlacementParams();
	has_validator_ = params.has("validate");
	validator_params_ = gen::ValidatorParams();
	if (has_validator_) {
		const Dictionary v = params["validate"];
		if (v.has("rules")) {
			validator_params_.rules = template_rules(v["rules"]);
		}
		validator_params_.max_retries = static_cast<int32_t>(int_of(v, "max_retries", validator_params_.max_retries));
		validator_params_.max_replans = static_cast<int32_t>(int_of(v, "max_replans", validator_params_.max_replans));
		const Dictionary arch = v.get("arch_reach", Dictionary());
		for (int e = 0; e < 4; e++) {
			validator_params_.arch_reach[static_cast<size_t>(e)] = static_cast<int32_t>(int_of(arch, SIDES[e], 0));
		}
	}
	has_roads_ = params.has("main_roads");
	if (has_roads_) {
		const Dictionary r = params["main_roads"];
		auto get = [&](const char *key, int32_t fallback) {
			return r.has(key) ? static_cast<int32_t>(std::llround(static_cast<double>(r[key]))) : fallback;
		};
		road_params_.spacing = get("spacing", road_params_.spacing);
		road_params_.width = get("width", road_params_.width);
		road_params_.offset = get("offset", road_params_.offset);
		road_params_.run_min = get("run_min", road_params_.run_min);
		road_params_.run_max = get("run_max", road_params_.run_max);
		road_params_.max_ring = get("max_ring", road_params_.max_ring);
		if (r.has("old_fall_probability")) {
			road_params_.old_fall_ppm = static_cast<uint32_t>(std::llround(static_cast<double>(r["old_fall_probability"]) * 1000000.0));
		}
	}
	rebuild();
}

Dictionary LbLayouts::plan(const Dictionary &params) {
	header_.list_kind = static_cast<int32_t>(static_cast<int64_t>(params.get("list_kind", 1)));
	header_.jobs = strings(params.get("jobs", Variant()));
	header_.cans = static_cast<int32_t>(static_cast<int64_t>(params.get("cans", 4)));
	header_.solo = static_cast<bool>(params.get("solo", false));
	header_.draw = strings(params.get("draw", Variant()));
	header_.staging = to_std(String(params.get("staging", "")));
	header_.hard_variant = to_std(String(params.get("hard_variant", "")));
	header_.generator_version = gen::GENERATOR_VERSION;
	header_.hash_version = lb::core::HASH_VERSION;
	header_.template_version = set_->set_version();
	header_.data_version = to_std(String(params.get("data_version", "")));
	header_.homes.clear();
	const gen::PlanParams p = plan_params(params.get("tuning", Dictionary()), ring_bounds_);
	gen::PlanWorld world;
	if (roads_) {
		const gen::MainRoads *roads = roads_.get();
		world.is_main_road_cell = [roads](lb::core::world::Coord c) { return roads->is_main_road_cell(c); };
	}
	for (int e = 0; e < 4; e++) {
		const std::optional<gen::Socket> s = header_.forced.query(gen::edge_of({0, 0}, static_cast<gen::Edge>(e)));
		if (!s || s->open) {
			world.gates.push_back(static_cast<gen::Edge>(e));
		}
	}
	header_.plan = gen::make_plan(header_, p, world);
	if (!header_.plan.error.empty()) {
		UtilityFunctions::push_error("LbLayouts.plan: ", String::utf8(header_.plan.error.c_str()));
	}
	rebuild();
	return plan_dict();
}

bool LbLayouts::load_plan(const PackedByteArray &bytes) {
	const std::optional<gen::RunHeader> h = gen::parse_header(unpacked(bytes));
	ERR_FAIL_COND_V_MSG(!h, false, "LbLayouts.load_plan: not a run header");
	ERR_FAIL_COND_V_MSG(h->seed != header_.seed, false, "LbLayouts.load_plan: the header is another seed's");
	header_.list_kind = h->list_kind;
	header_.jobs = h->jobs;
	header_.cans = h->cans;
	header_.solo = h->solo;
	header_.draw = h->draw;
	header_.staging = h->staging;
	header_.hard_variant = h->hard_variant;
	header_.generator_version = h->generator_version;
	header_.hash_version = h->hash_version;
	header_.template_version = h->template_version;
	header_.data_version = h->data_version;
	header_.plan = h->plan;
	header_.homes = h->homes;
	rebuild();
	return true;
}

PackedByteArray LbLayouts::plan_bytes() const {
	return packed(gen::serialise_header(header_));
}

Dictionary LbLayouts::plan_dict() const {
	const gen::RunPlan &plan = header_.plan;
	Dictionary d;
	d["ok"] = plan.error.empty();
	d["error"] = String::utf8(plan.error.c_str());
	d["list_kind"] = header_.list_kind;
	PackedStringArray jobs;
	for (const std::string &j : header_.jobs) {
		jobs.append(String::utf8(j.c_str()));
	}
	d["jobs"] = jobs;
	d["cans"] = header_.cans;
	d["solo"] = header_.solo;
	PackedStringArray draw;
	for (const std::string &x : header_.draw) {
		draw.append(String::utf8(x.c_str()));
	}
	d["draw"] = draw;
	d["staging"] = String::utf8(header_.staging.c_str());
	d["hard_variant"] = String::utf8(header_.hard_variant.c_str());
	d["generator_version"] = static_cast<int64_t>(header_.generator_version);
	d["hash_version"] = static_cast<int64_t>(header_.hash_version);
	d["template_version"] = String::utf8(header_.template_version.c_str());
	d["data_version"] = String::utf8(header_.data_version.c_str());
	Array sites;
	for (const gen::PlannedSite &site : plan.sites) {
		Dictionary s;
		s["kind"] = String::utf8(gen::poi_kind_name(site.kind));
		s["need"] = String::utf8(site.need.c_str());
		s["door"] = v2(site.door);
		s["door_side"] = String(SIDES[static_cast<size_t>(site.door_side)]);
		s["cells"] = cells_array(site.cells);
		Dictionary holds;
		for (const gen::Holding &h : site.holds) {
			holds[String::utf8(h.item.c_str())] = h.count;
		}
		s["holds"] = holds;
		s["spine"] = site.spine;
		s["attempt"] = site.attempt;
		sites.append(s);
	}
	d["sites"] = sites;
	Array spines;
	for (const gen::Spine &sp : plan.spines) {
		Dictionary s;
		s["site"] = sp.site;
		s["gate"] = String(SIDES[static_cast<size_t>(sp.gate)]);
		s["cells"] = cells_array(sp.cells);
		s["replan"] = sp.replan;
		spines.append(s);
	}
	d["spines"] = spines;
	d["revolver"] = plan.revolver;
	d["revolver_cell"] = v2(plan.revolver_cell);
	d["boxes"] = cells_array(plan.box_cells);
	PackedStringArray homes;
	for (const auto &[name, value] : header_.homes) {
		homes.append(String::utf8(name.c_str()));
	}
	d["homes"] = homes;
	d["bytes"] = plan_bytes();
	return d;
}

bool LbLayouts::is_spine_cell(Vector2i cell) const {
	return spine_sockets_ && spine_sockets_->is_spine_cell({cell.x, cell.y});
}

void LbLayouts::set_home(const String &name, const PackedByteArray &bytes) {
	header_.homes[to_std(name)] = unpacked(bytes);
}

PackedByteArray LbLayouts::home(const String &name) const {
	const auto it = header_.homes.find(to_std(name));
	return it != header_.homes.end() ? packed(it->second) : PackedByteArray();
}

bool LbLayouts::force_socket(Vector2i cell, const String &side, const Dictionary &socket) {
	const std::optional<gen::Edge> e = side_from(side);
	ERR_FAIL_COND_V_MSG(!e, false, "LbLayouts.force_socket: unknown side");
	gen::Socket s;
	s.open = static_cast<bool>(socket.get("open", false));
	s.offset = s.open ? static_cast<int32_t>(static_cast<int64_t>(socket.get("offset", 0))) : 0;
	s.width = s.open ? static_cast<int32_t>(static_cast<int64_t>(socket.get("width", 0))) : 0;
	header_.forced.set(gen::edge_of({cell.x, cell.y}, *e), s);
	rebuild();
	return true;
}

Dictionary LbLayouts::socket(Vector2i cell, const String &side) const {
	const std::optional<gen::Edge> e = side_from(side);
	ERR_FAIL_COND_V_MSG(!e, Dictionary(), "LbLayouts.socket: unknown side");
	return socket_dict(deriver_->socket(gen::edge_of({cell.x, cell.y}, *e)));
}

String LbLayouts::biome_of(Vector2i cell) const {
	// GEN-06's biome, or a templated point of interest's (GEN-09).
	if (pois_) {
		const gen::PoiRef ref = pois_->at({cell.x, cell.y});
		if (ref && ref->shape != nullptr && !ref->biome.empty()) {
			return String::utf8(ref->biome.c_str());
		}
	}
	return String::utf8(cells_->classify({cell.x, cell.y}).biome.c_str());
}

Dictionary LbLayouts::poi_at(Vector2i cell) const {
	if (!pois_) {
		return Dictionary();
	}
	const gen::PoiRef ref = pois_->at({cell.x, cell.y});
	return ref ? poi_dict(*ref) : Dictionary();
}

Dictionary LbLayouts::poi_region(Vector2i region) const {
	Dictionary d;
	d["region"] = region;
	Array pois;
	if (pois_) {
		const std::shared_ptr<const gen::RegionLayout> layout = pois_->region({region.x, region.y});
		d["wanted"] = layout->wanted;
		for (const gen::Poi &p : layout->pois) {
			pois.append(poi_dict(p));
		}
	} else {
		d["wanted"] = 0;
	}
	d["pois"] = pois;
	return d;
}

Array LbLayouts::poi_contents(Vector2i region, int64_t index) const {
	Array out;
	if (!pois_) {
		return out;
	}
	const gen::PoiId id{{region.x, region.y}, static_cast<int32_t>(index)};
	const gen::PoiRef ref = pois_->find(id);
	if (!ref) {
		return out;
	}
	for (const gen::Content &c : gen::poi_contents(header_, contents_params_, *ref, pois_->is_canary(id))) {
		Dictionary d;
		d["line"] = c.line;
		d["thing"] = String::utf8(c.thing.c_str());
		d["oil_milli"] = c.oil_milli;
		d["notches"] = c.notches;
		d["with"] = c.with;
		out.append(d);
	}
	return out;
}

PackedByteArray LbLayouts::canary_home(Vector2i region) {
	return packed(gen::canary_home({region.x, region.y}));
}

Dictionary LbLayouts::make_homes() {
	gen::write_homes(gen::make_homes(*place_world_, place_params_), header_);
	return homes_dict();
}

Dictionary LbLayouts::homes_dict() const {
	const gen::Homes h = gen::read_homes(header_);
	Dictionary d;
	Array roosts;
	for (const gen::TileBox &b : h.roosts) {
		roosts.append(box_rect(b));
	}
	d["roosts"] = roosts;
	d["start_roost"] = h.start_roost;
	d["hoard"] = h.hoard ? Variant(Vector2i(static_cast<int32_t>(h.hoard->x), static_cast<int32_t>(h.hoard->y))) : Variant();
	Array phones;
	for (const lb::core::world::Coord &t : h.gate_phones) {
		phones.append(Vector2i(static_cast<int32_t>(t.x), static_cast<int32_t>(t.y)));
	}
	d["gate_phones"] = phones;
	d["electric_lamp"] = h.electric_lamp ? Variant(Vector2i(static_cast<int32_t>(h.electric_lamp->x), static_cast<int32_t>(h.electric_lamp->y))) : Variant();
	d["canary"] = h.canary ? Variant(Vector2i(static_cast<int32_t>(h.canary->x), static_cast<int32_t>(h.canary->y))) : Variant();
	return d;
}

std::vector<gen::Placement> LbLayouts::placed(lb::core::world::Coord cell) const {
	if (!has_validator_) {
		return gen::place_cell(*place_world_, place_params_, cell);
	}
	gen::PlacedCell p = gen::place_validated(*place_world_, place_params_, validator_params_, cell);
	counters_->count_placement(cell, p);
	return std::move(p.list);
}

Array LbLayouts::place(Vector2i cell) const {
	Array out;
	for (const gen::Placement &x : placed({cell.x, cell.y})) {
		out.append(placement_dict(x));
	}
	return out;
}

int64_t LbLayouts::dress(Vector2i cell, const Ref<LbCellData> &data) const {
	ERR_FAIL_COND_V(data.is_null(), 0);
	lb::core::world::Cell *c = data->edit();
	ERR_FAIL_NULL_V(c, 0);
	int64_t changed = 0;
	bool doors = false;
	const lb::core::world::Coord at{cell.x, cell.y};
	for (const gen::Placement &x : placed(at)) {
		if (x.kind != gen::PlacedKind::AIR_DOOR && x.kind != gen::PlacedKind::SUMP_MUD) {
			continue;
		}
		for (int32_t j = 0; j < x.h; j++) {
			for (int32_t i = 0; i < x.w; i++) {
				const lb::core::world::Coord t{x.tile.x + i, x.tile.y + j};
				if (lb::core::world::cell_of(t) != at) {
					continue;
				}
				const lb::core::world::Coord local = lb::core::world::local_of(t);
				lb::core::world::Tile &tile = c->tiles[static_cast<size_t>(lb::core::world::Cell::index_of(local.x, local.y))];
				if (tile.material != static_cast<uint8_t>(lb::core::world::TileMaterial::FLOOR)) {
					continue;
				}
				if (x.kind == gen::PlacedKind::AIR_DOOR) {
					tile.material = static_cast<uint8_t>(lb::core::world::TileMaterial::WOODEN_DOOR);
					doors = true;
					changed++;
				} else if ((tile.state & lb::core::world::STATE_MUD) == 0) {
					tile.state = static_cast<uint8_t>(tile.state | lb::core::world::STATE_MUD);
					changed++;
				}
			}
		}
	}
	if (doors) {
		const bool poi = pois_ && pois_->at(at);
		data->cut_zones(poi ? "poi" : "chamber");
	}
	return changed;
}

Dictionary LbLayouts::find_counts(const TypedArray<Vector2i> &cells) const {
	std::vector<std::vector<gen::Placement>> lists;
	for (int64_t i = 0; i < cells.size(); i++) {
		const Vector2i c = cells[i];
		lists.push_back(placed({c.x, c.y}));
	}
	Dictionary d;
	for (const auto &[key, n] : gen::find_counts(lists)) {
		d[String::utf8(key.c_str())] = n;
	}
	return d;
}

Array LbLayouts::rich_rock_masses(Vector2i region) const {
	Array out;
	for (const gen::TileBox &b : gen::rich_rock_masses(*place_world_, place_params_, {region.x, region.y})) {
		out.append(box_rect(b));
	}
	return out;
}

Dictionary LbLayouts::road_of(Vector2i cell) const {
	Dictionary out;
	const bool main = roads_ && roads_->is_main_road_cell({cell.x, cell.y});
	out["main_road"] = main;
	out["crossing"] = main && roads_->is_crossing({cell.x, cell.y});
	if (main) {
		const gen::CellClass c = road_cells_->classify({cell.x, cell.y});
		out["shape"] = String::utf8(c.shape.c_str());
		out["old_fall"] = c.old_fall;
		out["transpose"] = c.transpose;
		out["dress"] = String::utf8(c.dress.c_str());
	}
	return out;
}

namespace {

Dictionary layout_dict(const std::optional<gen::Layout> &layout) {
	Dictionary out;
	out["ok"] = layout.has_value();
	if (!layout) {
		return out;
	}
	out["base_camp"] = layout->base_camp;
	out["fallback"] = layout->fallback;
	out["template"] = String::utf8(layout->template_id.c_str());
	Dictionary sockets;
	for (int e = 0; e < 4; e++) {
		sockets[SIDES[e]] = socket_dict(layout->sockets[static_cast<size_t>(e)]);
	}
	out["sockets"] = sockets;
	out["cell"] = layout->base_camp ? Variant() : Variant(LbCellData::wrap(layout->cell));
	out["digest"] = static_cast<int64_t>(layout->digest);
	out["reroll"] = layout->reroll;
	return out;
}

Dictionary verdict_dict(const gen::Verdict &v) {
	Dictionary d;
	d["ok"] = v.ok();
	d["rule"] = v.number();
	d["check"] = String(gen::check_name(v.check));
	d["tile"] = Vector2i(static_cast<int32_t>(v.tile.x), static_cast<int32_t>(v.tile.y));
	d["detail"] = String::utf8(v.detail.c_str());
	return d;
}

std::vector<lb::core::world::Coord> coords(const Array &a) {
	std::vector<lb::core::world::Coord> out;
	for (int64_t i = 0; i < a.size(); i++) {
		const Vector2i v = a[i];
		out.push_back({v.x, v.y});
	}
	return out;
}

Array vectors(const std::vector<lb::core::world::Coord> &cs) {
	Array out;
	for (const auto &c : cs) {
		out.push_back(Vector2i(static_cast<int32_t>(c.x), static_cast<int32_t>(c.y)));
	}
	return out;
}

} // namespace

Dictionary LbLayouts::derive(Vector2i cell, int64_t reroll) const {
	const uint64_t failures = deriver_->verify_failures();
	const std::optional<gen::Layout> layout = deriver_->derive({cell.x, cell.y}, static_cast<int32_t>(reroll));
	if (deriver_->verify_failures() != failures) {
		UtilityFunctions::push_error("LbLayouts: cell ", cell, " derived differently with its caches bypassed: an impure input");
	}
	return layout_dict(layout);
}

Dictionary LbLayouts::derive_final(Vector2i cell) const {
	const lb::core::world::Coord at{cell.x, cell.y};
	const uint64_t failures = deriver_->verify_failures();
	std::vector<gen::LayoutTry> tried;
	const std::optional<gen::Layout> layout =
			gen::derive_final(deriver_->inputs(), at, &tried, [&](int32_t reroll) { return deriver_->derive(at, reroll); });
	if (deriver_->verify_failures() != failures) {
		UtilityFunctions::push_error("LbLayouts: cell ", cell, " derived differently with its caches bypassed: an impure input");
	}
	if (has_validator_) {
		counters_->count_layout(at, cells_->classify(at).biome, layout, tried);
	}
	Dictionary out = layout_dict(layout);
	Array tries;
	for (const gen::LayoutTry &t : tried) {
		Dictionary d = verdict_dict(t.verdict);
		d["reroll"] = t.reroll;
		d["template"] = String::utf8(t.template_id.c_str());
		tries.push_back(d);
	}
	out["tries"] = tries;
	return out;
}

Dictionary LbLayouts::placement_report(Vector2i cell) const {
	Dictionary out;
	const gen::PlacedCell p = has_validator_ ? gen::place_validated(*place_world_, place_params_, validator_params_, {cell.x, cell.y}) : gen::PlacedCell{};
	out["retry"] = p.retry;
	out["strict"] = p.strict;
	out["dropped"] = p.dropped;
	Array failures;
	for (const gen::Verdict &v : p.failures) {
		failures.push_back(verdict_dict(v));
	}
	out["failures"] = failures;
	return out;
}

Dictionary LbLayouts::validate_run_start() {
	const size_t n = header_.plan.spines.size();
	gen::SpineCheck check;
	check.verdicts.assign(n, gen::Verdict{});
	check.replans.assign(n, 0);
	if (has_validator_) {
		std::vector<gen::Edge> gates;
		for (int e = 0; e < 4; e++) {
			const std::optional<gen::Socket> s = header_.forced.query(gen::edge_of({0, 0}, static_cast<gen::Edge>(e)));
			if (!s || s->open) {
				gates.push_back(static_cast<gen::Edge>(e));
			}
		}
		check = gen::validate_spines(
				header_.plan, header_.seed, gates, ring_bounds_, validator_params_.max_replans,
				[this](size_t i) { return gen::walk_spine(*place_world_, place_params_, validator_params_, header_.plan, i); },
				[this]() { rebuild(); });
	}
	const std::vector<gen::Spine> &spines = header_.plan.spines;
	const std::vector<gen::Verdict> &verdicts = check.verdicts;
	const std::vector<int32_t> &replans = check.replans;
	const int64_t total = check.total;
	Dictionary out;
	bool ok = true;
	Array list;
	for (size_t i = 0; i < n; i++) {
		if (has_validator_) {
			counters_->count_spine(replans[i], verdicts[i]);
		}
		Dictionary d = verdict_dict(verdicts[i]);
		d["site"] = spines[i].site;
		d["reached"] = verdicts[i].ok();
		d["replans"] = replans[i];
		list.push_back(d);
		ok = ok && verdicts[i].ok();
	}
	const gen::Verdict gates = has_validator_ ? gen::check_gates(*place_world_) : gen::Verdict{};
	if (has_validator_) {
		counters_->count_gates(gates);
		// GEN-09: a planned site no template fits stays plain cells, its contents with no slot to lie in
		// (GEN-16's templates close the gap).
		for (size_t i = 0; i < header_.plan.sites.size(); i++) {
			const gen::PlannedSite &site = header_.plan.sites[i];
			const gen::PoiRef ref = pois_ ? pois_->at(site.door) : gen::PoiRef{};
			if (pois_ && (!ref || ref->shape == nullptr)) {
				counters_->count("sites_untemplated", "planned site " + std::to_string(i) + " (" + gen::poi_kind_name(site.kind) + ", " + site.need +
								") has no template");
			}
		}
	}
	out["ok"] = ok && gates.ok();
	out["replans"] = total;
	out["spines"] = list;
	out["gates"] = verdict_dict(gates);
	return out;
}

Dictionary LbLayouts::validator_stats() const {
	Dictionary totals;
	for (const auto &[key, count] : counters_->totals()) {
		totals[String::utf8(key.c_str())] = count;
	}
	Array notes;
	for (const std::string &note : counters_->notes()) {
		notes.push_back(String::utf8(note.c_str()));
	}
	Dictionary out;
	out["totals"] = totals;
	out["notes"] = notes;
	return out;
}

Dictionary LbLayouts::fallback_coverage(const String &biome, const PackedInt32Array &widths) const {
	std::vector<int32_t> w;
	for (int64_t i = 0; i < widths.size(); i++) {
		w.push_back(widths[i]);
	}
	size_t checked = 0;
	const std::vector<gen::CoverageFailure> failures = gen::fallback_coverage(*set_, to_std(biome), w, header_.sockets, validator_params_, &checked);
	Array list;
	for (const gen::CoverageFailure &f : failures) {
		Dictionary d = verdict_dict(f.verdict);
		Dictionary sockets;
		for (int e = 0; e < 4; e++) {
			sockets[SIDES[e]] = socket_dict(f.sockets[static_cast<size_t>(e)]);
		}
		d["sockets"] = sockets;
		list.push_back(d);
	}
	Dictionary out;
	out["checked"] = static_cast<int64_t>(checked);
	out["failures"] = list;
	return out;
}

void LbLayouts::start_pool(int64_t threads, bool background) {
	pool_threads_ = std::max<int64_t>(0, threads);
	pool_background_ = background;
	pool_.reset();
	pool_ = std::make_unique<gen::GenPool>(*deriver_, static_cast<int32_t>(pool_threads_), pool_background_);
	reset_window();
}

void LbLayouts::stop_pool() {
	pool_.reset();
	pool_threads_ = -1;
	reset_window();
}

void LbLayouts::set_window(int64_t radius, int64_t prefetch_radius) {
	window_radius_ = static_cast<int32_t>(std::max<int64_t>(0, radius));
	window_prefetch_ = static_cast<int32_t>(std::max<int64_t>(window_radius_, prefetch_radius));
	if (pool_) {
		for (const lb::core::world::Coord &c : asked_) {
			pool_->unwant(c);
		}
	}
	reset_window();
}

Dictionary LbLayouts::update_window(const TypedArray<Vector2i> &holders, const Ref<LbMine> &mine) {
	Dictionary out;
	out["moved"] = false;
	ERR_FAIL_NULL_V_MSG(pool_, out, "LbLayouts.update_window: start_pool first");
	ERR_FAIL_COND_V_MSG(mine.is_null(), out, "LbLayouts.update_window: no mine");
	std::vector<lb::core::world::Coord> cells;
	cells.reserve(static_cast<size_t>(holders.size()));
	for (int64_t i = 0; i < holders.size(); i++) {
		const Vector2i h = holders[i];
		cells.push_back({h.x, h.y});
	}
	gen::Window::Change change = window_->update(std::move(cells));
	if (!change.moved) {
		return out;
	}
	const lb::core::world::MineMap &map = mine->map();
	const std::vector<lb::core::world::Coord> &at = window_->holders();
	for (const lb::core::world::Coord &c : change.departed) {
		pool_->unwant(c);
		asked_.erase(c);
	}
	// The nearest first: what is still asked for moves up or down with the holders.
	for (const lb::core::world::Coord &c : asked_) {
		pool_->want(c, gen::nearest_holder(c, at));
	}
	for (const lb::core::world::Coord &c : change.arrived) {
		if (!map.is_loaded(c)) {
			pool_->want(c, gen::nearest_holder(c, at));
			asked_.insert(c);
		}
	}
	TypedArray<Vector2i> entered;
	int64_t entered_loaded = 0;
	for (const lb::core::world::Coord &c : change.entered) {
		if (map.is_loaded(c)) {
			entered_loaded++;
		} else {
			entered.push_back(Vector2i(static_cast<int32_t>(c.x), static_cast<int32_t>(c.y)));
		}
	}
	TypedArray<Vector2i> left;
	for (const lb::core::world::Coord &c : change.left) {
		left.push_back(Vector2i(static_cast<int32_t>(c.x), static_cast<int32_t>(c.y)));
	}
	out["moved"] = true;
	out["entered"] = entered;
	out["entered_loaded"] = entered_loaded;
	out["left"] = left;
	return out;
}

TypedArray<Vector2i> LbLayouts::evictions_now(const Ref<LbMine> &mine, const TypedArray<Vector2i> &pinned, int64_t evict,
		int64_t max_live) const {
	TypedArray<Vector2i> out;
	ERR_FAIL_COND_V_MSG(mine.is_null(), out, "LbLayouts.evictions_now: no mine");
	gen::WindowParams p;
	// Over the cap, only cells beyond the prefetch ring go: one inside it would only be asked for again.
	p.generate = window_->prefetch_radius();
	p.evict = static_cast<int32_t>(evict);
	p.max_live = static_cast<size_t>(std::max<int64_t>(0, max_live));
	std::set<lb::core::world::Coord> pins;
	for (int64_t i = 0; i < pinned.size(); i++) {
		const Vector2i p_cell = pinned[i];
		pins.insert({p_cell.x, p_cell.y});
	}
	for (const lb::core::world::Coord &c : gen::evictions(mine->map().loaded_cells(), window_->holders(), pins, p)) {
		out.push_back(Vector2i(static_cast<int32_t>(c.x), static_cast<int32_t>(c.y)));
	}
	return out;
}

void LbLayouts::want(Vector2i cell, int64_t priority) {
	ERR_FAIL_NULL_MSG(pool_, "LbLayouts.want: start_pool first");
	pool_->want({cell.x, cell.y}, priority);
}

void LbLayouts::unwant(Vector2i cell) {
	if (pool_) {
		pool_->unwant({cell.x, cell.y});
	}
}

Array LbLayouts::take(int64_t max) {
	Array out;
	ERR_FAIL_NULL_V_MSG(pool_, out, "LbLayouts.take: start_pool first");
	const uint64_t failures = deriver_->verify_failures();
	for (gen::GenPool::Result &r : pool_->take(static_cast<size_t>(std::max<int64_t>(0, max)))) {
		asked_.erase(r.cell);
		Dictionary d = layout_dict(r.layout);
		d["at"] = Vector2i(static_cast<int32_t>(r.cell.x), static_cast<int32_t>(r.cell.y));
		d["ms"] = r.ms;
		out.push_back(d);
	}
	if (deriver_->verify_failures() != failures) {
		UtilityFunctions::push_error("LbLayouts: a cell derived differently with its caches bypassed: an impure input");
	}
	return out;
}

Dictionary LbLayouts::pool_stats() const {
	Dictionary d;
	d["threads"] = pool_ ? pool_->threads() : -1;
	d["queued"] = pool_ ? static_cast<int64_t>(pool_->queued()) : 0;
	d["running"] = pool_ ? static_cast<int64_t>(pool_->running()) : 0;
	d["finished"] = pool_ ? static_cast<int64_t>(pool_->finished()) : 0;
	d["derived"] = pool_ ? static_cast<int64_t>(pool_->derived()) : 0;
	d["p50_ms"] = pool_ ? pool_->percentile_ms(0.5) : 0.0;
	d["p99_ms"] = pool_ ? pool_->percentile_ms(0.99) : 0.0;
	return d;
}

Array LbLayouts::required_cells(const Array &holders, int64_t radius) {
	const std::set<lb::core::world::Coord> cells = gen::required_cells(coords(holders), static_cast<int32_t>(radius));
	return vectors(std::vector<lb::core::world::Coord>(cells.begin(), cells.end()));
}

Array LbLayouts::evictions(const Array &loaded, const Array &holders, const Array &pinned, int64_t generate, int64_t evict,
		int64_t max_live) {
	gen::WindowParams p;
	p.generate = static_cast<int32_t>(generate);
	p.evict = static_cast<int32_t>(evict);
	p.max_live = static_cast<size_t>(std::max<int64_t>(0, max_live));
	const std::vector<lb::core::world::Coord> pins = coords(pinned);
	return vectors(gen::evictions(coords(loaded), coords(holders), std::set<lb::core::world::Coord>(pins.begin(), pins.end()), p));
}

void LbLayouts::set_caching(bool on) {
	caching_ = on;
	deriver_->set_caching(on);
	if (pois_) {
		pois_->set_caching(on);
	}
}

void LbLayouts::clear_caches() {
	deriver_->clear_caches();
}

void LbLayouts::set_verify(bool on) {
	verify_ = on;
	deriver_->set_verify(on);
}

int64_t LbLayouts::verify_failures() const {
	return static_cast<int64_t>(deriver_->verify_failures());
}

} // namespace lb::godot

#pragma once
// GDScript face of core/gen/template.h (GEN-04): the template validator and the packed binary,
// for the editor plugin, the headless exporter and tests. Server and tools only.
//
// A template is a Dictionary in the export's shape: id, kind ("biome_cell", "main_road", "poi",
// "fallback" or "base_camp"), biome, footprint [w, h], poi_kind, weight, author_version,
// stubs [{cell: [x, y], edge: "north"|"east"|"south"|"west", offset, max_width, depth, door}],
// rib [{cell: [x, y], index, milli}] and cells (an Array of LbCellData, footprint-local coords).

#include "core/gen/template.h"

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/string.hpp>

namespace lb::godot {

// GEN-04's validator numbers from a rules dictionary (TemplateBuild.rules' shape: ValidateParams'
// fields by name, missing ones at their defaults), for LbTemplates.validate and GEN-12's cell checks.
lb::core::gen::ValidateParams template_rules(const ::godot::Dictionary &params);

class LbTemplates : public ::godot::RefCounted {
	GDCLASS(LbTemplates, ::godot::RefCounted)

protected:
	static void _bind_methods();

public:
	// Every rule's problems in rule order: [{rule, cell: Vector2i, x, y, message, text}] (text names
	// the template, the rule and the tile). `params` holds ValidateParams' fields by name; missing
	// fields keep their defaults. A malformed template is one "format" problem.
	static ::godot::Array validate(const ::godot::Dictionary &template_dict, const ::godot::Dictionary &params);
	// The packed binary of `templates` (empty, with an error, if one is malformed).
	static ::godot::PackedByteArray encode_pack(const ::godot::String &set_version, const ::godot::Array &templates);
	// {set_version, templates}, or {} for bytes that are not a whole pack of this format.
	static ::godot::Dictionary decode_pack(const ::godot::PackedByteArray &bytes);
};

} // namespace lb::godot

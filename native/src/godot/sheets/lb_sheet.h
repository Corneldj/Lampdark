#pragma once
// GDScript face of LFT-14's sheet geometry in C++: the map card's rasteriser (core/sheets/
// sheet_raster.h, client-side) and the rubber (core/sheets/sheet_rubber.h, the server's hot path).

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>

namespace lb::godot {

class LbSheet : public ::godot::RefCounted {
	GDCLASS(LbSheet, ::godot::RefCounted)

protected:
	static void _bind_methods();

public:
	// view: {origin (Vector2, sheet units), scale (px a unit), size (Vector2i)}; paper: RGBA as an
	// int (0xRRGGBBAA); layers: [{xy: PackedInt32Array, starts: PackedInt32Array, rgba: int,
	// width_px: float}]. RGBA8 bytes; empty when the view is.
	static ::godot::PackedByteArray render(const ::godot::Dictionary &view, int64_t paper, const ::godot::Array &layers);
	// The rubber's circles over a polyline: [touched, pieces (Array of PackedVector2Array)].
	static ::godot::Array rub(const ::godot::PackedVector2Array &points, const ::godot::PackedVector2Array &centres, double radius);
};

} // namespace lb::godot

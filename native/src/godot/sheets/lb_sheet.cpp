#include "godot/sheets/lb_sheet.h"

#include "core/sheets/sheet_raster.h"
#include "core/sheets/sheet_rubber.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector2i.hpp>

#include <cstring>

using namespace godot;
namespace sheets = lb::core::sheets;

namespace lb::godot {

void LbSheet::_bind_methods() {
	ClassDB::bind_static_method("LbSheet", D_METHOD("render", "view", "paper", "layers"), &LbSheet::render);
	ClassDB::bind_static_method("LbSheet", D_METHOD("rub", "points", "centres", "radius"), &LbSheet::rub);
}

PackedByteArray LbSheet::render(const Dictionary &view, int64_t paper, const Array &layers) {
	sheets::View v;
	const Vector2 origin = view.get("origin", Vector2());
	const Vector2i size = view.get("size", Vector2i());
	v.origin_x = origin.x;
	v.origin_y = origin.y;
	v.scale = static_cast<double>(view.get("scale", 1.0));
	v.width = size.x;
	v.height = size.y;
	std::vector<sheets::Layer> ls;
	for (int64_t i = 0; i < layers.size(); i++) {
		const Dictionary d = layers[i];
		sheets::Layer l;
		const PackedInt32Array xy = d.get("xy", PackedInt32Array());
		const PackedInt32Array starts = d.get("starts", PackedInt32Array());
		l.xy.assign(xy.ptr(), xy.ptr() + xy.size());
		l.starts.assign(starts.ptr(), starts.ptr() + starts.size());
		l.rgba = static_cast<uint32_t>(static_cast<int64_t>(d.get("rgba", 0xFF)));
		l.width_px = static_cast<double>(d.get("width_px", 3.0));
		ls.push_back(std::move(l));
	}
	const std::vector<uint8_t> bytes = sheets::render(v, static_cast<uint32_t>(paper), ls);
	PackedByteArray out;
	out.resize(static_cast<int64_t>(bytes.size()));
	if (!bytes.empty()) {
		std::memcpy(out.ptrw(), bytes.data(), bytes.size());
	}
	return out;
}

Array LbSheet::rub(const PackedVector2Array &points, const PackedVector2Array &centres, double radius) {
	std::vector<sheets::Pt> pts(static_cast<size_t>(points.size()));
	for (int64_t i = 0; i < points.size(); i++) {
		pts[i] = sheets::Pt{points[i].x, points[i].y};
	}
	std::vector<sheets::Pt> cs(static_cast<size_t>(centres.size()));
	for (int64_t i = 0; i < centres.size(); i++) {
		cs[i] = sheets::Pt{centres[i].x, centres[i].y};
	}
	const sheets::RubResult r = sheets::rub(pts, cs, radius);
	Array pieces;
	for (const std::vector<sheets::Pt> &piece : r.pieces) {
		PackedVector2Array out;
		out.resize(static_cast<int64_t>(piece.size()));
		for (size_t i = 0; i < piece.size(); i++) {
			out[static_cast<int64_t>(i)] = Vector2(static_cast<real_t>(piece[i].x), static_cast<real_t>(piece[i].y));
		}
		pieces.push_back(out);
	}
	Array result;
	result.push_back(r.touched);
	result.push_back(pieces);
	return result;
}

} // namespace lb::godot

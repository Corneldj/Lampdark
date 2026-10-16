#include "godot/gen/lb_layouts.h"

#include "godot/world/lb_mine.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
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

} // namespace

void LbLayouts::_bind_methods() {
	ClassDB::bind_method(D_METHOD("load_pack", "bytes"), &LbLayouts::load_pack);
	ClassDB::bind_method(D_METHOD("set_version"), &LbLayouts::set_version);
	ClassDB::bind_method(D_METHOD("configure", "seed", "params"), &LbLayouts::configure);
	ClassDB::bind_method(D_METHOD("force_socket", "cell", "side", "socket"), &LbLayouts::force_socket);
	ClassDB::bind_method(D_METHOD("socket", "cell", "side"), &LbLayouts::socket);
	ClassDB::bind_method(D_METHOD("derive", "cell", "reroll"), &LbLayouts::derive);
	ClassDB::bind_method(D_METHOD("set_caching", "on"), &LbLayouts::set_caching);
	ClassDB::bind_method(D_METHOD("clear_caches"), &LbLayouts::clear_caches);
	ClassDB::bind_method(D_METHOD("set_verify", "on"), &LbLayouts::set_verify);
	ClassDB::bind_method(D_METHOD("verify_failures"), &LbLayouts::verify_failures);
}

LbLayouts::LbLayouts() : set_(std::make_shared<gen::TemplateSet>()) {
#ifdef DEBUG_ENABLED
	verify_ = true; // debug builds derive every layout twice, caches bypassed, and compare (GEN-05)
#endif
	cells_ = std::make_unique<gen::UniformCells>("", header_.sockets.widths);
	rebuild();
}

void LbLayouts::rebuild() {
	gen::DeriveInputs in;
	in.header = &header_;
	in.templates = set_.get();
	in.cells = cells_.get();
	deriver_ = std::make_unique<gen::Deriver>(in);
	deriver_->set_caching(caching_);
	deriver_->set_verify(verify_);
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
	const CharString biome = String(params.get("biome", "")).utf8();
	cells_ = std::make_unique<gen::UniformCells>(std::string(biome.get_data(), static_cast<size_t>(biome.length())), header_.sockets.widths);
	rebuild();
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

Dictionary LbLayouts::derive(Vector2i cell, int64_t reroll) const {
	Dictionary out;
	const uint64_t failures = deriver_->verify_failures();
	const std::optional<gen::Layout> layout = deriver_->derive({cell.x, cell.y}, static_cast<int32_t>(reroll));
	if (deriver_->verify_failures() != failures) {
		UtilityFunctions::push_error("LbLayouts: cell ", cell, " derived differently with its caches bypassed: an impure input");
	}
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
	return out;
}

void LbLayouts::set_caching(bool on) {
	caching_ = on;
	deriver_->set_caching(on);
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

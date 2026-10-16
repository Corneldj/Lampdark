#pragma once
// GDScript face of GEN-05's layout stage (core/gen/derive.h): the run's template pack, its
// sockets and its derived cell layouts. Set it up first (load_pack, configure, force_socket);
// after that socket() and derive() are pure and thread-safe, for GEN-11's workers. Server-only:
// no socket, layout or seed reaches a client (NET-08).

#include "core/gen/derive.h"

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/vector2i.hpp>

#include <memory>

namespace lb::godot {

class LbLayouts : public ::godot::RefCounted {
	GDCLASS(LbLayouts, ::godot::RefCounted)

protected:
	static void _bind_methods();

public:
	LbLayouts();

	// GEN-04's pack. False for bytes that are not a whole pack.
	bool load_pack(const ::godot::PackedByteArray &bytes);
	::godot::String set_version() const;
	// params: open_probability, offsets, widths, reroll_limit, biome (every cell's until GEN-06).
	void configure(int64_t seed, const ::godot::Dictionary &params);
	// A socket forced up front (base camp's): socket {open, offset, width}. side: north, east, south, west.
	bool force_socket(::godot::Vector2i cell, const ::godot::String &side, const ::godot::Dictionary &socket);
	// {open, offset, width, forced}
	::godot::Dictionary socket(::godot::Vector2i cell, const ::godot::String &side) const;
	// {ok, base_camp, fallback, template, sockets: {side: {...}}, cell: LbCellData (none for base camp), digest}
	::godot::Dictionary derive(::godot::Vector2i cell, int64_t reroll) const;
	void set_caching(bool on);
	void clear_caches();
	void set_verify(bool on);
	int64_t verify_failures() const;

private:
	std::shared_ptr<lb::core::gen::TemplateSet> set_;
	lb::core::gen::RunHeader header_;
	std::unique_ptr<lb::core::gen::UniformCells> cells_;
	std::unique_ptr<lb::core::gen::Deriver> deriver_;
	bool caching_ = true;
	bool verify_ = false;
	void rebuild();
};

} // namespace lb::godot

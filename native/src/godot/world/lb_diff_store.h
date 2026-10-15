#pragma once
// GDScript face of core/world/diff_store (GEN-13): the diff log's compact store. DiffLog
// (server/world/diff_log.gd) is the gameplay-facing API over it. Server-only.

#include "core/world/diff_store.h"

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/vector2i.hpp>

namespace lb::godot {

class LbDiffStore : public ::godot::RefCounted {
	GDCLASS(LbDiffStore, ::godot::RefCounted)

protected:
	static void _bind_methods();

public:
	void put(::godot::Vector2i cell, int64_t kind, const ::godot::String &key, int64_t tick, const ::godot::PackedByteArray &payload);
	bool erase(::godot::Vector2i cell, int64_t kind, const ::godot::String &key);
	// {tick, payload}, or empty if there is no record.
	::godot::Dictionary get_record(::godot::Vector2i cell, int64_t kind, const ::godot::String &key) const;
	// The cell's records in canonical order: [{kind, key, tick, payload}].
	::godot::Array records(::godot::Vector2i cell) const;
	// The same with each payload decoded (bytes_to_var), and the cell's blood, if any, as one row of
	// kind `blood_kind`, key "blood", tick -1, payload {smears: [{tile, direction}]}, placed before
	// the first record of a higher kind: the replay order, ready to apply.
	::godot::Array decoded_records(::godot::Vector2i cell, int64_t blood_kind) const;
	::godot::Array cells() const;
	int64_t record_count() const;

	void mark_blood(::godot::Vector2i tile, int64_t direction);
	bool erase_blood(::godot::Vector2i tile);
	int64_t blood_at(::godot::Vector2i tile) const;
	// The cell's smeared tiles, row-major: [{tile, direction}].
	::godot::Array blood(::godot::Vector2i cell) const;
	int64_t blood_count() const;

	void section_put(const ::godot::String &section, const ::godot::String &key, const ::godot::PackedByteArray &payload);
	bool section_erase(const ::godot::String &section, const ::godot::String &key);
	bool section_has(const ::godot::String &section, const ::godot::String &key) const;
	::godot::PackedByteArray section_get(const ::godot::String &section, const ::godot::String &key) const;
	::godot::PackedStringArray section_keys(const ::godot::String &section) const;
	::godot::PackedStringArray sections() const;

	int64_t cells_bytes() const;
	int64_t section_bytes(const ::godot::String &section) const;
	::godot::PackedByteArray serialise() const;
	bool deserialise(const ::godot::PackedByteArray &bytes);
	// A payload's canonical bytes: var_to_bytes with every dictionary's keys in sorted order (by
	// their text), all the way down, so equal payloads encode alike on every platform.
	static ::godot::PackedByteArray encode(const ::godot::Variant &payload);
	// FNV-1a 64 of serialise(), as a signed 64-bit integer.
	int64_t digest() const;
	void clear();

private:
	lb::core::world::DiffStore store_;
};

} // namespace lb::godot

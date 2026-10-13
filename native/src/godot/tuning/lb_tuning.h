#pragma once
// GDScript face of the native tuning mirror (FND-05). Tuning calls set_values() after every
// load and swap; C++ systems read lb::core::TuningTable::current().

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/variant.hpp>

namespace lb::godot {

class LbTuning : public ::godot::RefCounted {
	GDCLASS(LbTuning, ::godot::RefCounted)

protected:
	static void _bind_methods();

public:
	// Replaces the current table with these key -> value pairs. Returns false (and keeps the
	// old table) if a value has a type the mirror cannot hold.
	static bool set_values(const ::godot::Dictionary &values);
	// The mirrored value converted back to a Variant, or null for an unknown key.
	static ::godot::Variant get_value(const ::godot::String &key);
	static int64_t count();
	static int64_t ppm(const ::godot::String &key);
};

} // namespace lb::godot

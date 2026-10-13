#pragma once
// GDScript face of core/rng/hash.h (FND-06). GDScript ints are signed 64-bit: a value of
// 2^63 or more shows as negative, but every bit pattern round-trips unchanged.

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <godot_cpp/variant/string.hpp>

namespace lb::godot {

class LbHash : public ::godot::RefCounted {
	GDCLASS(LbHash, ::godot::RefCounted)

protected:
	static void _bind_methods();

public:
	static int64_t mix64(int64_t value);
	static int64_t hash(int64_t seed, int64_t domain, const ::godot::PackedInt64Array &keys);
	static int64_t sub_seed(int64_t seed, int64_t domain, const ::godot::PackedInt64Array &keys, int64_t attempt);
	// 16 lower-case hex digits of the bit pattern, for dev and QA logs.
	static ::godot::String to_hex(int64_t value);
};

} // namespace lb::godot

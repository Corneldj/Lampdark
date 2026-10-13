#include "godot/rng/lb_hash.h"

#include "core/rng/hash.h"

#include <godot_cpp/core/class_db.hpp>

#include <cstdio>

using namespace godot;

namespace lb::godot {

void LbHash::_bind_methods() {
	ClassDB::bind_static_method("LbHash", D_METHOD("mix64", "value"), &LbHash::mix64);
	ClassDB::bind_static_method("LbHash", D_METHOD("hash", "seed", "domain", "keys"), &LbHash::hash);
	ClassDB::bind_static_method("LbHash", D_METHOD("sub_seed", "seed", "domain", "keys", "attempt"), &LbHash::sub_seed);
	ClassDB::bind_static_method("LbHash", D_METHOD("to_hex", "value"), &LbHash::to_hex);
	ClassDB::bind_integer_constant("LbHash", "", "VERSION", static_cast<int64_t>(lb::core::HASH_VERSION));
}

int64_t LbHash::mix64(int64_t value) {
	return static_cast<int64_t>(lb::core::mix64(static_cast<uint64_t>(value)));
}

int64_t LbHash::hash(int64_t seed, int64_t domain, const PackedInt64Array &keys) {
	return static_cast<int64_t>(lb::core::hash_u64(static_cast<uint64_t>(seed), static_cast<uint64_t>(domain),
			keys.ptr(), static_cast<size_t>(keys.size())));
}

int64_t LbHash::sub_seed(int64_t seed, int64_t domain, const PackedInt64Array &keys, int64_t attempt) {
	return static_cast<int64_t>(lb::core::sub_seed(static_cast<uint64_t>(seed), static_cast<uint64_t>(domain),
			keys.ptr(), static_cast<size_t>(keys.size()), attempt));
}

String LbHash::to_hex(int64_t value) {
	char text[17];
	std::snprintf(text, sizeof(text), "%016llx", static_cast<unsigned long long>(static_cast<uint64_t>(value)));
	return String(text);
}

} // namespace lb::godot

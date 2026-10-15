#pragma once
// NET-09's seal (GDD §15.10): save sections are sealed for server processes, so a save on a
// player's disk can be neither read nor altered unnoticed. Obfuscated, not secret: the keys live
// in this library, masked. Encrypt-then-MAC with the engine's own primitives (AES-256-CBC, a
// random IV, PKCS#7 padding; HMAC-SHA256 over IV and ciphertext). A sealed blob is
// [16-byte IV][ciphertext][32-byte MAC]. Clients store blobs and never open them.

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>

namespace lb::godot {

class LbSeal : public ::godot::RefCounted {
	GDCLASS(LbSeal, ::godot::RefCounted)

protected:
	static void _bind_methods();

public:
	static ::godot::PackedByteArray seal(const ::godot::PackedByteArray &plain);
	// The plain bytes, or empty when the blob is malformed or its MAC does not match (tampered).
	static ::godot::PackedByteArray open(const ::godot::PackedByteArray &sealed);
	// Whether `sealed` opens (without returning the bytes).
	static bool verify(const ::godot::PackedByteArray &sealed);
};

} // namespace lb::godot

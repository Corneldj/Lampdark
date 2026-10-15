#include "godot/net/lb_seal.h"

#include <godot_cpp/classes/aes_context.hpp>
#include <godot_cpp/classes/crypto.hpp>
#include <godot_cpp/classes/hashing_context.hpp>
#include <godot_cpp/classes/hmac_context.hpp>
#include <godot_cpp/core/class_db.hpp>

#include <array>
#include <cstdint>

using namespace godot;

namespace lb::godot {

namespace {

constexpr int64_t IV_BYTES = 16;
constexpr int64_t MAC_BYTES = 32;

// The keys, masked: key = MASKED xor MASK (the first 32 bytes encrypt, the next 32 authenticate).
constexpr std::array<uint8_t, 64> MASKED = {0xa8, 0x39, 0xef, 0xb5, 0xaf, 0xc2, 0x1a, 0xca, 0x00, 0x61, 0x7c, 0x15, 0x24, 0x67, 0xca, 0xf3, 0xb8, 0x9d, 0x96, 0x90, 0x7f, 0xd0, 0x9f, 0x94, 0x71, 0x9f, 0xa0, 0x9d, 0x6c, 0x3f, 0xb2, 0xaa, 0x9b, 0x7a, 0x47, 0xeb, 0xe7, 0x57, 0x52, 0x20, 0x7d, 0x3b, 0xa7, 0x79, 0x43, 0x5d, 0xcf, 0xdf, 0x2f, 0x8d, 0x56, 0x05, 0x6b, 0x6f, 0x16, 0x43, 0x5d, 0xf5, 0xf4, 0x17, 0xd2, 0xb5, 0x87, 0x1e};
constexpr std::array<uint8_t, 64> MASK = {0xdd, 0x07, 0x96, 0x38, 0xc4, 0x11, 0x66, 0x5b, 0x61, 0x68, 0x0d, 0x4d, 0xa2, 0xbc, 0x03, 0x7a, 0x58, 0x0e, 0x27, 0x66, 0xb8, 0x6d, 0x2b, 0xc5, 0xfe, 0x93, 0xfd, 0x1c, 0x83, 0x07, 0x2d, 0xed, 0x0e, 0x09, 0xc1, 0x9a, 0x08, 0x76, 0xfb, 0x6c, 0x29, 0xa7, 0xa0, 0x24, 0x26, 0x83, 0x51, 0x33, 0xe9, 0x02, 0x94, 0xaf, 0x0c, 0x77, 0x9c, 0x26, 0xb9, 0x56, 0xad, 0xad, 0xd2, 0xca, 0xc8, 0x4f};

PackedByteArray key_part(int64_t from) {
	PackedByteArray k;
	k.resize(32);
	for (int64_t i = 0; i < 32; i++) {
		k[i] = static_cast<uint8_t>(MASKED[static_cast<size_t>(from + i)] ^ MASK[static_cast<size_t>(from + i)]);
	}
	return k;
}

PackedByteArray mac_of(const PackedByteArray &iv_and_cipher) {
	Ref<HMACContext> h;
	h.instantiate();
	h->start(HashingContext::HASH_SHA256, key_part(32));
	h->update(iv_and_cipher);
	return h->finish();
}

} // namespace

void LbSeal::_bind_methods() {
	ClassDB::bind_static_method("LbSeal", D_METHOD("seal", "plain"), &LbSeal::seal);
	ClassDB::bind_static_method("LbSeal", D_METHOD("open", "sealed"), &LbSeal::open);
	ClassDB::bind_static_method("LbSeal", D_METHOD("verify", "sealed"), &LbSeal::verify);
}

PackedByteArray LbSeal::seal(const PackedByteArray &plain) {
	Ref<Crypto> crypto;
	crypto.instantiate();
	const PackedByteArray iv = crypto->generate_random_bytes(IV_BYTES);
	// PKCS#7 padding to the block size.
	PackedByteArray padded = plain;
	const int64_t pad = 16 - (plain.size() % 16);
	for (int64_t i = 0; i < pad; i++) {
		padded.push_back(static_cast<uint8_t>(pad));
	}
	Ref<AESContext> aes;
	aes.instantiate();
	aes->start(AESContext::MODE_CBC_ENCRYPT, key_part(0), iv);
	const PackedByteArray cipher = aes->update(padded);
	aes->finish();
	PackedByteArray out = iv;
	out.append_array(cipher);
	out.append_array(mac_of(out));
	return out;
}

bool LbSeal::verify(const PackedByteArray &sealed) {
	if (sealed.size() < IV_BYTES + 16 + MAC_BYTES || (sealed.size() - IV_BYTES - MAC_BYTES) % 16 != 0) {
		return false;
	}
	const PackedByteArray body = sealed.slice(0, sealed.size() - MAC_BYTES);
	const PackedByteArray want = mac_of(body);
	uint8_t diff = 0;
	for (int64_t i = 0; i < MAC_BYTES; i++) {
		diff = static_cast<uint8_t>(diff | (want[i] ^ sealed[sealed.size() - MAC_BYTES + i]));
	}
	return diff == 0;
}

PackedByteArray LbSeal::open(const PackedByteArray &sealed) {
	if (!verify(sealed)) {
		return PackedByteArray();
	}
	const PackedByteArray iv = sealed.slice(0, IV_BYTES);
	const PackedByteArray cipher = sealed.slice(IV_BYTES, sealed.size() - MAC_BYTES);
	Ref<AESContext> aes;
	aes.instantiate();
	aes->start(AESContext::MODE_CBC_DECRYPT, key_part(0), iv);
	PackedByteArray padded = aes->update(cipher);
	aes->finish();
	if (padded.is_empty()) {
		return PackedByteArray();
	}
	const int64_t pad = padded[padded.size() - 1];
	if (pad < 1 || pad > 16 || pad > padded.size()) {
		return PackedByteArray();
	}
	return padded.slice(0, padded.size() - pad);
}

} // namespace lb::godot

#include "godot/voice/lb_opus.h"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;
namespace voice = lb::core::voice;

namespace lb::godot {

void LbOpusEncoder::_bind_methods() {
	ClassDB::bind_method(D_METHOD("setup", "bitrate", "voip"), &LbOpusEncoder::setup);
	ClassDB::bind_method(D_METHOD("encode", "pcm"), &LbOpusEncoder::encode);
}

void LbOpusEncoder::setup(int64_t bitrate, bool voip) {
	enc_ = std::make_unique<voice::OpusVoiceEncoder>(static_cast<int>(bitrate), voip);
}

PackedByteArray LbOpusEncoder::encode(const PackedFloat32Array &pcm) {
	PackedByteArray out;
	if (!enc_) {
		setup(24000, true);
	}
	if (pcm.size() != voice::OPUS_FRAME) {
		return out;
	}
	const std::vector<uint8_t> packet = enc_->encode(pcm.ptr());
	out.resize(static_cast<int64_t>(packet.size()));
	for (size_t i = 0; i < packet.size(); i++) {
		out[static_cast<int64_t>(i)] = packet[i];
	}
	return out;
}

void LbOpusDecoder::_bind_methods() {
	ClassDB::bind_method(D_METHOD("decode", "packet"), &LbOpusDecoder::decode);
	ClassDB::bind_method(D_METHOD("conceal"), &LbOpusDecoder::conceal);
	ClassDB::bind_method(D_METHOD("reset"), &LbOpusDecoder::reset);
	ClassDB::bind_method(D_METHOD("decode_lbv", "file"), &LbOpusDecoder::decode_lbv);
	ClassDB::bind_static_method("LbOpusDecoder", D_METHOD("version"), &LbOpusDecoder::version);
}

LbOpusDecoder::LbOpusDecoder() : dec_(std::make_unique<voice::OpusVoiceDecoder>()) {}

static PackedFloat32Array to_packed(const std::vector<float> &v) {
	PackedFloat32Array out;
	out.resize(static_cast<int64_t>(v.size()));
	for (size_t i = 0; i < v.size(); i++) {
		out[static_cast<int64_t>(i)] = v[i];
	}
	return out;
}

PackedFloat32Array LbOpusDecoder::decode(const PackedByteArray &packet) {
	return to_packed(dec_->decode(packet.ptr(), static_cast<size_t>(packet.size())));
}

PackedFloat32Array LbOpusDecoder::conceal() {
	return to_packed(dec_->conceal());
}

void LbOpusDecoder::reset() {
	dec_->reset();
}

PackedFloat32Array LbOpusDecoder::decode_lbv(const PackedByteArray &file) {
	PackedFloat32Array empty;
	const int64_t size = file.size();
	if (size < 14 || file[0] != 'L' || file[1] != 'B' || file[2] != 'V' || file[3] != '1') {
		return empty;
	}
	const uint8_t *p = file.ptr();
	const uint32_t pre_skip = static_cast<uint32_t>(p[4] | (p[5] << 8));
	const uint32_t samples = static_cast<uint32_t>(p[6] | (p[7] << 8) | (p[8] << 16) | (static_cast<uint32_t>(p[9]) << 24));
	const uint32_t frames = static_cast<uint32_t>(p[10] | (p[11] << 8) | (p[12] << 16) | (static_cast<uint32_t>(p[13]) << 24));
	voice::OpusVoiceDecoder dec;
	std::vector<float> all;
	int64_t pos = 14;
	for (uint32_t i = 0; i < frames; i++) {
		if (pos + 2 > size) {
			return empty;
		}
		const int64_t n = p[pos] | (p[pos + 1] << 8);
		pos += 2;
		if (pos + n > size) {
			return empty;
		}
		const std::vector<float> pcm = dec.decode(p + pos, static_cast<size_t>(n));
		if (pcm.empty()) {
			return empty;
		}
		all.insert(all.end(), pcm.begin(), pcm.end());
		pos += n;
	}
	if (pos != size || all.size() < static_cast<size_t>(pre_skip) + samples) {
		return empty;
	}
	return to_packed(std::vector<float>(all.begin() + pre_skip, all.begin() + pre_skip + samples));
}

String LbOpusDecoder::version() {
	return String(voice::opus_version());
}

} // namespace lb::godot

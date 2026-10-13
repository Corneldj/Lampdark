#include "core/voice/opus_codec.h"

#include <opus.h>

namespace lb::core::voice {

OpusVoiceEncoder::OpusVoiceEncoder(int bitrate, bool voip) {
	int error = OPUS_OK;
	enc_ = opus_encoder_create(OPUS_RATE, 1, voip ? OPUS_APPLICATION_VOIP : OPUS_APPLICATION_AUDIO, &error);
	if (error != OPUS_OK) {
		enc_ = nullptr;
		return;
	}
	opus_encoder_ctl(enc_, OPUS_SET_BITRATE(bitrate));
}

OpusVoiceEncoder::~OpusVoiceEncoder() {
	if (enc_ != nullptr) {
		opus_encoder_destroy(enc_);
	}
}

std::vector<uint8_t> OpusVoiceEncoder::encode(const float *pcm) {
	if (enc_ == nullptr) {
		return {};
	}
	std::vector<uint8_t> out(1275);
	const opus_int32 n = opus_encode_float(enc_, pcm, OPUS_FRAME, out.data(), static_cast<opus_int32>(out.size()));
	if (n < 0) {
		return {};
	}
	out.resize(static_cast<size_t>(n));
	return out;
}

OpusVoiceDecoder::OpusVoiceDecoder() {
	int error = OPUS_OK;
	dec_ = opus_decoder_create(OPUS_RATE, 1, &error);
	if (error != OPUS_OK) {
		dec_ = nullptr;
	}
}

OpusVoiceDecoder::~OpusVoiceDecoder() {
	if (dec_ != nullptr) {
		opus_decoder_destroy(dec_);
	}
}

std::vector<float> OpusVoiceDecoder::decode(const uint8_t *data, size_t size) {
	if (dec_ == nullptr || data == nullptr || size == 0) {
		return {};
	}
	std::vector<float> out(OPUS_FRAME * 6);  // up to 120 ms in one packet
	const int n = opus_decode_float(dec_, data, static_cast<opus_int32>(size), out.data(), static_cast<int>(out.size()), 0);
	if (n < 0) {
		return {};
	}
	out.resize(static_cast<size_t>(n));
	return out;
}

std::vector<float> OpusVoiceDecoder::conceal() {
	if (dec_ == nullptr) {
		return {};
	}
	std::vector<float> out(OPUS_FRAME);
	const int n = opus_decode_float(dec_, nullptr, 0, out.data(), OPUS_FRAME, 0);
	out.resize(n > 0 ? static_cast<size_t>(n) : 0);
	return out;
}

void OpusVoiceDecoder::reset() {
	if (dec_ != nullptr) {
		opus_decoder_ctl(dec_, OPUS_RESET_STATE);
	}
}

const char *opus_version() {
	return opus_get_version_string();
}

} // namespace lb::core::voice

#pragma once
// SND-07 and SND-13: Opus (libopus 1.6, vendored and built in) at 48 kHz mono, one 20 ms frame
// (960 samples) at a time: the voice pipeline's codec and the decoder for SND-13's character lines
// (.lbv), with Opus's own loss concealment for a missing frame. Engine-free.

#include <cstdint>
#include <memory>
#include <vector>

struct OpusEncoder;
struct OpusDecoder;

namespace lb::core::voice {

constexpr int OPUS_RATE = 48000;
constexpr int OPUS_FRAME = 960;  // 20 ms

class OpusVoiceEncoder {
public:
	// `voip` tunes for speech; bitrate in bits per second.
	explicit OpusVoiceEncoder(int bitrate = 24000, bool voip = true);
	~OpusVoiceEncoder();
	bool ok() const { return enc_ != nullptr; }
	// One 20 ms frame (OPUS_FRAME floats in -1..1) to one packet; empty on an error.
	std::vector<uint8_t> encode(const float *pcm);

private:
	OpusEncoder *enc_ = nullptr;
};

class OpusVoiceDecoder {
public:
	OpusVoiceDecoder();
	~OpusVoiceDecoder();
	bool ok() const { return dec_ != nullptr; }
	// One packet to OPUS_FRAME samples; empty on a malformed packet.
	std::vector<float> decode(const uint8_t *data, size_t size);
	// A lost frame: Opus's concealment, OPUS_FRAME samples.
	std::vector<float> conceal();
	void reset();

private:
	OpusDecoder *dec_ = nullptr;
};

const char *opus_version();

} // namespace lb::core::voice

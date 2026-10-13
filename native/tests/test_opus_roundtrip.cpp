// SND-07 and SND-13: libopus 1.6, built in. A 20 ms frame of speech-band audio encodes to one packet
// under the voice bitrate and decodes to 960 samples close to the original; a lost frame is
// concealed with 960 samples.
#include "doctest.h"

#include "core/voice/opus_codec.h"

#include <cmath>
#include <cstring>
#include <vector>

using namespace lb::core::voice;

TEST_CASE("Opus 1.6 encodes and decodes 20 ms frames") {
	CHECK(std::strstr(opus_version(), "1.6") != nullptr);
	OpusVoiceEncoder enc(24000, true);
	OpusVoiceDecoder dec;
	REQUIRE(enc.ok());
	REQUIRE(dec.ok());
	std::vector<float> pcm(OPUS_FRAME);
	double in_energy = 0.0, out_energy = 0.0;
	size_t total_bytes = 0;
	for (int frame = 0; frame < 50; frame++) {
		for (int i = 0; i < OPUS_FRAME; i++) {
			const double t = (frame * OPUS_FRAME + i) / 48000.0;
			pcm[i] = static_cast<float>(0.3 * std::sin(2.0 * 3.14159265358979 * 220.0 * t) + 0.1 * std::sin(2.0 * 3.14159265358979 * 660.0 * t));
		}
		const std::vector<uint8_t> packet = enc.encode(pcm.data());
		REQUIRE(!packet.empty());
		total_bytes += packet.size();
		const std::vector<float> out = dec.decode(packet.data(), packet.size());
		REQUIRE(out.size() == static_cast<size_t>(OPUS_FRAME));
		if (frame >= 10) {
			for (int i = 0; i < OPUS_FRAME; i++) {
				in_energy += pcm[i] * pcm[i];
				out_energy += out[i] * out[i];
			}
		}
	}
	CHECK(total_bytes * 8.0 / 1.0 < 24000.0 * 1.2);  // 50 frames = 1 s at about 24 kbps
	CHECK(std::fabs(10.0 * std::log10(out_energy / in_energy)) < 1.5);
	const std::vector<float> concealed = dec.conceal();
	CHECK(concealed.size() == static_cast<size_t>(OPUS_FRAME));
	CHECK(dec.decode(nullptr, 0).empty());
}

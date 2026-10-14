#pragma once
// SND-05: the microphone's clean-up, in 10 ms blocks at 48 kHz mono. Echo cancelling against the
// game's own output (the far end), then noise suppression, then nothing else: automatic gain stays
// off, or it would squash SND-06's loudness bands (GDD §15.13). Three backends behind one switch,
// voice.apm_backend: WebRTC audio processing (AEC3, noise suppression, a high-pass), SpeexDSP (the
// spike's fallback: MDF echo cancelling and its preprocessor's denoiser) or none (a pass-through;
// the client forces Mute with it). Engine-free.

#include <cstdint>
#include <memory>
#include <string>

namespace lb::core::voice {

constexpr int CAPTURE_RATE = 48000;
constexpr int CAPTURE_BLOCK = 480; // 10 ms, what both processors take
constexpr int CAPTURE_FRAME = 960; // 20 ms, what SND-06 and SND-07 take

enum class ApmBackend : uint8_t {
	WEBRTC,
	SPEEX,
	NONE,
};
enum class NoiseLevel : uint8_t {
	LOW,
	MODERATE,
	HIGH,
	VERY_HIGH,
};

// "webrtc", "speex", "none"; false for anything else.
bool parse_backend(const std::string &name, ApmBackend &out);
// "low", "moderate", "high", "very_high"; false for anything else.
bool parse_noise_level(const std::string &name, NoiseLevel &out);

class VoiceProcessor {
public:
	virtual ~VoiceProcessor() = default;
	virtual ApmBackend backend() const = 0;
	// One 10 ms block of the far end (the game's final mix, mono, 48 kHz), in render order.
	virtual void far_end(const float *block) = 0;
	// One 10 ms block of microphone samples, cleaned in place.
	virtual void capture(float *block) = 0;
	// SND-06: the echo canceller's echo return loss (dB of far end to the echo it hears); small when
	// the game's sound reaches the microphone (speakers), large or unknown (< 0) with headphones.
	virtual double echo_return_loss_db() const { return -1.0; }
};

// Every number comes from tuning (data/tuning/voice.json), passed in by the client.
struct ProcessorParams {
	ApmBackend backend = ApmBackend::WEBRTC; // voice.apm_backend
	NoiseLevel noise = NoiseLevel::MODERATE; // voice.noise_suppression_level
	double speex_echo_tail_ms = 0.0; // voice.speex_echo_tail_ms
	double speex_suppress_db[4] = {}; // voice.speex_noise_suppress_db, by level (low to very high)
};

// Null only if the backend could not start (the client then falls back, GDD §15.13).
std::unique_ptr<VoiceProcessor> make_processor(const ProcessorParams &params);

} // namespace lb::core::voice

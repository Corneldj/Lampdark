#include "core/voice/voice_processor.h"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <vector>

#include "modules/audio_processing/include/audio_processing.h"
#include "speex/speex_echo.h"
#include "speex/speex_preprocess.h"

namespace lb::core::voice {

bool parse_backend(const std::string &name, ApmBackend &out) {
	if (name == "webrtc") {
		out = ApmBackend::WEBRTC;
	} else if (name == "speex") {
		out = ApmBackend::SPEEX;
	} else if (name == "none") {
		out = ApmBackend::NONE;
	} else {
		return false;
	}
	return true;
}

bool parse_noise_level(const std::string &name, NoiseLevel &out) {
	if (name == "low") {
		out = NoiseLevel::LOW;
	} else if (name == "moderate") {
		out = NoiseLevel::MODERATE;
	} else if (name == "high") {
		out = NoiseLevel::HIGH;
	} else if (name == "very_high") {
		out = NoiseLevel::VERY_HIGH;
	} else {
		return false;
	}
	return true;
}

namespace {

// WebRTC audio processing: AEC3 (desktop mode; it estimates the far end's delay itself), then
// noise suppression at the chosen level, with a high-pass; both gain controllers off.
class WebRtcProcessor final : public VoiceProcessor {
public:
	explicit WebRtcProcessor(NoiseLevel noise) : apm_(webrtc::AudioProcessingBuilder().Create()), config_(CAPTURE_RATE, 1) {
		if (!apm_) {
			return;
		}
		webrtc::AudioProcessing::Config c;
		c.pipeline.multi_channel_render = false;
		c.pipeline.multi_channel_capture = false;
		c.echo_canceller.enabled = true;
		c.echo_canceller.mobile_mode = false;
		c.noise_suppression.enabled = true;
		using Ns = webrtc::AudioProcessing::Config::NoiseSuppression;
		const Ns::Level levels[] = {Ns::kLow, Ns::kModerate, Ns::kHigh, Ns::kVeryHigh};
		c.noise_suppression.level = levels[static_cast<int>(noise)];
		c.high_pass_filter.enabled = true;
		c.gain_controller1.enabled = false;
		c.gain_controller2.enabled = false;
		apm_->ApplyConfig(c);
	}
	bool ok() const { return apm_ != nullptr; }
	ApmBackend backend() const override { return ApmBackend::WEBRTC; }
	void far_end(const float *block) override {
		std::memcpy(far_, block, sizeof(far_));
		const float *src = far_;
		float *dst = far_;
		apm_->ProcessReverseStream(&src, config_, config_, &dst);
	}
	void capture(float *block) override {
		const float *src = block;
		float *dst = block;
		apm_->ProcessStream(&src, config_, config_, &dst);
	}

private:
	rtc::scoped_refptr<webrtc::AudioProcessing> apm_;
	webrtc::StreamConfig config_;
	float far_[CAPTURE_BLOCK] = {};
};

// SpeexDSP: MDF echo cancelling (its own playback buffer pairs far end and capture), then the
// preprocessor's denoiser linked to it for residual echo; its AGC, VAD and dereverb stay off.
class SpeexProcessor final : public VoiceProcessor {
public:
	SpeexProcessor(NoiseLevel noise, double tail_ms, const double suppress_db[4]) {
		const int tail = std::max(CAPTURE_BLOCK, static_cast<int>(tail_ms * CAPTURE_RATE / 1000.0));
		echo_ = speex_echo_state_init(CAPTURE_BLOCK, tail);
		pre_ = speex_preprocess_state_init(CAPTURE_BLOCK, CAPTURE_RATE);
		if (!echo_ || !pre_) {
			return;
		}
		int rate = CAPTURE_RATE;
		speex_echo_ctl(echo_, SPEEX_ECHO_SET_SAMPLING_RATE, &rate);
		int on = 1;
		int off = 0;
		int suppress = static_cast<int>(suppress_db[static_cast<int>(noise)]);
		speex_preprocess_ctl(pre_, SPEEX_PREPROCESS_SET_DENOISE, &on);
		speex_preprocess_ctl(pre_, SPEEX_PREPROCESS_SET_NOISE_SUPPRESS, &suppress);
		speex_preprocess_ctl(pre_, SPEEX_PREPROCESS_SET_AGC, &off);
		speex_preprocess_ctl(pre_, SPEEX_PREPROCESS_SET_VAD, &off);
		speex_preprocess_ctl(pre_, SPEEX_PREPROCESS_SET_DEREVERB, &off);
		speex_preprocess_ctl(pre_, SPEEX_PREPROCESS_SET_ECHO_STATE, echo_);
	}
	~SpeexProcessor() override {
		if (pre_) {
			speex_preprocess_state_destroy(pre_);
		}
		if (echo_) {
			speex_echo_state_destroy(echo_);
		}
	}
	bool ok() const { return echo_ != nullptr && pre_ != nullptr; }
	ApmBackend backend() const override { return ApmBackend::SPEEX; }
	void far_end(const float *block) override {
		to_pcm(block, play_);
		speex_echo_playback(echo_, play_);
	}
	void capture(float *block) override {
		to_pcm(block, rec_);
		speex_echo_capture(echo_, rec_, out_);
		speex_preprocess_run(pre_, out_);
		for (int i = 0; i < CAPTURE_BLOCK; i++) {
			block[i] = static_cast<float>(out_[i]) / 32768.0f;
		}
	}

private:
	static void to_pcm(const float *src, spx_int16_t *dst) {
		for (int i = 0; i < CAPTURE_BLOCK; i++) {
			const float v = std::clamp(src[i], -1.0f, 1.0f) * 32767.0f;
			dst[i] = static_cast<spx_int16_t>(std::lround(v));
		}
	}
	SpeexEchoState *echo_ = nullptr;
	SpeexPreprocessState *pre_ = nullptr;
	spx_int16_t play_[CAPTURE_BLOCK] = {};
	spx_int16_t rec_[CAPTURE_BLOCK] = {};
	spx_int16_t out_[CAPTURE_BLOCK] = {};
};

class PassThrough final : public VoiceProcessor {
public:
	ApmBackend backend() const override { return ApmBackend::NONE; }
	void far_end(const float *) override {}
	void capture(float *) override {}
};

} // namespace

std::unique_ptr<VoiceProcessor> make_processor(const ProcessorParams &params) {
	switch (params.backend) {
		case ApmBackend::WEBRTC: {
			auto p = std::make_unique<WebRtcProcessor>(params.noise);
			return p->ok() ? std::unique_ptr<VoiceProcessor>(std::move(p)) : nullptr;
		}
		case ApmBackend::SPEEX: {
			auto p = std::make_unique<SpeexProcessor>(params.noise, params.speex_echo_tail_ms, params.speex_suppress_db);
			return p->ok() ? std::unique_ptr<VoiceProcessor>(std::move(p)) : nullptr;
		}
		case ApmBackend::NONE:
			return std::make_unique<PassThrough>();
	}
	return nullptr;
}

} // namespace lb::core::voice

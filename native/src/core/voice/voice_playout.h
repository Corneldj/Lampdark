#pragma once
// SND-07: one incoming voice stream, from packets to samples (GDD §15.5 step 5). Packets go
// through the jitter buffer; each frame due is decoded (Opus), or concealed when one frame is
// missing, or smeared into quiet room tone when more are, so a dropped run reads as distance, never
// a glitch; the voice fades back in when frames resume. Each frame is then capped at its band's
// loudness (the speech-band RMS never above `cap_dbfs[band]`), and a telephone frame is
// band-limited with line hiss. NET-12's marked probe frames are timed, not played. Engine-free.

#include <array>
#include <cstdint>
#include <memory>
#include <vector>

#include "core/voice/band_meter.h"
#include "core/voice/jitter_buffer.h"

namespace lb::core::voice {

class OpusVoiceDecoder;

struct PlayoutParams {
	JitterParams jitter;
	double speech_low_hz = 0.0;
	double speech_high_hz = 0.0;
	std::array<double, 5> cap_dbfs = {}; // by band; [0] unused
	double smear_dbfs = -60.0; // voice.smear_level_dbfs
	double hiss_dbfs = -60.0; // voice.telephone_hiss_dbfs
	double telephone_low_hz = 300.0;
	double telephone_high_hz = 3400.0;
};

class VoicePlayout {
public:
	enum class Kind {
		FRAME,
		CONCEAL,
		SMEAR,
		END,
	};
	struct Out {
		Kind kind = Kind::FRAME;
		std::vector<float> pcm; // 960 samples at 48 kHz (none for END)
		uint8_t head = 0;
		int64_t probe_t0_us = -1; // a probe frame's send time
		double cap_gain_db = 0.0; // what the band cap took off
	};

	explicit VoicePlayout(const PlayoutParams &p);
	~VoicePlayout();
	// A downstream packet (wire::DOWN_HEADER, then Opus). False if malformed, late or a duplicate.
	bool push(const uint8_t *packet, size_t size, int64_t now_us);
	// Every frame whose time has come.
	std::vector<Out> pop(int64_t now_us);
	bool done() const { return jitter_.done(); }
	double jitter_ms() const { return jitter_.jitter_ms(); }
	int target_ms() const { return jitter_.target_ms(); }
	// The latest header: gain, flags, crackle and the apparent position (tiles).
	int gain_db() const { return gain_db_; }
	uint8_t flags() const { return flags_; }
	uint8_t crackle() const { return crackle_; }
	double x() const { return x16_ / 16.0; }
	double y() const { return y16_ / 16.0; }

private:
	void cap(std::vector<float> &pcm, int band, double &cut_db);
	void telephone(std::vector<float> &pcm);
	std::vector<float> smear(bool fade_in);

	PlayoutParams params_;
	JitterBuffer jitter_;
	std::unique_ptr<OpusVoiceDecoder> decoder_;
	BandMeter level_;
	std::array<double, 4> tel_z_ = {}; // two biquads' state: a 2nd-order band
	double tel_b_[2][5] = {};
	uint32_t noise_ = 0x2545F491u;
	double smear_lp_ = 0.0;
	bool smearing_ = false;
	int last_band_ = 1;
	int gain_db_ = 0;
	uint8_t flags_ = 0;
	uint8_t crackle_ = 0;
	int32_t x16_ = 0;
	int32_t y16_ = 0;
};

} // namespace lb::core::voice

#pragma once
// SND-06: the voice's loudness band (GDD §15.5 step 2). Each 20 ms frame of clean 48 kHz mono is
// band-passed to speech (voice.speech_band_low_hz to high_hz), measured as RMS in dBFS, and the
// median over the last voice.band_median_ms is read against four thresholds (whisper, talk,
// shout, scream). The band rises at once and falls only after voice.band_hysteresis_s below its
// threshold, so it does not flicker between words. Band 0 is silent; voice activation opens at 1.
// Client-only (it shapes what is sent, never the simulation). Engine-free.

#include <array>
#include <cstdint>
#include <vector>

namespace lb::core::voice {

struct BandParams {
	double rate = 48000.0;
	double low_hz = 0.0; // voice.speech_band_low_hz
	double high_hz = 0.0; // voice.speech_band_high_hz
	int median_frames = 1; // voice.band_median_ms / voice.frame_ms
	int hysteresis_frames = 1; // voice.band_hysteresis_s / voice.frame_ms
	std::array<double, 4> thresholds_dbfs = {}; // whisper, talk, shout, scream
};

class BandMeter {
public:
	static constexpr double FLOOR_DBFS = -120.0;

	explicit BandMeter(const BandParams &params);
	// One frame (any length; 960 samples at 48 kHz is 20 ms). Returns the band, 0-4.
	int push(const float *samples, size_t count);
	int band() const { return band_; }
	// The last frame's speech-band level, and the median the band is read from.
	double level_dbfs() const { return level_; }
	double median_dbfs() const { return median_; }
	// New thresholds (a calibration), keeping the filter and the history.
	void set_thresholds(const std::array<double, 4> &t) { params_.thresholds_dbfs = t; }
	void reset();

private:
	struct Biquad {
		double b0 = 1, b1 = 0, b2 = 0, a1 = 0, a2 = 0;
		double z1 = 0, z2 = 0;
		double run(double x) {
			const double y = b0 * x + z1;
			z1 = b1 * x - a1 * y + z2;
			z2 = b2 * x - a2 * y;
			return y;
		}
	};
	int band_for(double dbfs) const;

	BandParams params_;
	std::array<Biquad, 4> filter_{}; // two high-pass, two low-pass: 4th-order edges
	std::vector<double> history_;
	size_t filled_ = 0;
	size_t next_ = 0;
	double level_ = FLOOR_DBFS;
	double median_ = FLOOR_DBFS;
	int band_ = 0;
	int below_ = 0;
};

} // namespace lb::core::voice

#pragma once
// SND-06: the loudness band meter for GDScript (client/audio/voice_bands.gd, calibration.gd).

#include "core/voice/band_meter.h"

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>

#include <memory>

namespace lb::godot {

class LbBandMeter : public ::godot::RefCounted {
	GDCLASS(LbBandMeter, ::godot::RefCounted)

public:
	// The speech band's edges (Hz), the median and hysteresis in frames, and four thresholds (dBFS:
	// whisper, talk, shout, scream). False when the thresholds are not four.
	bool configure(double low_hz, double high_hz, int64_t median_frames, int64_t hysteresis_frames,
			const ::godot::PackedFloat32Array &thresholds_dbfs);
	void set_thresholds(const ::godot::PackedFloat32Array &thresholds_dbfs);
	// One frame of 48 kHz mono; returns the band, 0 (silent) to 4 (scream).
	int64_t push(const ::godot::PackedFloat32Array &pcm);
	int64_t band() const;
	double level_dbfs() const;
	double median_dbfs() const;
	void reset();

protected:
	static void _bind_methods();

private:
	std::unique_ptr<lb::core::voice::BandMeter> meter_;
};

} // namespace lb::godot

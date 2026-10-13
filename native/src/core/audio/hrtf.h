#pragma once
// SND-04: the headphone path's HRTF renderer. The mixer hands it one mono block per source (after
// the source's gain and rear low-pass) and the source's azimuth off the facing; it returns the two
// ears. Steam Audio's binaural effect implements it (phonon_hrtf); without it the mixer falls back to
// the spherical-head model in spatializer.h. Engine-free.

#include <cstdint>

namespace lb::core::audio {

class Hrtf {
public:
	virtual ~Hrtf() = default;
	// Samples per block; process() always takes exactly this many.
	virtual int frame_size() const = 0;
	// A per-source state (its own interpolation history); 0 when none could be made.
	virtual uint32_t open() = 0;
	virtual void close(uint32_t id) = 0;
	// One block: `in` mono, `left` and `right` written (not added). Azimuth in degrees, 0 ahead,
	// positive to the right, as azimuth_deg() gives it.
	virtual void process(uint32_t id, double azimuth_deg, const float *in, float *left, float *right) = 0;
	virtual const char *name() const = 0;
};

} // namespace lb::core::audio

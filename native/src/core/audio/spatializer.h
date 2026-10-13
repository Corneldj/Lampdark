#pragma once
// SND-04: the client's ears. Everything here is facing-relative: a source's azimuth is the angle
// from the own miner to it in the frame of the miner's facing (0 straight ahead, positive to the
// right, screen space with +y down), elevation 0, and nothing depends on distance: a source's gain
// is what the server delivered (SND-03, SND-07). Three output modes share one rear low-pass that
// deepens across the blind area: equal-power panning (speakers), a spherical-head binaural model
// (headphones: an interaural delay and the far ear's head shadow), and mono (the panned signal summed).
// Engine-free.

#include <cstdint>
#include <utility>

namespace lb::core::audio {

enum class OutputMode : uint8_t { HEADPHONES = 0, SPEAKERS = 1, MONO = 2 };

struct Pose {
	double x = 0.0, y = 0.0;    // tiles
	double facing_turns = 0.0;  // 0 east, clockwise (screen space, +y down)
};

struct RearParams {
	double start_deg = 55.0;   // noise.rear_filter_start_deg: no filtering inside the cone
	double min_hz = 2000.0;    // noise.rear_lowpass_min_hz: the cutoff straight behind
	double max_hz = 20000.0;   // where the falloff starts (effectively open)
};

// The source's azimuth in degrees, (-180, 180]: 0 ahead, +90 to the right, -90 to the left.
double azimuth_deg(const Pose &pose, double sx, double sy);

// Equal-power speaker gains {left, right} for an azimuth; front and back fold onto the same pan.
std::pair<double, double> pan_gains(double az_deg);

// The rear low-pass cutoff (Hz) for an azimuth: 0 (none) within +-start_deg, then log-linear from
// max_hz at start_deg to min_hz at 180.
double rear_cutoff_hz(double az_deg, const RearParams &p);

// The spherical-head model (Woodworth's interaural delay; the far ear shadowed by a low-pass and a
// level drop growing with laterality). A source to the left has the left ear near.
struct Binaural {
	bool left_near = true;
	double itd_s = 0.0;            // the far ear's delay
	double far_gain = 1.0;         // the far ear's level (linear)
	double far_cutoff_hz = 0.0;    // the far ear's head-shadow low-pass (0: none)
};
Binaural binaural(double az_deg);

// A one-pole low-pass; cutoff 0 bypasses it.
class OnePole {
public:
	void set(double cutoff_hz, double sample_rate);
	float process(float x);
	bool bypassed() const { return a_ <= 0.0; }

private:
	double a_ = 0.0;  // 0: bypass
	double z_ = 0.0;
};

} // namespace lb::core::audio

#include "core/audio/spatializer.h"

#include <cmath>

namespace lb::core::audio {

namespace {
constexpr double PI = 3.14159265358979323846;
constexpr double HEAD_RADIUS_M = 0.0875;
constexpr double SPEED_OF_SOUND = 343.0;
} // namespace

double azimuth_deg(const Pose &pose, double sx, double sy) {
	const double vx = sx - pose.x;
	const double vy = sy - pose.y;
	if (vx * vx + vy * vy < 1e-12) {
		return 0.0;
	}
	// Screen space: angles clockwise from east (+y down), as the facing is.
	const double source_deg = std::atan2(vy, vx) * 180.0 / PI;  // determinism: allow (client audio output, never sim state)
	double az = source_deg - pose.facing_turns * 360.0;
	az = std::fmod(az, 360.0);
	if (az <= -180.0) {
		az += 360.0;
	} else if (az > 180.0) {
		az -= 360.0;
	}
	return az;
}

std::pair<double, double> pan_gains(double az_deg) {
	// Pan position -1 (left) .. 1 (right) from the lateral component.
	const double p = std::sin(az_deg * PI / 180.0);  // determinism: allow (client audio output, never sim state)
	const double theta = (p + 1.0) * PI / 4.0;  // 0 .. pi/2
	return {std::cos(theta), std::sin(theta)};  // determinism: allow (client audio output, never sim state)
}

double rear_cutoff_hz(double az_deg, const RearParams &p) {
	const double a = std::fabs(az_deg);
	if (a <= p.start_deg) {
		return 0.0;
	}
	const double t = (a - p.start_deg) / (180.0 - p.start_deg);
	return std::exp(std::log(p.max_hz) + (std::log(p.min_hz) - std::log(p.max_hz)) * (t > 1.0 ? 1.0 : t));  // determinism: allow (client audio output, never sim state)
}

Binaural binaural(double az_deg) {
	Binaural b;
	b.left_near = az_deg <= 0.0;
	double lateral = std::fabs(az_deg);
	if (lateral > 90.0) {
		lateral = 180.0 - lateral;  // the cone of confusion: the rear filter tells front from back
	}
	const double th = lateral * PI / 180.0;
	b.itd_s = HEAD_RADIUS_M / SPEED_OF_SOUND * (th + std::sin(th));  // determinism: allow (client audio output, never sim state)
	const double s = std::sin(th);  // determinism: allow (client audio output, never sim state)
	b.far_gain = std::pow(10.0, -10.0 * s / 20.0);       // up to -10 dB fully lateral; determinism: allow (client audio output, never sim state)
	b.far_cutoff_hz = s < 0.05 ? 0.0 : 20000.0 * std::pow(0.075, s);  // ~1.5 kHz fully lateral; determinism: allow (client audio output, never sim state)
	return b;
}

void OnePole::set(double cutoff_hz, double sample_rate) {
	if (cutoff_hz <= 0.0 || cutoff_hz >= sample_rate * 0.49) {
		a_ = 0.0;
		return;
	}
	a_ = 1.0 - std::exp(-2.0 * PI * cutoff_hz / sample_rate);  // determinism: allow (client audio output, never sim state)
}

float OnePole::process(float x) {
	if (a_ <= 0.0) {
		z_ = x;
		return x;
	}
	z_ += a_ * (static_cast<double>(x) - z_);
	return static_cast<float>(z_);
}

} // namespace lb::core::audio

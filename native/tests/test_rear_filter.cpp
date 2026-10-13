// SND-04: the rear low-pass. None within +-55 degrees of facing (the cone); beyond, the cutoff falls
// log-linearly to 2 kHz straight behind, on every output mode, so what you cannot see sounds dull.
#include "doctest.h"

#include "core/audio/mixer.h"

#include <cmath>
#include <vector>

using namespace lb::core::audio;

namespace {

// RMS of a 6 kHz tone heard from azimuth `az` (source at distance 10 around a miner facing east).
double rms_at(double az_deg, OutputMode mode) {
	Mixer m(44100.0);
	m.set_mode(mode);
	m.set_pose(Pose{0, 0, 0.0});
	SourceDesc d;
	d.rate = 44100.0;
	d.samples.resize(20000);
	for (size_t i = 0; i < d.samples.size(); i++) {
		d.samples[i] = static_cast<float>(0.5 * std::sin(2.0 * 3.14159265358979 * 6000.0 * i / 44100.0));
	}
	d.x = 10.0 * std::cos(az_deg * 3.14159265358979 / 180.0);
	d.y = 10.0 * std::sin(az_deg * 3.14159265358979 / 180.0);
	m.add(d);
	std::vector<float> out(8192 * 2);
	m.mix(0, out.data(), 8192);
	double e = 0.0;
	for (size_t f = 1024; f < 8192; f++) {
		e += out[f * 2] * out[f * 2] + out[f * 2 + 1] * out[f * 2 + 1];
	}
	return std::sqrt(e / 7168.0);
}

} // namespace

TEST_CASE("the cutoff: none inside the cone, 2 kHz straight behind, log-linear between") {
	RearParams p;
	CHECK(rear_cutoff_hz(0.0, p) == 0.0);
	CHECK(rear_cutoff_hz(54.9, p) == 0.0);
	CHECK(rear_cutoff_hz(-55.0, p) == 0.0);
	CHECK(rear_cutoff_hz(180.0, p) == doctest::Approx(2000.0));
	CHECK(rear_cutoff_hz(-180.0, p) == doctest::Approx(2000.0));
	const double mid = rear_cutoff_hz(117.5, p);  // halfway in angle: the geometric mean
	CHECK(mid == doctest::Approx(std::sqrt(2000.0 * 20000.0)).epsilon(1e-6));
	CHECK(rear_cutoff_hz(100.0, p) > rear_cutoff_hz(150.0, p));
}

TEST_CASE("behind is duller than ahead on every output") {
	for (OutputMode mode : {OutputMode::SPEAKERS, OutputMode::HEADPHONES, OutputMode::MONO}) {
		const double ahead = rms_at(0.0, mode);
		const double behind = rms_at(180.0, mode);
		CHECK(behind < ahead * 0.5);  // a 6 kHz tone through 2 kHz
		const double side = rms_at(100.0, mode);
		CHECK(side > behind);
	}
}

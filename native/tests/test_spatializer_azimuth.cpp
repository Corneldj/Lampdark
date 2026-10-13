// SND-04: facing-relative azimuth and the three output modes. A fixed source due north of a miner
// facing north is centred; facing south it is centred (and filtered: test_rear_filter); facing
// east it sits hard left on speakers and fully lateral left on headphones.
#include "doctest.h"

#include "core/audio/mixer.h"

#include <cmath>
#include <vector>

using namespace lb::core::audio;

namespace {

constexpr double NORTH = 0.75, SOUTH = 0.25, EAST = 0.0;

// The steady-state left and right RMS of a 440 Hz tone from (0, -10) heard at the origin.
std::pair<double, double> rms(OutputMode mode, double facing, std::vector<float> *raw = nullptr) {
	Mixer m(44100.0);
	m.set_mode(mode);
	m.set_pose(Pose{0.0, 0.0, facing});
	SourceDesc d;
	d.rate = 44100.0;
	d.samples.resize(44100);
	for (size_t i = 0; i < d.samples.size(); i++) {
		d.samples[i] = static_cast<float>(0.5 * std::sin(2.0 * 3.14159265358979 * 440.0 * i / 44100.0));
	}
	d.x = 0.0;
	d.y = -10.0;
	m.add(d);
	std::vector<float> out(8192 * 2);
	m.mix(0, out.data(), 8192);
	double l = 0.0, r = 0.0;
	for (size_t f = 2048; f < 8192; f++) {
		l += out[f * 2] * out[f * 2];
		r += out[f * 2 + 1] * out[f * 2 + 1];
	}
	if (raw != nullptr) {
		*raw = out;
	}
	return {std::sqrt(l / 6144.0), std::sqrt(r / 6144.0)};
}

} // namespace

TEST_CASE("azimuth is facing-relative: 0 ahead, +90 right, -90 left, 180 behind") {
	CHECK(azimuth_deg(Pose{0, 0, NORTH}, 0, -10) == doctest::Approx(0.0));
	CHECK(std::fabs(azimuth_deg(Pose{0, 0, SOUTH}, 0, -10)) == doctest::Approx(180.0));
	CHECK(azimuth_deg(Pose{0, 0, EAST}, 0, -10) == doctest::Approx(-90.0));
	CHECK(azimuth_deg(Pose{0, 0, EAST}, 0, 10) == doctest::Approx(90.0));
	CHECK(azimuth_deg(Pose{5, 5, NORTH}, 5, 4) == doctest::Approx(0.0));
}

TEST_CASE("north, facing north: centred on every output") {
	for (OutputMode mode : {OutputMode::SPEAKERS, OutputMode::HEADPHONES, OutputMode::MONO}) {
		const auto g = rms(mode, NORTH);
		CHECK(g.first == doctest::Approx(g.second).epsilon(1e-3));
		CHECK(g.first > 0.1);
	}
}

TEST_CASE("north, facing south: centred on every output") {
	for (OutputMode mode : {OutputMode::SPEAKERS, OutputMode::HEADPHONES, OutputMode::MONO}) {
		const auto g = rms(mode, SOUTH);
		CHECK(g.first == doctest::Approx(g.second).epsilon(1e-3));
	}
}

TEST_CASE("north, facing east: hard left on speakers, fully lateral left on headphones, centred in mono") {
	const auto sp = rms(OutputMode::SPEAKERS, EAST);
	CHECK(sp.second < 1e-6);
	CHECK(sp.first > 0.3);
	std::vector<float> raw;
	const auto hp = rms(OutputMode::HEADPHONES, EAST, &raw);
	CHECK(hp.first > hp.second * 2.0);  // the far ear shadowed by 10 dB at 440 Hz and more above
	// The right ear lags by the full interaural delay (about 0.66 ms, 29 samples at 44.1 kHz).
	const Binaural b = binaural(-90.0);
	CHECK(b.left_near);
	CHECK(b.itd_s == doctest::Approx(0.0875 / 343.0 * (3.14159265358979 / 2.0 + 1.0)).epsilon(1e-6));
	size_t first_left = 0, first_right = 0;
	for (size_t f = 0; f < 200; f++) {
		if (first_left == 0 && std::fabs(raw[f * 2]) > 1e-6) first_left = f;
		if (first_right == 0 && std::fabs(raw[f * 2 + 1]) > 1e-6) first_right = f;
	}
	CHECK(first_right >= first_left + 25);
	const auto mono = rms(OutputMode::MONO, EAST);
	CHECK(mono.first == doctest::Approx(mono.second).epsilon(1e-6));
}

TEST_CASE("front and back fold onto the same pan; the rear filter tells them apart") {
	const auto front = pan_gains(30.0);
	const auto back = pan_gains(150.0);
	CHECK(front.first == doctest::Approx(back.first));
	CHECK(front.second == doctest::Approx(back.second));
	const auto centre = pan_gains(0.0);
	CHECK(centre.first * centre.first + centre.second * centre.second == doctest::Approx(1.0));
}

#ifdef LB_DEBUG_TOOLS
TEST_CASE("screen-up (dev and QA only): the listener faces north whatever the facing") {
	Mixer m;
	m.set_pose(Pose{0, 0, EAST});
	SourceDesc d;
	d.samples.assign(100, 0.1f);
	d.x = 0;
	d.y = -5;
	const uint32_t id = m.add(d);
	CHECK(m.azimuth_of(id) == doctest::Approx(-90.0));
	m.set_screen_up(true);
	CHECK(m.azimuth_of(id) == doctest::Approx(0.0));
}
#endif

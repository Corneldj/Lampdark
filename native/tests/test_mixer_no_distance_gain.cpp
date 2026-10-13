// SND-04: positional sounds carry no added distance cue. The same source at 1, 10 and 60 tiles in the
// same direction mixes to the same output; only the server's gain (SND-03) changes loudness.
#include "doctest.h"

#include "core/audio/mixer.h"

#include <cmath>
#include <vector>

using namespace lb::core::audio;

namespace {

std::vector<float> mixed(double distance, double gain_db, OutputMode mode) {
	Mixer m(44100.0);
	m.set_mode(mode);
	m.set_pose(Pose{3.0, 4.0, 0.1});
	SourceDesc d;
	d.rate = 22050.0;
	d.samples.resize(4000);
	for (size_t i = 0; i < d.samples.size(); i++) {
		d.samples[i] = static_cast<float>(std::sin(i * 0.37) * 0.4);
	}
	d.x = 3.0 + distance * 0.6;
	d.y = 4.0 + distance * 0.8;
	d.gain_db = gain_db;
	m.add(d);
	std::vector<float> out(4096 * 2);
	m.mix(0, out.data(), 4096);
	return out;
}

} // namespace

TEST_CASE("distance changes nothing inside the mixer") {
	for (OutputMode mode : {OutputMode::SPEAKERS, OutputMode::HEADPHONES, OutputMode::MONO}) {
		const std::vector<float> near = mixed(1.0, 0.0, mode);
		CHECK(mixed(10.0, 0.0, mode) == near);
		CHECK(mixed(60.0, 0.0, mode) == near);
	}
}

TEST_CASE("the server's gain is the only level: -20 dB is a tenth of the amplitude") {
	const std::vector<float> full = mixed(5.0, 0.0, OutputMode::SPEAKERS);
	const std::vector<float> dipped = mixed(5.0, -20.0, OutputMode::SPEAKERS);
	for (size_t i = 0; i < full.size(); i += 97) {
		CHECK(dipped[i] == doctest::Approx(full[i] * 0.1).epsilon(1e-4));
	}
}

TEST_CASE("groups mix apart; finished sources drop; loops keep playing") {
	Mixer m(44100.0);
	SourceDesc a;
	a.samples.assign(100, 0.5f);
	a.rate = 44100.0;
	a.group = 1;
	SourceDesc b = a;
	b.group = 2;
	b.loop = true;
	m.add(a);
	m.add(b);
	std::vector<float> out(512 * 2);
	m.mix(1, out.data(), 512);
	CHECK(m.count() == 1);  // the one-shot in group 1 finished
	m.mix(2, out.data(), 512);
	m.mix(2, out.data(), 512);
	CHECK(m.count() == 1);  // the loop plays on
	CHECK(out[1000] != 0.0f);
}

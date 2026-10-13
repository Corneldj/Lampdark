// SND-04: Steam Audio's HRTF on the headphone path. The library loads from beside this runner (the
// build copies it into native/bin), and through it a fixed source is centred ahead, lateral when the
// miner turns, dulled behind, and never louder or quieter with distance.
#include "doctest.h"

#include "core/audio/mixer.h"
#include "core/audio/phonon_hrtf.h"

#include <cmath>
#include <memory>
#include <vector>

using namespace lb::core::audio;

namespace {

constexpr double NORTH = 0.75, SOUTH = 0.25, EAST = 0.0;

std::shared_ptr<Hrtf> load() {
	std::shared_ptr<Hrtf> h(PhononHrtf::load(48000, 512).release());
	return h;
}

// Left and right RMS (and the raw mix) of a tone at (x, y) heard from the origin.
std::pair<double, double> hear(std::shared_ptr<Hrtf> h, double facing, double x, double y, double hz, OutputMode mode,
		std::vector<float> *raw = nullptr) {
	Mixer m(48000.0);
	m.set_hrtf(h);
	m.set_mode(mode);
	m.set_pose(Pose{0, 0, facing});
	SourceDesc d;
	d.rate = 48000.0;
	d.samples.resize(48000);
	uint32_t state = 12345u;
	for (size_t i = 0; i < d.samples.size(); i++) {
		if (hz > 0.0) {
			d.samples[i] = static_cast<float>(0.4 * std::sin(2.0 * 3.14159265358979 * hz * i / 48000.0));
		} else {  // broadband noise: hz 0
			state = state * 1664525u + 1013904223u;
			d.samples[i] = static_cast<float>(0.4 * (static_cast<int32_t>(state) / 2147483648.0));
		}
	}
	d.x = x;
	d.y = y;
	m.add(d);
	std::vector<float> out(8192 * 2);
	for (int pass = 0; pass < 2; pass++) {  // the second pass is past the HRTF's start-up
		m.mix(0, out.data(), 4096);
	}
	m.mix(0, out.data(), 8192);
	double l = 0.0, r = 0.0;
	for (size_t f = 0; f < 8192; f++) {
		l += out[f * 2] * out[f * 2];
		r += out[f * 2 + 1] * out[f * 2 + 1];
	}
	if (raw != nullptr) {
		*raw = out;
	}
	return {std::sqrt(l / 8192.0), std::sqrt(r / 8192.0)};
}

} // namespace

TEST_CASE("Steam Audio loads from beside the runner") {
	std::shared_ptr<Hrtf> h = load();
	INFO(PhononHrtf::last_error());
	REQUIRE(static_cast<bool>(h));
	CHECK(std::string(h->name()) == "steam_audio");
	CHECK(h->frame_size() == 512);
	const uint32_t id = h->open();
	CHECK(id != 0);
	h->close(id);
}

TEST_CASE("HRTF: north while facing north is centred (broadband, the measured head's median plane found at load)") {
	std::shared_ptr<Hrtf> h = load();
	REQUIRE(static_cast<bool>(h));
	CHECK(std::fabs(static_cast<PhononHrtf *>(h.get())->centre_deg()) < 15.0);
	const auto g = hear(h, NORTH, 0, -10, 0.0, OutputMode::HEADPHONES);
	CHECK(g.first > 0.05);
	CHECK(std::fabs(20.0 * std::log10(g.first / g.second)) < 1.0);
}

TEST_CASE("HRTF: facing east, the same source is fully lateral left") {
	std::shared_ptr<Hrtf> h = load();
	REQUIRE(static_cast<bool>(h));
	const auto g = hear(h, EAST, 0, -10, 0.0, OutputMode::HEADPHONES);
	CHECK(20.0 * std::log10(g.first / g.second) > 10.0);  // the head shadows the right ear
	const auto right = hear(h, EAST, 0, 10, 0.0, OutputMode::HEADPHONES);
	CHECK(20.0 * std::log10(right.second / right.first) > 10.0);
	const auto behind = hear(h, SOUTH, 0, -10, 0.0, OutputMode::HEADPHONES);
	CHECK(std::fabs(20.0 * std::log10(behind.first / behind.second)) < 1.0);  // behind: centred too
}

TEST_CASE("HRTF: facing south, the source behind is dulled by the rear low-pass") {
	std::shared_ptr<Hrtf> h = load();
	REQUIRE(static_cast<bool>(h));
	const auto ahead = hear(h, NORTH, 0, -10, 6000.0, OutputMode::HEADPHONES);
	const auto behind = hear(h, SOUTH, 0, -10, 6000.0, OutputMode::HEADPHONES);
	CHECK(behind.first + behind.second < 0.5 * (ahead.first + ahead.second));
}

TEST_CASE("HRTF: no distance cue, and mono sums the ears") {
	std::shared_ptr<Hrtf> h = load();
	REQUIRE(static_cast<bool>(h));
	std::vector<float> near, far;
	hear(h, EAST, 0.3, -2, 800.0, OutputMode::HEADPHONES, &near);
	hear(h, EAST, 3.0, -20, 800.0, OutputMode::HEADPHONES, &far);
	CHECK(near == far);
	const auto mono = hear(h, EAST, 0, -10, 800.0, OutputMode::MONO);
	CHECK(mono.first == doctest::Approx(mono.second).epsilon(1e-6));
	const auto speakers = hear(h, EAST, 0, -10, 800.0, OutputMode::SPEAKERS);
	CHECK(speakers.second < 1e-6);  // speakers still pan, hard left
}

TEST_CASE("a one-shot through the HRTF finishes and leaves the mixer") {
	std::shared_ptr<Hrtf> h = load();
	REQUIRE(static_cast<bool>(h));
	Mixer m(48000.0);
	m.set_hrtf(h);
	SourceDesc d;
	d.rate = 48000.0;
	d.samples.assign(1000, 0.2f);
	d.y = -3;
	m.add(d);
	std::vector<float> out(2048 * 2);
	m.mix(0, out.data(), 2048);
	CHECK(m.count() == 0);
	m.set_hrtf(nullptr);
	m.add(d);
	m.mix(0, out.data(), 2048);
	CHECK(m.count() == 0);  // the fallback model too
}

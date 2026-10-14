// SND-06: the loudness band meter: levels to bands at the default thresholds, the 100 ms median's
// step response, the 0.3 s hysteresis, the speech-band filter, and laughter against desk noise.

#include "doctest.h"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <vector>

#include "core/voice/band_meter.h"
#include "core/voice/voice_processor.h"
#include "voice_signals.h"

using namespace lb::core::voice;
using namespace voice_signals;

namespace {

constexpr size_t FRAME = 960;

BandParams defaults() {
	BandParams p;
	p.low_hz = 300.0;
	p.high_hz = 3400.0;
	p.median_frames = 5; // 100 ms
	p.hysteresis_frames = 15; // 0.3 s
	p.thresholds_dbfs = {-50.0, -40.0, -22.0, -12.0};
	return p;
}

// Noise well inside the speech band (4th-order edges at 600 and 2800 Hz), scaled to `dbfs` RMS.
std::vector<float> speech_band_noise(size_t n, double dbfs, uint32_t seed) {
	BandParams shape = defaults();
	shape.low_hz = 600.0;
	shape.high_hz = 2800.0;
	struct Q {
		double b0, b1, b2, a1, a2, z1 = 0, z2 = 0;
		double run(double x) {
			const double y = b0 * x + z1;
			z1 = b1 * x - a1 * y + z2;
			z2 = b2 * x - a2 * y;
			return y;
		}
	};
	auto make = [](double hz, bool high) {
		const double w = 2.0 * 3.14159265358979 * hz / 48000.0;
		const double c = std::cos(w);
		const double alpha = std::sin(w) / (2.0 * 0.7071067811865476);
		const double a0 = 1.0 + alpha;
		Q q{};
		q.b0 = (high ? (1.0 + c) : (1.0 - c)) / 2.0 / a0;
		q.b1 = (high ? -(1.0 + c) : (1.0 - c)) / a0;
		q.b2 = q.b0;
		q.a1 = -2.0 * c / a0;
		q.a2 = (1.0 - alpha) / a0;
		return q;
	};
	Q f[4] = {make(shape.low_hz, true), make(shape.low_hz, true), make(shape.high_hz, false), make(shape.high_hz, false)};
	Lcg r(seed);
	std::vector<float> x(n);
	for (size_t i = 0; i < n + 4800; i++) { // the first 0.1 s, the filters' start-up, is dropped
		double v = r.next();
		for (Q &q : f) {
			v = q.run(v);
		}
		if (i >= 4800) {
			x[i - 4800] = static_cast<float>(v);
		}
	}
	double e = 0.0;
	for (float v : x) {
		e += static_cast<double>(v) * v;
	}
	const double scale = std::pow(10.0, dbfs / 20.0) / std::sqrt(e / static_cast<double>(n));
	for (float &v : x) {
		v = static_cast<float>(v * scale);
	}
	return x;
}

std::vector<float> tone(size_t n, double hz, double dbfs) {
	std::vector<float> x(n);
	const double amp = std::pow(10.0, dbfs / 20.0) * std::sqrt(2.0);
	for (size_t i = 0; i < n; i++) {
		x[i] = static_cast<float>(amp * std::sin(2.0 * 3.14159265358979 * hz * static_cast<double>(i) / 48000.0));
	}
	return x;
}

// Bands frame by frame.
std::vector<int> bands(BandMeter &m, const std::vector<float> &x) {
	std::vector<int> out;
	for (size_t at = 0; at + FRAME <= x.size(); at += FRAME) {
		out.push_back(m.push(x.data() + at, FRAME));
	}
	return out;
}

} // namespace

TEST_CASE("SND-06: speech-band noise at -55, -45, -30, -20 and -10 dBFS reads silent to scream") {
	const double levels[5] = {-55.0, -45.0, -30.0, -20.0, -10.0};
	for (int k = 0; k < 5; k++) {
		BandMeter m(defaults());
		const std::vector<int> b = bands(m, speech_band_noise(48000, levels[k], 3 + k));
		CHECK(b.back() == k);
		INFO("level ", levels[k], " measured ", m.median_dbfs());
		CHECK(std::fabs(m.median_dbfs() - levels[k]) < 1.5); // a median of five 20 ms noise frames scatters
	}
}

TEST_CASE("SND-06: a step up raises the band within 60 ms, once 3 of 5 frames are above") {
	BandMeter m(defaults());
	std::vector<float> x(FRAME * 20, 0.0f);
	const std::vector<float> talk = speech_band_noise(FRAME * 10, -30.0, 7);
	x.insert(x.end(), talk.begin(), talk.end());
	const std::vector<int> b = bands(m, x);
	CHECK(b[19] == 0);
	CHECK(b[20] == 0); // 1 of 5 above
	CHECK(b[21] == 0); // 2 of 5
	CHECK(b[22] == 2); // 3 of 5: talk, 60 ms after the step
}

TEST_CASE("SND-06: a 0.25 s dip keeps the band; a 0.35 s dip lowers it") {
	for (int dip_frames : {12, 18}) { // 0.24 s and 0.36 s
		BandMeter m(defaults());
		std::vector<float> x = speech_band_noise(FRAME * 20, -30.0, 9);
		x.insert(x.end(), FRAME * dip_frames, 0.0f);
		const std::vector<float> back = speech_band_noise(FRAME * 10, -30.0, 10);
		x.insert(x.end(), back.begin(), back.end());
		const std::vector<int> b = bands(m, x);
		const int lowest = *std::min_element(b.begin() + 20, b.end());
		if (dip_frames == 12) {
			CHECK(lowest == 2); // the band held through the gap between words
		} else {
			CHECK(lowest == 0); // a real pause: down to silent
		}
		CHECK(b.back() == 2);
	}
}

TEST_CASE("SND-06: the speech band ignores hum below it and hiss above it") {
	BandMeter hum(defaults());
	CHECK(bands(hum, tone(48000, 60.0, -20.0)).back() == 0); // mains hum at shout level: silent
	BandMeter hiss(defaults());
	CHECK(bands(hiss, tone(48000, 12000.0, -20.0)).back() == 0); // a whine far above speech
	BandMeter voice(defaults());
	CHECK(bands(voice, tone(48000, 1000.0, -30.0)).back() == 2); // inside the band: talk
}

TEST_CASE("SND-06: new thresholds (a calibration) take effect without losing the history") {
	BandMeter m(defaults());
	bands(m, speech_band_noise(FRAME * 10, -38.0, 4));
	CHECK(m.band() == 2); // talk at the default -40
	m.set_thresholds({-50.0, -36.0, -22.0, -12.0}); // a louder speaker's talk threshold
	bands(m, speech_band_noise(FRAME * 20, -38.0, 5));
	CHECK(m.band() == 1);
}

TEST_CASE("SND-06: laughter opens whisper or above; keyboard and desk fan stay silent after clean-up") {
	ProcessorParams pp;
	pp.backend = ApmBackend::WEBRTC;
	pp.noise = NoiseLevel::MODERATE;
	const std::vector<float> silence(48000 * 10, 0.0f);
	auto run = [&](const std::vector<float> &mic) {
		auto p = make_processor(pp);
		REQUIRE(p);
		std::vector<float> out(mic.size());
		for (size_t at = 0; at + CAPTURE_BLOCK <= mic.size(); at += CAPTURE_BLOCK) {
			p->far_end(silence.data());
			float block[CAPTURE_BLOCK];
			std::copy(mic.begin() + static_cast<long>(at), mic.begin() + static_cast<long>(at + CAPTURE_BLOCK), block);
			p->capture(block);
			std::copy(block, block + CAPTURE_BLOCK, out.begin() + static_cast<long>(at));
		}
		return out;
	};
	// Laughter: voiced 'ha' bursts, a 260 Hz fundamental with harmonics, five a second, quiet (-36 dBFS).
	std::vector<float> laugh(48000 * 10);
	for (size_t i = 0; i < laugh.size(); i++) {
		const double t = static_cast<double>(i) / 48000.0;
		const double env = std::fmax(0.0, std::sin(2.0 * 3.14159265358979 * 5.0 * t));
		double v = 0.0;
		for (int h = 1; h <= 8; h++) {
			v += std::sin(2.0 * 3.14159265358979 * 260.0 * h * t) / h;
		}
		laugh[i] = static_cast<float>(0.025 * env * v);
	}
	std::vector<float> desk(48000 * 10);
	const std::vector<float> f = fan(desk.size(), 31, 0.007f);
	const std::vector<float> k = keyboard(desk.size(), 32, 0.05f);
	for (size_t i = 0; i < desk.size(); i++) {
		desk[i] = f[i] + k[i];
	}
	BandMeter lm(defaults());
	const std::vector<int> lb = bands(lm, run(laugh));
	BandMeter dm(defaults());
	const std::vector<int> db = bands(dm, run(desk));
	CHECK(*std::max_element(lb.begin() + 100, lb.end()) >= 1); // laughter counts
	CHECK(*std::max_element(db.begin() + 100, db.end()) == 0); // typing and the fan do not
}

TEST_CASE("SND-06: the echo estimate tells speakers from headphones (the speakers warning)") {
	ProcessorParams pp;
	pp.backend = ApmBackend::WEBRTC;
	pp.noise = NoiseLevel::MODERATE;
	const size_t n = 48000 * 8;
	const std::vector<float> far = speechlike(n, 41, 0.3f);
	const std::vector<float> talk = speechlike(n, 42, 0.1f);
	double erl[2] = {-1.0, -1.0};
	for (int k = 0; k < 2; k++) {
		// k = 0: speakers (the game's sound reaches the mic at -6 dB); k = 1: headphones (it does not).
		const std::vector<float> echo = echo_of(far, 48 * 20, k == 0 ? 0.5f : 0.0f);
		auto p = make_processor(pp);
		REQUIRE(p);
		for (size_t at = 0; at + CAPTURE_BLOCK <= n; at += CAPTURE_BLOCK) {
			p->far_end(far.data() + at);
			float block[CAPTURE_BLOCK];
			for (int i = 0; i < CAPTURE_BLOCK; i++) {
				block[i] = echo[at + i] + talk[at + i];
			}
			p->capture(block);
		}
		erl[k] = p->echo_return_loss_db();
	}
	std::printf("    echo return loss: speakers %.1f dB, headphones %.1f dB\n", erl[0], erl[1]);
	const double warn_below = 20.0; // voice.speaker_warning_erl_db
	CHECK(erl[0] >= 0.0);
	CHECK(erl[0] < warn_below); // speakers: warned
	CHECK((erl[1] < 0.0 || erl[1] >= warn_below)); // headphones: not
}

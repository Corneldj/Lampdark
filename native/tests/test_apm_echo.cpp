// SND-05: the echo cancelling and noise suppression, on synthetic signals. The far end (the game's
// own sound) reaches the microphone through an echo path; with nobody speaking, what comes out must
// be far quieter. Near-end speech over it must survive, and a fan's noise must fall.

#include "doctest.h"

#include <algorithm>
#include <cstdio>

#include "core/voice/voice_processor.h"
#include "voice_signals.h"

using namespace lb::core::voice;
using namespace voice_signals;

namespace {

ProcessorParams params(ApmBackend b, NoiseLevel n = NoiseLevel::MODERATE) {
	ProcessorParams p;
	p.backend = b;
	p.noise = n;
	p.speex_echo_tail_ms = 100.0;
	const double db[4] = {-10.0, -15.0, -22.0, -30.0};
	for (int i = 0; i < 4; i++) {
		p.speex_suppress_db[i] = db[i];
	}
	return p;
}

// Runs `mic` (with `far` as the far end) through a processor; returns the cleaned signal.
std::vector<float> run(VoiceProcessor &p, const std::vector<float> &far, const std::vector<float> &mic) {
	std::vector<float> out(mic.size());
	for (size_t at = 0; at + CAPTURE_BLOCK <= mic.size(); at += CAPTURE_BLOCK) {
		p.far_end(far.data() + at);
		float block[CAPTURE_BLOCK];
		std::copy(mic.begin() + static_cast<long>(at), mic.begin() + static_cast<long>(at + CAPTURE_BLOCK), block);
		p.capture(block);
		std::copy(block, block + CAPTURE_BLOCK, out.begin() + static_cast<long>(at));
	}
	return out;
}

} // namespace

TEST_CASE("SND-05: parse the backend and noise level names") {
	ApmBackend b{};
	CHECK(parse_backend("webrtc", b));
	CHECK(b == ApmBackend::WEBRTC);
	CHECK(parse_backend("speex", b));
	CHECK(parse_backend("none", b));
	CHECK(b == ApmBackend::NONE);
	CHECK_FALSE(parse_backend("rnnoise", b));
	NoiseLevel n{};
	CHECK(parse_noise_level("very_high", n));
	CHECK(n == NoiseLevel::VERY_HIGH);
	CHECK_FALSE(parse_noise_level("max", n));
}

TEST_CASE("SND-05: WebRTC's AEC3 removes the game's own sound from a silent room") {
	const size_t n = 48000 * 12;
	const std::vector<float> far = speechlike(n, 7, 0.3f);
	const std::vector<float> mic = echo_of(far, 48 * 35, 0.5f); // 35 ms away, -6 dB
	auto p = make_processor(params(ApmBackend::WEBRTC));
	REQUIRE(p);
	const std::vector<float> out = run(*p, far, mic);
	const double in_db = energy_db(mic, 48000 * 4, n);
	const double out_db = energy_db(out, 48000 * 4, n);
	std::printf("    webrtc echo: %.1f dB in, %.1f dB out (%.1f dB removed)\n", in_db, out_db, in_db - out_db);
	CHECK(in_db - out_db >= 25.0);
}

TEST_CASE("SND-05: SpeexDSP, the fallback, also removes most of the echo") {
	const size_t n = 48000 * 12;
	const std::vector<float> far = speechlike(n, 7, 0.3f);
	const std::vector<float> mic = echo_of(far, 48 * 35, 0.5f);
	auto p = make_processor(params(ApmBackend::SPEEX));
	REQUIRE(p);
	// SpeexDSP pairs far end and capture through its own playback buffer: a block of render first.
	const std::vector<float> out = run(*p, far, mic);
	const double in_db = energy_db(mic, 48000 * 4, n);
	const double out_db = energy_db(out, 48000 * 4, n);
	std::printf("    speex echo: %.1f dB in, %.1f dB out (%.1f dB removed)\n", in_db, out_db, in_db - out_db);
	CHECK(in_db - out_db >= 12.0);
}

namespace {

// Talking from 6 s, once converged, over the echo: how loud the speaker comes out against their own
// speech alone, after 7 s.
void double_talk(ApmBackend b, double &talk_db, double &out_db) {
	const size_t n = 48000 * 12;
	const std::vector<float> far = speechlike(n, 7, 0.3f);
	const std::vector<float> echo = echo_of(far, 48 * 35, 0.5f);
	const std::vector<float> talk = speechlike(n, 99, 0.2f);
	std::vector<float> mic(n);
	for (size_t i = 0; i < n; i++) {
		mic[i] = echo[i] + (i >= 48000 * 6 ? talk[i] : 0.0f);
	}
	auto p = make_processor(params(b));
	REQUIRE(p);
	const std::vector<float> out = run(*p, far, mic);
	talk_db = energy_db(talk, 48000 * 7, n);
	out_db = energy_db(out, 48000 * 7, n);
}

} // namespace

TEST_CASE("SND-05: near-end speech survives SpeexDSP's echo canceller too (double talk)") {
	double talk_db = 0.0;
	double out_db = 0.0;
	double_talk(ApmBackend::SPEEX, talk_db, out_db);
	std::printf("    speex double talk: speech %.1f dB, out %.1f dB\n", talk_db, out_db);
	CHECK(out_db > talk_db - 10.0);
}

TEST_CASE("SND-05: near-end speech survives the echo canceller (double talk)") {
	const size_t n = 48000 * 12;
	const std::vector<float> far = speechlike(n, 7, 0.3f);
	const std::vector<float> echo = echo_of(far, 48 * 35, 0.5f);
	const std::vector<float> talk = speechlike(n, 99, 0.2f);
	std::vector<float> mic(n);
	for (size_t i = 0; i < n; i++) {
		mic[i] = echo[i] + (i >= 48000 * 6 ? talk[i] : 0.0f); // talking from 6 s, once converged
	}
	auto p = make_processor(params(ApmBackend::WEBRTC));
	REQUIRE(p);
	const std::vector<float> out = run(*p, far, mic);
	const double talk_db = energy_db(talk, 48000 * 7, n);
	const double out_db = energy_db(out, 48000 * 7, n);
	std::printf("    double talk: speech %.1f dB, out %.1f dB\n", talk_db, out_db);
	CHECK(out_db > talk_db - 10.0); // the speaker is still heard, at most 10 dB down
}

TEST_CASE("SND-05: noise suppression lowers a fan, more at higher levels") {
	const size_t n = 48000 * 6;
	const std::vector<float> silence(n, 0.0f);
	const std::vector<float> noise = fan(n, 3, 0.02f);
	double removed[2] = {};
	const NoiseLevel levels[2] = {NoiseLevel::LOW, NoiseLevel::VERY_HIGH};
	for (int k = 0; k < 2; k++) {
		auto p = make_processor(params(ApmBackend::WEBRTC, levels[k]));
		REQUIRE(p);
		const std::vector<float> out = run(*p, silence, noise);
		removed[k] = energy_db(noise, 48000 * 2, n) - energy_db(out, 48000 * 2, n);
	}
	std::printf("    fan removed: low %.1f dB, very high %.1f dB\n", removed[0], removed[1]);
	CHECK(removed[0] >= 4.0);
	CHECK(removed[1] > removed[0]);
}

TEST_CASE("SND-05: backend none passes the microphone through untouched") {
	auto p = make_processor(params(ApmBackend::NONE));
	REQUIRE(p);
	const std::vector<float> mic = speechlike(4800, 1, 0.3f);
	const std::vector<float> out = run(*p, std::vector<float>(4800, 0.5f), mic);
	CHECK(out == mic);
}

TEST_CASE("SND-05: loud game audio echoing at full strength reads silent in 95% of frames (the Deck stand-in)") {
	// The Steam Deck's speakers sit beside its microphone: the far end at full volume (about -12 dBFS
	// RMS) reaching the mic 10 ms later at 0 dB. With nobody speaking, after a 2 s settling, at least
	// 95% of 20 ms frames must stay under the whisper threshold (voice.threshold_whisper_dbfs, -50).
	const double whisper_dbfs = -50.0;
	const size_t n = 48000 * 30;
	std::vector<float> far = speechlike(n, 11, 0.6f);
	const std::vector<float> noise = fan(n, 12, 0.08f);
	for (size_t i = 0; i < n; i++) {
		far[i] += noise[i]; // game sound is more than speech: a steady bed under it
	}
	const std::vector<float> mic = echo_of(far, 48 * 10, 1.0f);
	for (ApmBackend b : {ApmBackend::WEBRTC, ApmBackend::SPEEX}) {
		auto p = make_processor(params(b));
		REQUIRE(p);
		const std::vector<float> out = run(*p, far, mic);
		int frames = 0;
		int silent = 0;
		for (size_t at = 48000 * 2; at + CAPTURE_FRAME <= n; at += CAPTURE_FRAME) {
			frames++;
			silent += energy_db(out, at, at + CAPTURE_FRAME) < whisper_dbfs ? 1 : 0;
		}
		const double share = 100.0 * silent / frames;
		std::printf("    %s, far end %.1f dBFS: %.1f%% of frames under %.0f dBFS\n", b == ApmBackend::WEBRTC ? "webrtc" : "speex",
				energy_db(far, 0, n), share, whisper_dbfs);
		CHECK(share >= 95.0);
	}
}

namespace {

// SND-06's reading (GDD §15.5): each 20 ms frame's level, then the median over 100 ms (5 frames).
std::vector<double> median_levels(const std::vector<float> &x, size_t from) {
	std::vector<double> frames;
	for (size_t at = from; at + CAPTURE_FRAME <= x.size(); at += CAPTURE_FRAME) {
		frames.push_back(energy_db(x, at, at + CAPTURE_FRAME));
	}
	std::vector<double> out;
	for (size_t i = 4; i < frames.size(); i++) {
		std::vector<double> w(frames.begin() + static_cast<long>(i - 4), frames.begin() + static_cast<long>(i + 1));
		std::nth_element(w.begin(), w.begin() + 2, w.end());
		out.push_back(w[2]);
	}
	return out;
}

} // namespace

TEST_CASE("SND-05: a fan and typing at desk level read silent, and a whisper still crosses (synthetic stand-in)") {
	// The criterion asks for recorded clips; until those exist, synthetic ones at desk level: a fan
	// (about -45 dBFS) and typing (clicks peaking near -26 dBFS), against the whisper threshold
	// (voice.threshold_whisper_dbfs, -50) on SND-06's 100 ms median.
	const double whisper_dbfs = -50.0;
	const size_t n = 48000 * 12;
	const std::vector<float> fan_noise = fan(n, 21, 0.007f);
	const std::vector<float> typing = keyboard(n, 22, 0.05f);
	std::vector<float> desk(n);
	for (size_t i = 0; i < n; i++) {
		desk[i] = fan_noise[i] + typing[i];
	}
	const std::vector<float> silence(n, 0.0f);
	auto p = make_processor(params(ApmBackend::WEBRTC));
	REQUIRE(p);
	const std::vector<float> cleaned = run(*p, silence, desk);
	const std::vector<double> levels = median_levels(cleaned, 48000 * 3);
	const double loudest = *std::max_element(levels.begin(), levels.end());
	std::printf("    desk noise: %.1f dBFS raw; cleaned, the loudest 100 ms median is %.1f dBFS\n", energy_db(desk, 0, n), loudest);
	CHECK(loudest < whisper_dbfs);

	// A whisper over the same desk: it must still reach the whisper threshold.
	const std::vector<float> whisper = speechlike(n, 23, 0.025f);
	std::vector<float> talk(n);
	for (size_t i = 0; i < n; i++) {
		talk[i] = desk[i] + whisper[i];
	}
	auto q = make_processor(params(ApmBackend::WEBRTC));
	const std::vector<float> spoken = run(*q, silence, talk);
	const std::vector<double> talk_levels = median_levels(spoken, 48000 * 3);
	const double peak = *std::max_element(talk_levels.begin(), talk_levels.end());
	std::printf("    whisper (%.1f dBFS raw) over the desk: loudest 100 ms median %.1f dBFS\n", energy_db(whisper, 0, n), peak);
	CHECK(peak > whisper_dbfs);
}

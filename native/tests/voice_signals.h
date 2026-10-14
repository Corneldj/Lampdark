#pragma once
// SND-05 tests: deterministic synthetic signals at 48 kHz (no recordings needed): speech-like
// noise (syllable-rate bursts of band-limited noise), a fan's steady hum and hiss, and an echo path.

#include <cmath>
#include <cstdint>
#include <vector>

namespace voice_signals {

struct Lcg {
	uint32_t s;
	explicit Lcg(uint32_t seed) : s(seed) {}
	float next() { // -1..1
		s = s * 1664525u + 1013904223u;
		return static_cast<float>((s >> 8) & 0xFFFF) / 32768.0f - 1.0f;
	}
};

// Band-limited noise in 4-6 Hz syllable bursts, peaking near `level` (linear).
inline std::vector<float> speechlike(size_t n, uint32_t seed, float level) {
	Lcg r(seed);
	std::vector<float> out(n);
	float lp1 = 0.0f, lp2 = 0.0f;
	for (size_t i = 0; i < n; i++) {
		const float w = r.next();
		lp1 += 0.25f * (w - lp1); // a low-pass near 2 kHz
		lp2 += 0.02f * (lp1 - lp2); // and its low part, taken away: a band
		const double t = static_cast<double>(i) / 48000.0;
		const double env = std::fmax(0.0, std::sin(2.0 * 3.14159265358979 * 5.0 * t + 0.7 * std::sin(2.0 * 3.14159265358979 * 0.9 * t)));
		out[i] = static_cast<float>(level * 3.0 * env * (lp1 - lp2));
	}
	return out;
}

// A fan: a 120 Hz hum with harmonics under steady hiss, at `level` (linear RMS-ish).
inline std::vector<float> fan(size_t n, uint32_t seed, float level) {
	Lcg r(seed);
	std::vector<float> out(n);
	for (size_t i = 0; i < n; i++) {
		const double t = static_cast<double>(i) / 48000.0;
		const double hum = std::sin(2.0 * 3.14159265358979 * 120.0 * t) + 0.5 * std::sin(2.0 * 3.14159265358979 * 240.0 * t);
		out[i] = static_cast<float>(level * (0.5 * hum + 0.7 * r.next()));
	}
	return out;
}

// Typing: 5 ms clicks of decaying noise, 6-8 a second, peaking near `level`.
inline std::vector<float> keyboard(size_t n, uint32_t seed, float level) {
	Lcg r(seed);
	std::vector<float> out(n, 0.0f);
	size_t at = 2400;
	while (at < n) {
		for (size_t i = 0; i < 240 && at + i < n; i++) {
			out[at + i] = level * r.next() * std::exp(-static_cast<float>(i) / 50.0f);
		}
		at += 6000 + static_cast<size_t>((r.next() + 1.0f) * 900.0f);
	}
	return out;
}

// The loudspeaker-to-microphone path: a delay, a gain and a little room (two reflections).
inline std::vector<float> echo_of(const std::vector<float> &far, int delay, float gain) {
	std::vector<float> out(far.size(), 0.0f);
	for (size_t i = 0; i < far.size(); i++) {
		const long a = static_cast<long>(i) - delay;
		const long b = a - 240;
		const long c = a - 700;
		float v = 0.0f;
		if (a >= 0)
			v += far[a];
		if (b >= 0)
			v += 0.35f * far[b];
		if (c >= 0)
			v -= 0.2f * far[c];
		out[i] = gain * v;
	}
	return out;
}

inline double energy_db(const std::vector<float> &x, size_t from, size_t to) {
	double e = 0.0;
	for (size_t i = from; i < to; i++) {
		e += static_cast<double>(x[i]) * x[i];
	}
	return 10.0 * std::log10(e / static_cast<double>(to - from) + 1e-20);
}

} // namespace voice_signals

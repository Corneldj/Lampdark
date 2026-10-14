// SND-08: the voice loss model: the distance rule, independent combining, run lengths of 3-10
// frames, the long-run share, determinism by key, and independence between listeners.

#include "doctest.h"

#include <cmath>
#include <vector>

#include "core/voice/voice_loss.h"

using namespace lb::core::voice;

namespace {

LossParams runs() {
	LossParams p;
	p.run_min = 3;
	p.run_max = 10;
	return p;
}

double drop_share(double p, uint32_t listener, size_t frames = 100000) {
	const std::vector<uint8_t> m = mask_for(1234, 7, listener, frames, p, runs());
	size_t dropped = 0;
	for (uint8_t k : m) {
		dropped += k == 0 ? 1 : 0;
	}
	return static_cast<double>(dropped) / static_cast<double>(frames);
}

} // namespace

TEST_CASE("SND-08: talk loses 0% at 6 tiles, 20% at 9 and 40% at 12, over 100,000 frames") {
	const double range = 12.0;
	const double r6 = distance_loss(6.0, range, 0.5, 0.4);
	const double r9 = distance_loss(9.0, range, 0.5, 0.4);
	const double r12 = distance_loss(12.0, range, 0.5, 0.4);
	CHECK(r6 == 0.0);
	CHECK(r9 == doctest::Approx(0.2));
	CHECK(r12 == doctest::Approx(0.4));
	CHECK(drop_share(r6, 1) == 0.0);
	CHECK(std::fabs(drop_share(r9, 2) - 0.20) <= 0.02);
	CHECK(std::fabs(drop_share(r12, 3) - 0.40) <= 0.02);
	CHECK(distance_muffle(9.0, range, 0.5) == doctest::Approx(0.5));
	CHECK(distance_muffle(3.0, range, 0.5) == 0.0);
}

TEST_CASE("SND-08: the edge, a hunting Stythe and a run together keep 36% of frames") {
	const double rates[3] = {0.40, 0.25, 0.20};
	const double p = combine(rates, 3);
	CHECK(1.0 - p == doctest::Approx(0.36));
	CHECK(std::fabs((1.0 - drop_share(p, 4)) - 0.36) <= 0.02);
}

TEST_CASE("SND-08: every dropped run lasts 3-10 frames, except where the utterance ends inside it") {
	for (double p : {0.1, 0.4, 0.64, 0.9}) {
		const std::vector<uint8_t> m = mask_for(99, 3, 5, 50000, p, runs());
		size_t i = 0;
		bool ok = true;
		while (i < m.size()) {
			if (m[i] != 0) {
				i++;
				continue;
			}
			size_t j = i;
			while (j < m.size() && m[j] == 0) {
				j++;
			}
			const size_t run = j - i;
			// Runs never abut (the frame after one is kept), so each is exactly one run.
			if (j < m.size()) {
				ok = ok && run >= 3 && run <= 10;
			}
			i = j;
		}
		CHECK(ok);
	}
	// A single process: each run it starts is 3-10 long.
	LossProcess proc(5, 6, 7, runs());
	int run = 0;
	int shortest = 99, longest = 0;
	for (int f = 0; f < 200000; f++) {
		if (!proc.keep(0.05)) {
			run++;
		} else if (run > 0) {
			shortest = std::min(shortest, run);
			longest = std::max(longest, run);
			run = 0;
		}
	}
	CHECK(shortest >= 3);
	CHECK(longest <= 10);
}

TEST_CASE("SND-08: the same keys give the same masks; two listeners lose independently") {
	CHECK(mask_for(42, 9, 1, 2000, 0.3, runs()) == mask_for(42, 9, 1, 2000, 0.3, runs()));
	CHECK(mask_for(42, 9, 1, 2000, 0.3, runs()) != mask_for(42, 10, 1, 2000, 0.3, runs())); // another utterance
	const std::vector<uint8_t> a = mask_for(42, 9, 1, 100000, 0.4, runs());
	const std::vector<uint8_t> b = mask_for(42, 9, 2, 100000, 0.4, runs());
	CHECK(a != b);
	// Independent: both dropping a frame happens about p x p of the time.
	size_t both = 0;
	for (size_t i = 0; i < a.size(); i++) {
		both += (a[i] == 0 && b[i] == 0) ? 1 : 0;
	}
	CHECK(std::fabs(static_cast<double>(both) / a.size() - 0.16) <= 0.02);
}

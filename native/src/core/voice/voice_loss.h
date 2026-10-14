#pragma once
// SND-08: the simulated voice loss (Gameplay §6.2, GDD §15.5). Rates combine independently (the
// kept share is the product of 1 - each rate), and frames drop in runs of `run_min`-`run_max`, so
// syllables vanish whole: from KEEP each frame starts a run with hazard p / (mean run x (1 - p)),
// capped at 1; a run is never cut short by a change in p, and the frame after it is kept, so runs
// never merge; the long-run drop share is then p (at most mean / (mean + 1), about 87%). Each
// (utterance, listener) has its own process, seeded from the run seed through FND-06's voice.loss
// domain, so a scenario repeats and two listeners lose independently. Loss touches only what a
// listener receives. Engine-free.

#include <cstddef>
#include <cstdint>
#include <vector>

#include "core/rng/rng.h"

namespace lb::core::voice {

struct LossParams {
	int run_min = 3; // voice.loss_run_min_frames
	int run_max = 10; // voice.loss_run_max_frames
};

// Distance: none within `clean_fraction` of the range, then rising linearly to `edge_loss` at it.
double distance_loss(double d, double range, double clean_fraction, double edge_loss);
// How muffled, 0-1, by the same distance.
double distance_muffle(double d, double range, double clean_fraction);
// 1 - product of (1 - r).
double combine(const double *rates, size_t count);

class LossProcess {
public:
	LossProcess(uint64_t run_seed, uint64_t utterance, uint32_t listener, const LossParams &p);
	// The next frame at drop share `p`: true when it is kept (sent), false when dropped.
	bool keep(double p);
	bool in_run() const { return run_left_ > 0; }

private:
	Rng rng_;
	LossParams params_;
	int run_left_ = 0;
	bool after_run_ = false;
};

// A recorded line's mask (SND-11's callouts, CRT-10's illusions): 1 kept, 0 dropped, from the same
// process a live utterance would get.
std::vector<uint8_t> mask_for(uint64_t run_seed, uint64_t utterance, uint32_t listener, size_t frames, double p,
		const LossParams &params);

} // namespace lb::core::voice

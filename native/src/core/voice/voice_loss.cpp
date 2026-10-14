#include "core/voice/voice_loss.h"

#include <algorithm>

#include "core/generated/hash_domains.h"

namespace lb::core::voice {

double distance_loss(double d, double range, double clean_fraction, double edge_loss) {
	if (range <= 0.0) {
		return 0.0;
	}
	return edge_loss * distance_muffle(d, range, clean_fraction);
}

double distance_muffle(double d, double range, double clean_fraction) {
	if (range <= 0.0) {
		return 0.0;
	}
	const double clean = range * clean_fraction;
	const double span = range - clean;
	if (span <= 0.0) {
		return d > clean ? 1.0 : 0.0;
	}
	return std::clamp((d - clean) / span, 0.0, 1.0);
}

double combine(const double *rates, size_t count) {
	double kept = 1.0;
	for (size_t i = 0; i < count; i++) {
		kept *= 1.0 - std::clamp(rates[i], 0.0, 1.0);
	}
	return 1.0 - kept;
}

namespace {

uint64_t seed_for(uint64_t run_seed, uint64_t utterance, uint32_t listener) {
	const int64_t keys[2] = {static_cast<int64_t>(utterance), static_cast<int64_t>(listener)};
	return hash_u64(run_seed, hash_domain::VOICE_LOSS, keys, 2);
}

} // namespace

LossProcess::LossProcess(uint64_t run_seed, uint64_t utterance, uint32_t listener, const LossParams &p) : rng_(seed_for(run_seed, utterance, listener)), params_(p) {}

bool LossProcess::keep(double p) {
	if (run_left_ > 0) {
		run_left_--;
		if (run_left_ == 0) {
			after_run_ = true;
		}
		return false;
	}
	// The frame after a run is always kept: runs never merge into one longer than run_max, and with
	// that gap the hazard below gives a long-run drop share of exactly p.
	if (after_run_) {
		after_run_ = false;
		return true;
	}
	if (p <= 0.0) {
		return true;
	}
	const double mean = 0.5 * (params_.run_min + params_.run_max);
	const double hazard = p >= 1.0 ? 1.0 : std::min(1.0, p / (mean * (1.0 - p)));
	if (rng_.unit_double() >= hazard) {
		return true;
	}
	run_left_ = static_cast<int>(*rng_.range(params_.run_min, params_.run_max)) - 1;
	after_run_ = run_left_ == 0;
	return false;
}

std::vector<uint8_t> mask_for(uint64_t run_seed, uint64_t utterance, uint32_t listener, size_t frames, double p,
		const LossParams &params) {
	LossProcess proc(run_seed, utterance, listener, params);
	std::vector<uint8_t> out(frames);
	for (size_t i = 0; i < frames; i++) {
		out[i] = proc.keep(p) ? 1 : 0;
	}
	return out;
}

} // namespace lb::core::voice

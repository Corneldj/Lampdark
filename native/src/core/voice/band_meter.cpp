#include "core/voice/band_meter.h"

#include <algorithm>
#include <cmath>

namespace lb::core::voice {

namespace {

// RBJ cookbook biquads, Q = 1/sqrt(2) (Butterworth); two in a row make a 4th-order edge.
void design(double rate, double hz, bool high, double &b0, double &b1, double &b2, double &a1, double &a2) {
	const double w = 2.0 * 3.14159265358979323846 * hz / rate;
	const double c = std::cos(w); // determinism: allow (client voice metering, never sim state)
	const double alpha = std::sin(w) / (2.0 * 0.70710678118654752440); // determinism: allow (client voice metering)
	const double a0 = 1.0 + alpha;
	if (high) {
		b0 = (1.0 + c) / 2.0 / a0;
		b1 = -(1.0 + c) / a0;
		b2 = b0;
	} else {
		b0 = (1.0 - c) / 2.0 / a0;
		b1 = (1.0 - c) / a0;
		b2 = b0;
	}
	a1 = -2.0 * c / a0;
	a2 = (1.0 - alpha) / a0;
}

} // namespace

BandMeter::BandMeter(const BandParams &params) : params_(params) {
	params_.median_frames = std::max(1, params_.median_frames);
	params_.hysteresis_frames = std::max(1, params_.hysteresis_frames);
	for (int i = 0; i < 4; i++) {
		Biquad &q = filter_[i];
		design(params_.rate, i < 2 ? params_.low_hz : params_.high_hz, i < 2, q.b0, q.b1, q.b2, q.a1, q.a2);
	}
	history_.assign(params_.median_frames, FLOOR_DBFS);
}

void BandMeter::reset() {
	for (Biquad &q : filter_) {
		q.z1 = 0.0;
		q.z2 = 0.0;
	}
	std::fill(history_.begin(), history_.end(), FLOOR_DBFS);
	filled_ = 0;
	next_ = 0;
	level_ = FLOOR_DBFS;
	median_ = FLOOR_DBFS;
	band_ = 0;
	below_ = 0;
}

int BandMeter::band_for(double dbfs) const {
	int b = 0;
	for (int i = 0; i < 4; i++) {
		if (dbfs >= params_.thresholds_dbfs[i]) {
			b = i + 1;
		}
	}
	return b;
}

int BandMeter::push(const float *samples, size_t count) {
	double sum = 0.0;
	for (size_t i = 0; i < count; i++) {
		double x = samples[i];
		for (Biquad &q : filter_) {
			x = q.run(x);
		}
		sum += x * x;
	}
	const double mean = count > 0 ? sum / static_cast<double>(count) : 0.0;
	level_ = mean > 0.0 ? std::max(FLOOR_DBFS, 10.0 * std::log10(mean)) : FLOOR_DBFS; // determinism: allow (client voice metering)
	history_[next_] = level_;
	next_ = (next_ + 1) % history_.size();
	filled_ = std::min(filled_ + 1, history_.size());
	// Until the window fills, the frames so far (written from slot 0 onward).
	std::vector<double> w(history_.begin(), history_.begin() + static_cast<std::ptrdiff_t>(filled_));
	std::nth_element(w.begin(), w.begin() + static_cast<std::ptrdiff_t>(w.size() / 2), w.end());
	median_ = w[w.size() / 2];
	const int target = band_for(median_);
	if (target > band_) {
		band_ = target; // up at once
		below_ = 0;
	} else if (target < band_) {
		if (++below_ >= params_.hysteresis_frames) {
			band_ = target; // down only after the hysteresis
			below_ = 0;
		}
	} else {
		below_ = 0;
	}
	return band_;
}

} // namespace lb::core::voice

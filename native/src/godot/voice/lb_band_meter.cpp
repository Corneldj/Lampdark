#include "godot/voice/lb_band_meter.h"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;
namespace cv = lb::core::voice;

namespace lb::godot {

namespace {

bool four(const PackedFloat32Array &t, std::array<double, 4> &out) {
	if (t.size() != 4) {
		return false;
	}
	for (int i = 0; i < 4; i++) {
		out[i] = t[i];
	}
	return true;
}

} // namespace

bool LbBandMeter::configure(double low_hz, double high_hz, int64_t median_frames, int64_t hysteresis_frames,
		const PackedFloat32Array &thresholds_dbfs) {
	cv::BandParams p;
	if (!four(thresholds_dbfs, p.thresholds_dbfs)) {
		return false;
	}
	p.low_hz = low_hz;
	p.high_hz = high_hz;
	p.median_frames = static_cast<int>(median_frames);
	p.hysteresis_frames = static_cast<int>(hysteresis_frames);
	meter_ = std::make_unique<cv::BandMeter>(p);
	return true;
}

void LbBandMeter::set_thresholds(const PackedFloat32Array &thresholds_dbfs) {
	std::array<double, 4> t{};
	if (meter_ && four(thresholds_dbfs, t)) {
		meter_->set_thresholds(t);
	}
}

int64_t LbBandMeter::push(const PackedFloat32Array &pcm) {
	return meter_ ? meter_->push(pcm.ptr(), static_cast<size_t>(pcm.size())) : 0;
}

int64_t LbBandMeter::band() const {
	return meter_ ? meter_->band() : 0;
}

double LbBandMeter::level_dbfs() const {
	return meter_ ? meter_->level_dbfs() : cv::BandMeter::FLOOR_DBFS;
}

double LbBandMeter::median_dbfs() const {
	return meter_ ? meter_->median_dbfs() : cv::BandMeter::FLOOR_DBFS;
}

void LbBandMeter::reset() {
	if (meter_) {
		meter_->reset();
	}
}

void LbBandMeter::_bind_methods() {
	ClassDB::bind_method(D_METHOD("configure", "low_hz", "high_hz", "median_frames", "hysteresis_frames", "thresholds_dbfs"),
			&LbBandMeter::configure);
	ClassDB::bind_method(D_METHOD("set_thresholds", "thresholds_dbfs"), &LbBandMeter::set_thresholds);
	ClassDB::bind_method(D_METHOD("push", "pcm"), &LbBandMeter::push);
	ClassDB::bind_method(D_METHOD("band"), &LbBandMeter::band);
	ClassDB::bind_method(D_METHOD("level_dbfs"), &LbBandMeter::level_dbfs);
	ClassDB::bind_method(D_METHOD("median_dbfs"), &LbBandMeter::median_dbfs);
	ClassDB::bind_method(D_METHOD("reset"), &LbBandMeter::reset);
}

} // namespace lb::godot

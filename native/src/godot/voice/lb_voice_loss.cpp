#include "godot/voice/lb_voice_loss.h"

#include "core/voice/voice_loss.h"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;
namespace cv = lb::core::voice;

namespace lb::godot {

double LbVoiceLoss::distance_loss(double d, double range, double clean_fraction, double edge_loss) {
	return cv::distance_loss(d, range, clean_fraction, edge_loss);
}

double LbVoiceLoss::distance_muffle(double d, double range, double clean_fraction) {
	return cv::distance_muffle(d, range, clean_fraction);
}

double LbVoiceLoss::combine(const PackedFloat64Array &rates) {
	return cv::combine(rates.ptr(), static_cast<size_t>(rates.size()));
}

PackedByteArray LbVoiceLoss::mask_for(int64_t run_seed, int64_t utterance, int64_t listener, int64_t frames, double p, int64_t run_min,
		int64_t run_max) {
	cv::LossParams lp;
	lp.run_min = static_cast<int>(run_min);
	lp.run_max = static_cast<int>(run_max);
	const std::vector<uint8_t> m = cv::mask_for(static_cast<uint64_t>(run_seed), static_cast<uint64_t>(utterance),
			static_cast<uint32_t>(listener), static_cast<size_t>(frames < 0 ? 0 : frames), p, lp);
	PackedByteArray out;
	out.resize(static_cast<int64_t>(m.size()));
	std::copy(m.begin(), m.end(), out.ptrw());
	return out;
}

void LbVoiceLoss::_bind_methods() {
	ClassDB::bind_static_method("LbVoiceLoss", D_METHOD("distance_loss", "d", "range", "clean_fraction", "edge_loss"), &LbVoiceLoss::distance_loss);
	ClassDB::bind_static_method("LbVoiceLoss", D_METHOD("distance_muffle", "d", "range", "clean_fraction"), &LbVoiceLoss::distance_muffle);
	ClassDB::bind_static_method("LbVoiceLoss", D_METHOD("combine", "rates"), &LbVoiceLoss::combine);
	ClassDB::bind_static_method("LbVoiceLoss", D_METHOD("mask_for", "run_seed", "utterance", "listener", "frames", "p", "run_min", "run_max"),
			&LbVoiceLoss::mask_for);
}

} // namespace lb::godot

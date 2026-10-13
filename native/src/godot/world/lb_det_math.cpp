#include "godot/world/lb_det_math.h"

#include "core/vision/det_trig.h"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

namespace lb::godot {

void LbDetMath::_bind_methods() {
	ClassDB::bind_static_method("LbDetMath", D_METHOD("unit", "turns"), &LbDetMath::unit);
	ClassDB::bind_static_method("LbDetMath", D_METHOD("cos_deg", "degrees"), &LbDetMath::cos_deg);
}

PackedFloat64Array LbDetMath::unit(double turns) {
	const lb::core::vision::Vec2 v = lb::core::vision::unit_at_turns(turns);
	PackedFloat64Array out;
	out.push_back(v.x);
	out.push_back(v.y);
	return out;
}

double LbDetMath::cos_deg(double degrees) {
	return lb::core::vision::cos_deg(degrees);
}

} // namespace lb::godot

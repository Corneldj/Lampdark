#include "godot/lb_core_info.h"

#include "core/core_info.h"

#include <godot_cpp/core/class_db.hpp>

#ifdef _WIN32
#include <windows.h>
#include <timeapi.h>
#endif

using namespace godot;

namespace lb::godot {

void LbCoreInfo::_bind_methods() {
	ClassDB::bind_static_method("LbCoreInfo", D_METHOD("version"), &LbCoreInfo::version);
	ClassDB::bind_static_method("LbCoreInfo", D_METHOD("build_type"), &LbCoreInfo::build_type);
	ClassDB::bind_static_method("LbCoreInfo", D_METHOD("has_debug_tools"), &LbCoreInfo::has_debug_tools);
	ClassDB::bind_static_method("LbCoreInfo", D_METHOD("add_i64", "a", "b"), &LbCoreInfo::add_i64);
	ClassDB::bind_static_method("LbCoreInfo", D_METHOD("request_timer_resolution_1ms"), &LbCoreInfo::request_timer_resolution_1ms);
}

String LbCoreInfo::version() {
	return String::utf8(lb::core::version_string().c_str());
}

String LbCoreInfo::build_type() {
	return String(lb::core::build_type());
}

bool LbCoreInfo::has_debug_tools() {
	return lb::core::has_debug_tools();
}

int64_t LbCoreInfo::add_i64(int64_t a, int64_t b) {
	return lb::core::add_i64_wrapping(a, b);
}

bool LbCoreInfo::request_timer_resolution_1ms() {
#ifdef _WIN32
	return timeBeginPeriod(1) == TIMERR_NOERROR;
#else
	return true;
#endif
}

} // namespace lb::godot

#include "godot/lb_core_info.h"

#include "core/core_info.h"

#include <godot_cpp/core/class_db.hpp>

#ifdef _WIN32
#include <windows.h>
#include <timeapi.h>
#else
#include <cerrno>
#include <csignal>
#include <sys/types.h>
#endif
#if defined(__GLIBC__)
#include <malloc.h>
#endif

using namespace godot;

namespace lb::godot {

void LbCoreInfo::_bind_methods() {
	ClassDB::bind_static_method("LbCoreInfo", D_METHOD("version"), &LbCoreInfo::version);
	ClassDB::bind_static_method("LbCoreInfo", D_METHOD("build_type"), &LbCoreInfo::build_type);
	ClassDB::bind_static_method("LbCoreInfo", D_METHOD("has_debug_tools"), &LbCoreInfo::has_debug_tools);
	ClassDB::bind_static_method("LbCoreInfo", D_METHOD("add_i64", "a", "b"), &LbCoreInfo::add_i64);
	ClassDB::bind_static_method("LbCoreInfo", D_METHOD("request_timer_resolution_1ms"), &LbCoreInfo::request_timer_resolution_1ms);
	ClassDB::bind_static_method("LbCoreInfo", D_METHOD("process_alive", "pid"), &LbCoreInfo::process_alive);
	ClassDB::bind_static_method("LbCoreInfo", D_METHOD("heap_in_use"), &LbCoreInfo::heap_in_use);
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

bool LbCoreInfo::process_alive(int64_t pid) {
	if (pid <= 0) {
		return false;
	}
#ifdef _WIN32
	HANDLE h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, static_cast<DWORD>(pid));
	if (h == nullptr) {
		return false;
	}
	DWORD code = 0;
	const bool alive = GetExitCodeProcess(h, &code) != 0 && code == STILL_ACTIVE;
	CloseHandle(h);
	return alive;
#else
	return kill(static_cast<pid_t>(pid), 0) == 0 || errno == EPERM;
#endif
}

int64_t LbCoreInfo::heap_in_use() {
#if defined(__GLIBC__)
	const struct mallinfo2 m = mallinfo2();
	return static_cast<int64_t>(m.uordblks + m.hblkhd);
#else
	return -1;
#endif
}

} // namespace lb::godot

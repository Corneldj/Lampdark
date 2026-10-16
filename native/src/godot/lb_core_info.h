#pragma once
// GDScript face of core/core_info.h (FND-02).

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/string.hpp>

namespace lb::godot {

class LbCoreInfo : public ::godot::RefCounted {
	GDCLASS(LbCoreInfo, ::godot::RefCounted)

protected:
	static void _bind_methods();

public:
	static ::godot::String version();
	static ::godot::String build_type();
	static bool has_debug_tools();
	static int64_t add_i64(int64_t a, int64_t b);
	// Asks the OS for 1 ms timer resolution (Windows: timeBeginPeriod); a no-op elsewhere.
	// The headless server calls it so its sleeps to each tick deadline are precise (NET-01).
	static bool request_timer_resolution_1ms();
	// Whether any process with this ID is running (STM-04: a private host's server watches its
	// parent, which Godot's OS.is_process_running cannot: it knows only its own children).
	static bool process_alive(int64_t pid);
	// Bytes the process's allocator has handed out and not taken back (glibc's mallinfo2: arena
	// and mapped chunks), engine and extension alike; -1 where unknown. GEN-11's soak weighs live
	// cells with it: unlike the resident set, it falls when memory is freed.
	static int64_t heap_in_use();
};

} // namespace lb::godot

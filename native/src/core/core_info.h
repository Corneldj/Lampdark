#pragma once
// Engine-free build information (FND-02). Thread-safe: pure functions, no state.

#include <cstdint>
#include <string>

namespace lb::core {

// "<game version>+<git short sha>", e.g. "0.1.0+3f2a9c1".
std::string version_string();

// "debug" or "release".
const char *build_type();

// True when built with LB_DEBUG_TOOLS (template_debug only).
bool has_debug_tools();

// Two's-complement wrapping add: no overflow is undefined, every bit survives.
int64_t add_i64_wrapping(int64_t a, int64_t b);

} // namespace lb::core

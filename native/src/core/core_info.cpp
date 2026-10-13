#include "core/core_info.h"

#include "core/version.gen.h"

namespace lb::core {

std::string version_string() {
	return std::string(LB_VERSION) + "+" + LB_GIT_SHA;
}

const char *build_type() {
#ifdef LB_DEBUG_TOOLS
	return "debug";
#else
	return "release";
#endif
}

bool has_debug_tools() {
#ifdef LB_DEBUG_TOOLS
	return true;
#else
	return false;
#endif
}

int64_t add_i64_wrapping(int64_t a, int64_t b) {
	return static_cast<int64_t>(static_cast<uint64_t>(a) + static_cast<uint64_t>(b));
}

} // namespace lb::core

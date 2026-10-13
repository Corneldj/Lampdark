#include "core/sim/entity_mirror.h"

#include <algorithm>

namespace lb::core::sim {

bool EntityMirror::set(int64_t tick, std::vector<MirrorEntity> entities) {
	uint32_t last = 0;
	for (const MirrorEntity &e : entities) {
		if (e.id <= last) {
			return false;
		}
		last = e.id;
	}
	tick_ = tick;
	entities_ = std::move(entities);
	return true;
}

std::optional<MirrorEntity> EntityMirror::find(uint32_t id) const {
	auto it = std::lower_bound(entities_.begin(), entities_.end(), id,
			[](const MirrorEntity &e, uint32_t wanted) { return e.id < wanted; });
	if (it == entities_.end() || it->id != id) {
		return std::nullopt;
	}
	return *it;
}

EntityMirror &EntityMirror::current() {
	static EntityMirror mirror;
	return mirror;
}

} // namespace lb::core::sim

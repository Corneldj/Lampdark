#include "core/world/entity_id.h"

namespace lb::core::world {

std::optional<EntityId> EntityIdAllocator::allocate() {
	if (next_ > UINT32_MAX) {
		return std::nullopt;
	}
	return static_cast<EntityId>(next_++);
}

} // namespace lb::core::world

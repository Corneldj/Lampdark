#pragma once
// Server entity IDs (FND-07). Issued per run from 1 upwards, never reused within a run;
// 0 means none. NET-01's registry saves next() in snapshots and restores it on resume.
// Server vocabulary only: clients get NET-04's per-client tokens instead.
// Not thread-safe: the simulation thread owns the allocator.

#include <cstdint>
#include <optional>

namespace lb::core::world {

using EntityId = uint32_t;
constexpr EntityId NO_ENTITY = 0;

class EntityIdAllocator {
public:
	// The next ID, or std::nullopt once all 2^32 - 1 IDs of the run are spent.
	std::optional<EntityId> allocate();
	// The counter to save: the ID the next allocate() returns.
	uint64_t next() const { return next_; }
	// Restores a saved counter. Values below 1 are raised to 1, so 0 is never issued.
	void restore(uint64_t next) { next_ = next < 1 ? 1 : next; }

private:
	uint64_t next_ = 1;
};

} // namespace lb::core::world

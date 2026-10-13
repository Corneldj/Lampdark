#pragma once
// The packed per-tick entity mirror (NET-01). The simulation pushes every entity's ID, kind,
// position and flags once per tick, before the light grid; native stages read it instead of
// calling back into GDScript per entity. Entries stay in ascending ID order.
// Not thread-safe: written and read on the simulation thread.

#include <cstdint>
#include <optional>
#include <vector>

namespace lb::core::sim {

struct MirrorEntity {
	uint32_t id = 0;
	uint16_t kind = 0;
	double x = 0.0;
	double y = 0.0;
	uint32_t flags = 0;
	bool operator==(const MirrorEntity &o) const {
		return id == o.id && kind == o.kind && x == o.x && y == o.y && flags == o.flags;
	}
};

class EntityMirror {
public:
	// Replaces the contents. Rejects (and keeps the old contents) unless IDs are ascending,
	// non-zero and unique.
	bool set(int64_t tick, std::vector<MirrorEntity> entities);

	int64_t tick() const { return tick_; }
	size_t size() const { return entities_.size(); }
	const std::vector<MirrorEntity> &entities() const { return entities_; }
	std::optional<MirrorEntity> find(uint32_t id) const;

	static EntityMirror &current();

private:
	int64_t tick_ = -1;
	std::vector<MirrorEntity> entities_;
};

} // namespace lb::core::sim

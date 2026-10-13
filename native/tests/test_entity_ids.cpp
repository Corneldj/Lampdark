#include "core/world/entity_id.h"

#include <doctest.h>

#include <set>

using namespace lb::core::world;

TEST_CASE("entity IDs start at 1, rise monotonically and are never reused") {
	EntityIdAllocator ids;
	std::set<EntityId> seen;
	EntityId last = NO_ENTITY;
	for (int i = 0; i < 1000; i++) {
		const EntityId id = *ids.allocate();
		CHECK(id != NO_ENTITY);
		CHECK(id > last);
		CHECK(seen.insert(id).second);
		last = id;
	}
	CHECK(ids.next() == 1001);
}

TEST_CASE("the counter restores from a saved value") {
	EntityIdAllocator ids;
	for (int i = 0; i < 5; i++) {
		ids.allocate();
	}
	const uint64_t saved = ids.next();
	EntityIdAllocator resumed;
	resumed.restore(saved);
	CHECK(*resumed.allocate() == 6);
	EntityIdAllocator zero;
	zero.restore(0);
	CHECK(*zero.allocate() == 1); // never 0
}

TEST_CASE("the allocator stops at 2^32 - 1 rather than wrapping to 0") {
	EntityIdAllocator ids;
	ids.restore(UINT32_MAX);
	CHECK(*ids.allocate() == UINT32_MAX);
	CHECK_FALSE(ids.allocate().has_value());
}

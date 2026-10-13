#pragma once
// VIS-03's perception classes, keyed by FND-07's entity kinds (data/world/perception_classes.json):
// each kind's size class, footprint and identity threshold. Miner-sized and large things arrive
// as anonymous shape tokens in the fringe; small things need the small-thing threshold and are
// never tokens; NONE kinds are never perceived as entities (gates and doors are geometry).

#include <array>
#include <cstdint>

namespace lb::core::vision {

// Token classes, as NET-04 sends them. LARGE_MOTIONLESS is shared by a heap of coats and a
// sleeping Moth, so the two are byte-identical.
enum class SizeClass : uint8_t { NONE = 0, MINER = 1, LARGE = 2, LARGE_MOTIONLESS = 3, SMALL = 4 };

struct PerceptionClass {
	SizeClass size = SizeClass::NONE;
	// Side of the square footprint in tiles; a large entity takes the brightest tile under it.
	int64_t footprint = 1;
	// Light in thousandths for identity; -1 means the table default.
	int64_t identity_min = -1;
	// A large kind that is motionless whenever the motionless flag is set (the sleeping Moth),
	// or always (the heap of coats).
	bool motionless_always = false;
};

class PerceptionTable {
public:
	static constexpr size_t MAX_KINDS = 64;

	void set(uint16_t kind, PerceptionClass c) {
		if (kind < MAX_KINDS) {
			classes_[kind] = c;
		}
	}
	PerceptionClass get(uint16_t kind) const { return kind < MAX_KINDS ? classes_[kind] : PerceptionClass{}; }

	// The token class of an entity of this kind with these flags.
	SizeClass token_class(uint16_t kind, uint32_t flags) const {
		const PerceptionClass c = get(kind);
		if (c.size == SizeClass::LARGE && (c.motionless_always || (flags & motionless_flag) != 0)) {
			return SizeClass::LARGE_MOTIONLESS;
		}
		return c.size;
	}

	uint32_t motionless_flag = 1;

private:
	std::array<PerceptionClass, MAX_KINDS> classes_{};
};

} // namespace lb::core::vision

#pragma once
// A miner's line of sight (VIS-03): symmetric shadowcasting (VIS-02's) from the miner's tile
// centre, stored as a bitset over an (2R+1)² window, R = the range in tiles. Tiles further than R
// by centre distance are never in it. The field is recast only when the miner changes tile or
// GEN-01 reports a change inside the window (a gate, an air door, a collapse).

#include "core/world/coords.h"

#include <cstdint>
#include <functional>
#include <vector>

namespace lb::core::vision {

using lb::core::world::Coord;

class LosField {
public:
	void cast(Coord origin, int64_t range, const std::function<bool(Coord)> &blocks);

	bool visible(Coord tile) const;
	bool valid() const { return valid_; }
	Coord origin() const { return origin_; }
	int64_t range() const { return range_; }
	size_t count() const { return count_; }
	void invalidate() { valid_ = false; }

	// True if a changed rectangle (inclusive) touches the window.
	bool touches(int64_t x0, int64_t y0, int64_t x1, int64_t y1) const;

	// Calls visit(tile) for every visible tile, in row-major window order.
	void for_each(const std::function<void(Coord)> &visit) const;

private:
	Coord origin_{0, 0};
	int64_t range_ = 0;
	int64_t side_ = 0;
	bool valid_ = false;
	size_t count_ = 0;
	std::vector<uint64_t> bits_;
};

} // namespace lb::core::vision

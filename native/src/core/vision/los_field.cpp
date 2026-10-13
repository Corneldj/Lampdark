#include "core/vision/los_field.h"

#include "core/light/shadowcast.h"

namespace lb::core::vision {

void LosField::cast(Coord origin, int64_t range, const std::function<bool(Coord)> &blocks) {
	origin_ = origin;
	range_ = range;
	side_ = 2 * range + 1;
	bits_.assign(static_cast<size_t>((side_ * side_ + 63) / 64), 0);
	count_ = 0;
	const int64_t r2 = range * range;
	lb::core::light::shadowcast(origin, range, blocks, [&](Coord t) {
		const int64_t dx = t.x - origin.x;
		const int64_t dy = t.y - origin.y;
		if (dx * dx + dy * dy > r2) {
			return;
		}
		const int64_t i = (dy + range) * side_ + (dx + range);
		uint64_t &word = bits_[static_cast<size_t>(i / 64)];
		const uint64_t bit = uint64_t{1} << (i % 64);
		if ((word & bit) == 0) {
			word |= bit;
			count_++;
		}
	});
	valid_ = true;
}

bool LosField::visible(Coord tile) const {
	if (!valid_) {
		return false;
	}
	const int64_t dx = tile.x - origin_.x;
	const int64_t dy = tile.y - origin_.y;
	if (dx < -range_ || dx > range_ || dy < -range_ || dy > range_) {
		return false;
	}
	const int64_t i = (dy + range_) * side_ + (dx + range_);
	return (bits_[static_cast<size_t>(i / 64)] >> (i % 64)) & 1u;
}

bool LosField::touches(int64_t x0, int64_t y0, int64_t x1, int64_t y1) const {
	return !(x1 < origin_.x - range_ || x0 > origin_.x + range_ || y1 < origin_.y - range_ || y0 > origin_.y + range_);
}

void LosField::for_each(const std::function<void(Coord)> &visit) const {
	if (!valid_) {
		return;
	}
	for (int64_t i = 0; i < side_ * side_; i++) {
		if ((bits_[static_cast<size_t>(i / 64)] >> (i % 64)) & 1u) {
			visit(Coord{origin_.x - range_ + i % side_, origin_.y - range_ + i / side_});
		}
	}
}

} // namespace lb::core::vision

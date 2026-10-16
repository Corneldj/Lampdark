// GEN-05: a seed's 400 nearest cells give the same layouts in any order, with caches on and off,
// and after eviction and re-derivation (50 seeds here; GEN-14 runs 10,000).

#include "core/rng/rng.h"
#include "layout_fixture.h"

#include <doctest.h>

#include <algorithm>
#include <map>

using namespace layout_fixture;

namespace {

// The 400 cells nearest (0, 0), by distance, then by coordinates.
std::vector<Coord> nearest_400() {
	std::vector<Coord> cells;
	for (int64_t y = -12; y <= 12; y++) {
		for (int64_t x = -12; x <= 12; x++) {
			cells.push_back({x, y});
		}
	}
	std::sort(cells.begin(), cells.end(), [](const Coord &a, const Coord &b) {
		const int64_t da = a.x * a.x + a.y * a.y;
		const int64_t db = b.x * b.x + b.y * b.y;
		return da != db ? da < db : a < b;
	});
	cells.resize(400);
	return cells;
}

std::map<Coord, uint64_t> digests(const Deriver &d, const std::vector<Coord> &order) {
	std::map<Coord, uint64_t> out;
	for (const Coord &c : order) {
		const std::optional<Layout> l = d.derive(c, 0);
		REQUIRE(l.has_value());
		out[c] = l->digest;
	}
	return out;
}

} // namespace

TEST_CASE("GEN-05 layouts are the same in any order, cached or not, and after eviction (50 seeds)") {
	auto set = template_set();
	const std::vector<Coord> cells = nearest_400();
	lb::core::Rng rng(2026);
	for (uint64_t s = 0; s < 50; s++) {
		Run r = run(rng.next_u64(), set);
		Deriver small_cache(r.inputs(), 64, 256); // evicts constantly
		const std::map<Coord, uint64_t> first = digests(small_cache, cells);
		for (int order = 0; order < 3; order++) {
			std::vector<Coord> shuffled = cells;
			rng.shuffle(shuffled);
			Deriver d(r.inputs());
			CHECK(digests(d, shuffled) == first);
			d.set_caching(false);
			CHECK(digests(d, shuffled) == first);
		}
		small_cache.clear_caches(); // evict everything, then derive again
		std::vector<Coord> reversed(cells.rbegin(), cells.rend());
		CHECK(digests(small_cache, reversed) == first);
	}
}

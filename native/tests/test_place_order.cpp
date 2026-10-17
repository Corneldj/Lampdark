// GEN-10 extends GEN-05's order test: over real derived layouts (GEN-05's fixture set), a cell's
// placements are the same in any generation order, cached or not, and after the caches clear.

#include "core/gen/biomes.h"
#include "core/gen/placement.h"
#include "layout_fixture.h"

#include <doctest.h>

#include <algorithm>
#include <map>

using namespace layout_fixture;
using lb::core::world::Coord;

namespace {

class DeriverWorld final : public PlacementWorld {
public:
	explicit DeriverWorld(const Deriver &d, const RunHeader &h) : d_(d), h_(h) {}
	const RunHeader &header() const override { return h_; }
	std::optional<Layout> layout(Coord c) const override { return d_.derive(c, 0); }
	CellFacts facts(Coord c) const override {
		CellFacts f;
		f.base_camp = c == Coord{0, 0};
		f.ring = ring_of_cell(c, bounds_);
		f.biome = (c.x + c.y) % 2 == 0 ? "seam" : "old_workings";
		return f;
	}
	const std::vector<int64_t> &ring_bounds() const override { return bounds_; }

private:
	const Deriver &d_;
	const RunHeader &h_;
	std::vector<int64_t> bounds_{20, 60, 120, 200};
};

std::map<Coord, uint64_t> digests(const PlacementWorld &w, const PlacementParams &p, const std::vector<Coord> &order) {
	std::map<Coord, uint64_t> out;
	for (const Coord &c : order) {
		out[c] = placement_digest(place_cell(w, p, c));
	}
	return out;
}

} // namespace

TEST_CASE("GEN-10 placements are the same in any generation order (30 seeds)") {
	const PlacementParams p;
	std::vector<Coord> cells;
	for (int64_t y = -5; y <= 5; y++) {
		for (int64_t x = -5; x <= 5; x++) {
			cells.push_back({x, y});
		}
	}
	int64_t placed = 0;
	for (uint64_t s = 0; s < 30; s++) {
		Run r = run(lb::core::mix64(s + 0x0D0E), template_set());
		Deriver d(r.inputs(), 16);
		const DeriverWorld w(d, r.head);
		const std::map<Coord, uint64_t> base = digests(w, p, cells);
		for (const auto &[c, dg] : base) {
			placed += place_cell(w, p, c).size();
		}
		for (int k = 0; k < 3; k++) {
			std::vector<Coord> order = cells;
			lb::core::Rng rng(s * 7 + static_cast<uint64_t>(k));
			rng.shuffle(order);
			d.set_caching(k != 1);
			CHECK(digests(w, p, order) == base);
		}
		d.clear_caches();
		std::vector<Coord> reversed(cells.rbegin(), cells.rend());
		CHECK(digests(w, p, reversed) == base);
	}
	CHECK(placed > 1000);
}

#pragma once
// GEN-10's fixtures: a cell carrying every anchor placement reads (GEN-04's base cell plus item,
// trap and low-road anchors and a high chamber), and a synthetic world that puts it at every
// cell with a class by rule (ring by distance, a biome, main roads, spines, a hoard), so density
// runs over many seeds need no derive: placement reads only anchors, tiles, sockets and collapses.

#include "core/gen/biomes.h"
#include "core/gen/placement.h"
#include "layout_fixture.h"
#include "template_fixture.h"

#include <functional>

namespace place_fixture {

using namespace template_fixture;
using lb::core::world::Coord;

// GEN-04's base anchors with the remains moved off the gas dead end (so remains never meet
// blackdamp here), two item anchors, two trap sites, a low road on the north road and the chamber
// tagged high.
inline std::vector<Anchor> place_anchors() {
	std::vector<Anchor> a = base_anchors();
	for (Anchor &x : a) {
		if (x.type == AnchorType::CHAMBER) {
			x.tags = {"high"};
		}
		if (x.type == AnchorType::REMAINS) {
			x.x = 2;
			x.y = 11;
		}
	}
	a.push_back(anchor(AnchorType::ITEM, 3, 10));
	a.push_back(anchor(AnchorType::ITEM, 16, 10));
	a.push_back(anchor(AnchorType::TRAP_SITE, 6, 10));
	a.push_back(anchor(AnchorType::TRAP_SITE, 13, 9));
	a.push_back(anchor(AnchorType::LOW_ROAD, 10, 0, 1, 4));
	return a;
}

inline Layout prototype() {
	Spec s;
	s.anchors = place_anchors();
	Layout l;
	l.template_id = s.id;
	l.cell = cell_of(s);
	for (int e = 0; e < 4; e++) {
		Socket so;
		so.open = static_cast<Edge>(e) != Edge::SOUTH;
		so.offset = 10;
		so.width = so.open ? 3 : 0;
		l.sockets[static_cast<size_t>(e)] = so;
	}
	return l;
}

// The planned hoard at `cell` (one cell).
inline void plan_hoard(RunHeader &h, Coord cell) {
	PlannedSite s;
	s.kind = PoiKind::HOARD;
	s.need = "hoard";
	s.door = cell;
	s.cells = {cell};
	h.plan.sites.push_back(s);
}

class World final : public PlacementWorld {
public:
	RunHeader head;
	std::vector<int64_t> bounds{80, 200, 400, 700};
	Layout proto = prototype();
	std::function<std::string(Coord)> biome = [](Coord) { return std::string("seam"); };
	std::function<bool(Coord)> main_road = [](Coord) { return false; };
	std::function<bool(Coord)> spine = [](Coord) { return false; };

	const RunHeader &header() const override { return head; }
	std::optional<Layout> layout(Coord c) const override {
		Layout l = proto;
		l.coord = c;
		l.cell.coord = c;
		l.base_camp = c == Coord{0, 0};
		return l;
	}
	CellFacts facts(Coord c) const override {
		CellFacts f;
		f.base_camp = c == Coord{0, 0};
		f.ring = ring_of_cell(c, bounds);
		f.biome = biome(c);
		f.main_road = main_road(c);
		f.spine = spine(c);
		return f;
	}
	const std::vector<int64_t> &ring_bounds() const override { return bounds; }
};

// A world for `seed`: GEN-05's base camp sockets, a biome by a hash of the cell (seam 40%, Old
// Workings 40%, Black Seam 20%), main roads along y = 0 and x = 0, a hoard at (8, 0), and the
// homes pass run.
inline void reset(World &w, uint64_t seed, const PlacementParams &p = PlacementParams()) {
	w.head = layout_fixture::header(seed);
	plan_hoard(w.head, {8, 0});
	w.biome = [seed](Coord c) {
		const int64_t keys[2] = {c.x, c.y};
		const uint64_t v = lb::core::hash_u64(seed ^ 0xB10Eull, 7, keys, 2) % 10u;
		return std::string(v < 4 ? "seam" : (v < 8 ? "old_workings" : "black_seam"));
	};
	w.main_road = [](Coord c) { return c.y == 0 || c.x == 0; };
	write_homes(make_homes(w, p), w.head);
}

inline std::vector<Placement> of_kind(const std::vector<Placement> &list, PlacedKind kind) {
	std::vector<Placement> out;
	for (const Placement &x : list) {
		if (x.kind == kind) {
			out.push_back(x);
		}
	}
	return out;
}

inline int64_t count(const std::vector<Placement> &list, PlacedKind kind, const std::string &thing = "") {
	int64_t n = 0;
	for (const Placement &x : list) {
		if (x.kind == kind && (thing.empty() || x.thing == thing)) {
			n++;
		}
	}
	return n;
}

} // namespace place_fixture

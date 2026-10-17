// HAZ-01's man-traps on the lair's approaches (Gameplay §8.1, §8.2, §10.10), over a world of grid
// cells (3-wide roads on every stub line, a trap site on each road crossing's arms): 4-8 a run, each
// 30-70 tiles by path from the lair's door, half of them (rounded up) within the 50-tile territory,
// at least 6 tiles apart by path; never on a door site, nor below a staged run 1's ring; placed in
// their cells on their trap sites, those cells rolling no other; through the header's homes and back.

#include "place_fixture.h"

#include <doctest.h>

#include <deque>
#include <map>
#include <set>

using namespace place_fixture;

namespace {

// The grid fallback with trap sites on its roads' arms, a door site over one of them.
Layout grid_prototype() {
	Spec s = fallback_spec();
	s.kind = TemplateKind::BIOME_CELL;
	for (int a : {5, 10, 15}) {
		s.anchors.push_back(anchor(AnchorType::TRAP_SITE, a, 2));
		s.anchors.push_back(anchor(AnchorType::TRAP_SITE, 2, a));
	}
	s.anchors.push_back(anchor(AnchorType::DOOR_SITE, 9, 2, 3, 1));
	Layout l;
	l.template_id = s.id;
	l.cell = cell_of(s);
	for (int e = 0; e < 4; e++) {
		Socket so;
		so.open = true;
		so.offset = 10;
		so.width = 3;
		l.sockets[static_cast<size_t>(e)] = so;
	}
	return l;
}

// The planned lair at `door` (one cell), its door on its west edge.
void plan_lair(RunHeader &h, Coord door) {
	PlannedSite s;
	s.kind = PoiKind::LAIR;
	s.need = "lair";
	s.door = door;
	s.door_side = Edge::WEST;
	s.cells = {door};
	h.plan.sites.push_back(s);
}

const Coord LAIR{12, 3};

void reset_grid(World &w, uint64_t seed, const PlacementParams &p, const std::string &staging = "") {
	w.head = layout_fixture::header(seed);
	w.head.staging = staging;
	w.proto = grid_prototype();
	plan_lair(w.head, LAIR);
	write_homes(make_homes(w, p), w.head);
}

bool floor_at(const World &w, Coord t) {
	const Coord c = lb::core::world::cell_of(t);
	if (c == LAIR || c == Coord{0, 0}) {
		return false;
	}
	const std::optional<Layout> l = w.layout(c);
	const Coord local = lb::core::world::local_of(t);
	return l && l->cell.tiles[static_cast<size_t>(lb::core::world::Cell::index_of(local.x, local.y))].material == static_cast<uint8_t>(lb::core::world::TileMaterial::FLOOR);
}

// Tiles by path from `from` (4-connected, the lair left out), up to `limit`.
std::map<Coord, int64_t> flood(const World &w, Coord from, int64_t limit) {
	std::map<Coord, int64_t> dist{{from, 0}};
	std::deque<Coord> queue{from};
	while (!queue.empty()) {
		const Coord t = queue.front();
		queue.pop_front();
		if (dist[t] >= limit) {
			continue;
		}
		for (const Coord step : {Coord{1, 0}, Coord{-1, 0}, Coord{0, 1}, Coord{0, -1}}) {
			const Coord n{t.x + step.x, t.y + step.y};
			if (floor_at(w, n) && !dist.count(n)) {
				dist[n] = dist[t] + 1;
				queue.push_back(n);
			}
		}
	}
	return dist;
}

} // namespace

TEST_CASE("HAZ-01 approach traps: 4-8 in the band, half within the territory, spaced by path") {
	const PlacementParams p;
	World w;
	std::set<int64_t> sizes;
	for (int64_t s = 0; s < 300; s++) {
		reset_grid(w, lb::core::mix64(static_cast<uint64_t>(s) * 7 + 0x4A01), p);
		const std::vector<ApproachTrap> traps = approach_traps(w, p);
		REQUIRE(traps.size() >= 4);
		REQUIRE(traps.size() <= 8);
		sizes.insert(static_cast<int64_t>(traps.size()));
		int64_t inside = 0;
		for (const ApproachTrap &t : traps) {
			CHECK(t.path >= 30);
			CHECK(t.path <= 70);
			inside += t.path <= 50 ? 1 : 0;
			// On a trap site, never the one under the door site (local (10, 2)).
			const Coord local = lb::core::world::local_of(t.tile);
			CHECK(((local.y == 2 && (local.x == 5 || local.x == 15)) || (local.x == 2 && (local.y == 5 || local.y == 10 || local.y == 15))));
		}
		CHECK(inside == (static_cast<int64_t>(traps.size()) + 1) / 2);
		for (size_t i = 0; i < traps.size(); i++) {
			const std::map<Coord, int64_t> near = flood(w, traps[i].tile, 5);
			for (size_t j = 0; j < traps.size(); j++) {
				if (i != j) {
					CHECK_FALSE(near.count(traps[j].tile));
				}
			}
		}
		// The same answer twice, and through the header's homes.
		CHECK(approach_traps(w, p) == traps);
		CHECK(read_homes(w.head).lair_traps == traps);
	}
	CHECK(sizes == std::set<int64_t>{4, 5, 6, 7, 8});
}

TEST_CASE("HAZ-01 approach traps: their path is the flood's from the lair's door") {
	const PlacementParams p;
	World w;
	reset_grid(w, 0x4A02, p);
	// The door's floor: the lair cell's west edge on the three road rows, one step out of it.
	std::map<Coord, int64_t> best;
	for (int64_t row : {4, 5, 6, 9, 10, 11, 14, 15, 16}) {
		const Coord out{LAIR.x * lb::core::world::CELL_TILES - 1, LAIR.y * lb::core::world::CELL_TILES + row};
		for (const auto &[t, d] : flood(w, out, 70)) {
			const auto it = best.find(t);
			if (it == best.end() || d + 1 < it->second) {
				best[t] = d + 1;
			}
		}
	}
	for (const ApproachTrap &t : approach_traps(w, p)) {
		REQUIRE(best.count(t.tile));
		CHECK(best[t.tile] == t.path);
	}
}

TEST_CASE("HAZ-01 approach traps lie in their cells, which roll no other man-trap") {
	PlacementParams p;
	p.man_trap_ppm = 1000000; // every other cell of ring 2 and deeper would hold one
	World w;
	for (int64_t s = 0; s < 40; s++) {
		reset_grid(w, lb::core::mix64(static_cast<uint64_t>(s) + 0x4A03), p);
		const Homes h = read_homes(w.head);
		REQUIRE_FALSE(h.lair_traps.empty());
		std::map<Coord, std::set<Coord>> by_cell;
		for (const ApproachTrap &t : h.lair_traps) {
			by_cell[lb::core::world::cell_of(t.tile)].insert(t.tile);
		}
		for (const auto &[cell, tiles] : by_cell) {
			std::set<Coord> placed;
			for (const Placement &x : of_kind(place_cell(w, p, cell), PlacedKind::MAN_TRAP)) {
				placed.insert(x.tile);
				CHECK(x.source == "trap");
				CHECK(x.anchor >= 0);
			}
			CHECK(placed == tiles);
		}
	}
}

TEST_CASE("HAZ-01 approach traps: a staged run 1 has none below ring 2, and no lair none") {
	const PlacementParams p;
	World w;
	for (int64_t s = 0; s < 60; s++) {
		reset_grid(w, lb::core::mix64(static_cast<uint64_t>(s) + 0x4A04), p, "1");
		for (const ApproachTrap &t : approach_traps(w, p)) {
			CHECK(w.facts(lb::core::world::cell_of(t.tile)).ring >= 2);
		}
	}
	reset_grid(w, 0x4A05, p);
	w.head.plan.sites.clear();
	CHECK(approach_traps(w, p).empty());
}

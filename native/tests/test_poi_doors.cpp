// GEN-09: over 200 seeds, every templated point of interest's door socket is open and forced at
// its door stub's offset, and the floor of the door cell and of the cell beyond (derived as GEN-05
// derives) meets across the opening; each of its other outer edges is shut but where a stub rolled
// open at that stub; the lair joins exactly one socket; each planned door faces its spine's last
// cell; an edge inside one point of interest is no socket, and the template's own floor crosses it;
// its cells report its template's biome, the lair's always Old Workings. Region layouts and derived
// cells are the same whichever cell comes first, cached or not (100 seeds).

#include "poi_fixture.h"

#include <doctest.h>

#include <algorithm>

using namespace poi_fixture;
using lb::core::world::Cell;
using lb::core::world::TileMaterial;

namespace {

// The tile `k` along a cell's `side` edge (from its west or north end).
Coord edge_tile(Edge side, int64_t k) {
	switch (side) {
		case Edge::NORTH: return Coord{k, 0};
		case Edge::SOUTH: return Coord{k, CELL_TILES - 1};
		case Edge::WEST: return Coord{0, k};
		default: return Coord{CELL_TILES - 1, k};
	}
}

bool floor_at(const Cell &cell, Coord t) {
	return cell.tiles[static_cast<size_t>(Cell::index_of(t.x, t.y))].material == static_cast<uint8_t>(TileMaterial::FLOOR);
}

// The point of interest's outer edges: each of its cells' sides that leave the footprint.
std::vector<std::pair<Coord, Edge>> outer_edges(const Poi &p) {
	std::vector<std::pair<Coord, Edge>> out;
	for (const Coord &c : p.cells()) {
		for (int e = 0; e < 4; e++) {
			if (!p.contains(neighbour(c, static_cast<Edge>(e)))) {
				out.push_back({c, static_cast<Edge>(e)});
			}
		}
	}
	return out;
}

} // namespace

TEST_CASE("GEN-09 every door is open and the floor beyond meets it") {
	int64_t doors = 0;
	int64_t lairs = 0;
	int64_t inner = 0;
	int64_t opened = 0;
	for (uint64_t s = 0; s < 200; s++) {
		const auto r = run(lb::core::mix64(s * 5 + 0xD0025), static_cast<int32_t>(s % 3));
		const auto d = derive_inputs(*r);
		const Deriver deriver(d->in);
		for (const Coord &region : regions()) {
			for (const Poi &p : r->pois->region(region)->pois) {
				if (p.shape == nullptr) {
					continue;
				}
				const Coord local{p.door.x - p.origin.x, p.door.y - p.origin.y};
				const Stub *door = nullptr;
				for (const Stub &st : p.shape->oriented.stubs) {
					if (st.door && st.cell == local && st.edge == p.door_side) {
						door = &st;
					}
				}
				REQUIRE(door != nullptr);
				const Socket sock = deriver.socket(edge_of(p.door, p.door_side));
				CHECK(sock.open);
				CHECK(sock.forced);
				CHECK(sock.offset == door->offset);
				CHECK(sock.width <= door->max_width);
				const std::optional<Layout> in = deriver.derive(p.door, 0);
				const std::optional<Layout> out = deriver.derive(p.approach(), 0);
				REQUIRE(in.has_value());
				REQUIRE(out.has_value());
				CHECK(in->template_id == p.shape->oriented.id);
				const int32_t first = opening_first(sock.offset, sock.width);
				for (int32_t k = first; k < first + sock.width; k++) {
					CHECK(floor_at(in->cell, edge_tile(p.door_side, k)));
					CHECK(floor_at(out->cell, edge_tile(opposite(p.door_side), k)));
				}
				doors++;
				// Its other outer edges: shut, or open at one of its stubs there.
				int32_t open = 0;
				for (const auto &[c, side] : outer_edges(p)) {
					const Socket e = deriver.socket(edge_of(c, side));
					CHECK(e.forced);
					if (!e.open) {
						continue;
					}
					open++;
					bool stub = false;
					for (const Stub &st : p.shape->oriented.stubs) {
						stub = stub || (st.cell == Coord{c.x - p.origin.x, c.y - p.origin.y} && st.edge == side && st.offset == e.offset);
					}
					CHECK(stub);
				}
				opened += open - 1;
				if (p.kind == PoiKind::LAIR) {
					lairs++;
					CHECK(open == 1);
				}
				// Edges inside it are no socket, and its own floor crosses them.
				for (const Coord &c : p.cells()) {
					for (Edge side : {Edge::EAST, Edge::SOUTH}) {
						const Coord n = neighbour(c, side);
						if (!p.contains(n)) {
							continue;
						}
						inner++;
						const Socket e = deriver.socket(edge_of(c, side));
						CHECK_FALSE(e.open);
						CHECK(e.forced);
						const std::optional<Layout> a = deriver.derive(c, 0);
						const std::optional<Layout> b = deriver.derive(n, 0);
						REQUIRE(a.has_value());
						REQUIRE(b.has_value());
						bool crosses = false;
						for (int64_t k = 0; k < CELL_TILES; k++) {
							crosses = crosses || (floor_at(a->cell, edge_tile(side, k)) && floor_at(b->cell, edge_tile(opposite(side), k)));
						}
						CHECK(crosses);
					}
				}
				// Its cells take its template's biome; the lair's is Old Workings.
				for (const Coord &c : p.cells()) {
					const CellClass cls = d->in.cells->classify(c);
					CHECK(cls.kind == TemplateKind::POI);
					CHECK(cls.biome == (p.kind == PoiKind::LAIR ? std::string("old_workings") : std::string("seam")));
				}
			}
		}
	}
	MESSAGE(doors, " doors, ", lairs, " lairs, ", inner, " inner edges, ", opened, " other stubs rolled open");
	CHECK(doors > 1000);
	CHECK(lairs > 50);
	CHECK(inner > 100);
	CHECK(opened > 100);
}

TEST_CASE("GEN-09 each planned door faces its spine's last cell") {
	int64_t checked = 0;
	for (uint64_t s = 0; s < 300; s++) {
		const auto r = run(lb::core::mix64(s * 11 + 0xD0026), static_cast<int32_t>(s % 3));
		const RunPlan &plan = r->head.plan;
		for (const Spine &spine : plan.spines) {
			const PlannedSite &site = plan.sites[static_cast<size_t>(spine.site)];
			const PoiRef p = r->pois->at(site.door);
			REQUIRE(p);
			CHECK(p->planned == spine.site);
			REQUIRE(p->shape != nullptr);
			CHECK(p->door == site.door);
			CHECK(p->door_side == site.door_side);
			CHECK(p->approach() == spine.cells.back());
			std::vector<Coord> a = p->cells();
			std::vector<Coord> b = site.cells;
			std::sort(a.begin(), a.end());
			std::sort(b.begin(), b.end());
			CHECK(a == b);
			checked++;
		}
	}
	CHECK(checked > 3000);
}

TEST_CASE("GEN-09 region layouts are the same whichever cell comes first, cached or not") {
	for (uint64_t s = 0; s < 100; s++) {
		const uint64_t seed = lb::core::mix64(s + 0xD0027);
		const auto a = run(seed, static_cast<int32_t>(s % 3));
		const auto b = run(seed, static_cast<int32_t>(s % 3));
		b->pois->set_caching(false);
		std::vector<Coord> cells;
		for (int64_t y = -20; y < 20; y++) {
			for (int64_t x = -20; x < 20; x++) {
				cells.push_back(Coord{x, y});
			}
		}
		std::vector<Coord> shuffled = cells;
		lb::core::Rng(seed).shuffle(shuffled);
		std::map<Coord, std::string> first;
		auto describe = [](const PoiRef &p) {
			if (!p) {
				return std::string("-");
			}
			return std::string(poi_kind_name(p->kind)) + "/" + std::to_string(p->id.index) + "/" + (p->shape ? p->shape->oriented.id : "") +
					"/" + std::to_string(p->origin.x) + "," + std::to_string(p->origin.y) + "/" + std::to_string(p->door.x) + "," +
					std::to_string(p->door.y) + "/" + std::to_string(static_cast<int>(p->door_side));
		};
		for (const Coord &c : cells) {
			first[c] = describe(a->pois->at(c));
		}
		for (const Coord &c : shuffled) {
			REQUIRE(describe(b->pois->at(c)) == first[c]);
		}
		// Derived cells too: one deriver in order, another shuffled with its caches off.
		const auto da = derive_inputs(*a);
		const auto db = derive_inputs(*b);
		const Deriver in_order(da->in);
		Deriver any_order(db->in);
		any_order.set_caching(false);
		std::map<Coord, uint64_t> digests;
		for (const Coord &c : cells) {
			if (a->pois->at(c)) {
				const std::optional<Layout> l = in_order.derive(c, 0);
				REQUIRE(l.has_value());
				digests[c] = l->digest;
			}
		}
		for (const Coord &c : shuffled) {
			if (digests.count(c) != 0) {
				const std::optional<Layout> l = any_order.derive(c, 0);
				REQUIRE(l.has_value());
				CHECK(l->digest == digests[c]);
			}
		}
	}
}

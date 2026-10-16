// GEN-05: stub fill: throats narrowed to the socket's width, blind headings, and no road changing
// width at a cell edge.

#include "core/sound/zone_block.h"
#include "layout_fixture.h"

#include <doctest.h>

#include <algorithm>
#include <deque>

using namespace layout_fixture;

namespace {

bool floor_at(const Cell &c, int64_t x, int64_t y) {
	return c.tiles[static_cast<size_t>(Cell::index_of(x, y))].material == static_cast<uint8_t>(TileMaterial::FLOOR);
}

// The floor tiles along one side of a cell, as positions along the edge.
std::vector<int32_t> edge_floor(const Cell &c, Edge side) {
	std::vector<int32_t> out;
	for (int32_t i = 0; i < CELL_TILES; i++) {
		int64_t x = i, y = i;
		switch (side) {
			case Edge::NORTH: y = 0; break;
			case Edge::SOUTH: y = CELL_TILES - 1; break;
			case Edge::WEST: x = 0; break;
			default: x = CELL_TILES - 1; break;
		}
		if (floor_at(c, x, y)) {
			out.push_back(i);
		}
	}
	return out;
}

std::vector<int32_t> covered(const Socket &s) {
	std::vector<int32_t> out;
	if (s.open) {
		for (int32_t i = 0; i < s.width; i++) {
			out.push_back(opening_first(s.offset, s.width) + i);
		}
	}
	return out;
}

bool connected(const Cell &c) {
	std::vector<uint8_t> seen(CELL_AREA, 0);
	int64_t start = -1, total = 0;
	for (int64_t i = 0; i < CELL_AREA; i++) {
		if (floor_at(c, i % CELL_TILES, i / CELL_TILES)) {
			total++;
			start = start < 0 ? i : start;
		}
	}
	if (start < 0) {
		return true;
	}
	std::deque<int64_t> q{start};
	seen[static_cast<size_t>(start)] = 1;
	int64_t reached = 1;
	while (!q.empty()) {
		const int64_t t = q.front();
		q.pop_front();
		const int64_t x = t % CELL_TILES, y = t / CELL_TILES;
		const int64_t next[4][2] = {{x + 1, y}, {x - 1, y}, {x, y + 1}, {x, y - 1}};
		for (const auto &n : next) {
			if (n[0] < 0 || n[1] < 0 || n[0] >= CELL_TILES || n[1] >= CELL_TILES) {
				continue;
			}
			const int64_t i = Cell::index_of(n[0], n[1]);
			if (!seen[static_cast<size_t>(i)] && floor_at(c, n[0], n[1])) {
				seen[static_cast<size_t>(i)] = 1;
				reached++;
				q.push_back(i);
			}
		}
	}
	return reached == total;
}

} // namespace

TEST_CASE("GEN-05 an open socket narrows its stub's throat to its width; the others are blind headings") {
	const Template t = grid("seam_grid_a", 1.0);
	for (int e = 0; e < 4; e++) {
		for (int32_t offset : {5, 10, 15}) {
			for (int32_t w = 1; w <= 3; w++) {
				CellSockets s{};
				Socket o;
				o.open = true;
				o.offset = offset;
				o.width = w;
				s[static_cast<size_t>(e)] = o;
				const Cell c = fill_stubs(t, s, {4, 7});
				CHECK(c.coord == Coord{4, 7});
				for (int side = 0; side < 4; side++) {
					CHECK(edge_floor(c, static_cast<Edge>(side)) == covered(s[static_cast<size_t>(side)]));
				}
				// Each throat stays its socket's width all the way in, and the blind ones are rock to
				// their full depth.
				for (const Stub &stub : t.stubs) {
					const bool used = static_cast<int>(stub.edge) == e && stub.offset == offset;
					const std::vector<Coord> kept = throat(t, stub, w);
					for (const Coord &tile : throat(t, stub, stub.max_width)) {
						const bool inside = used && std::find(kept.begin(), kept.end(), tile) != kept.end();
						CHECK(floor_at(c, tile.x, tile.y) == inside);
					}
				}
				const std::optional<lb::core::sound::CellBlock> b = lb::core::sound::decode_block(c.road_graph);
				REQUIRE(b.has_value());
				CHECK(lb::core::sound::validate_block(c, *b).empty());
				CHECK(connected(c));
			}
		}
	}
}

TEST_CASE("GEN-05 no road changes width at a cell edge (100,000 adjacent pairs)") {
	auto set = template_set();
	int64_t pairs = 0;
	int64_t open_pairs = 0;
	for (uint64_t seed = 1; pairs < 100000; seed++) {
		Run r = run(seed * 104729, set);
		Deriver d(r.inputs(), 1024);
		for (int64_t y = -7; y <= 7; y++) {
			for (int64_t x = -7; x <= 7; x++) {
				const std::optional<Layout> a = d.derive({x, y}, 0);
				REQUIRE(a.has_value());
				if (!a->base_camp) { // the chosen template covers every open socket, fallback or not
					const Template *chosen = nullptr;
					for (const Template &t : set->templates()) {
						chosen = t.id == a->template_id ? &t : chosen;
					}
					REQUIRE(chosen != nullptr);
					CHECK(covers(*chosen, a->sockets));
				}
				for (Edge side : {Edge::EAST, Edge::SOUTH}) {
					const Coord nb = neighbour({x, y}, side);
					if (nb.x > 7 || nb.y > 7) {
						continue;
					}
					const std::optional<Layout> b = d.derive(nb, 0);
					REQUIRE(b.has_value());
					const Socket &s = a->sockets[static_cast<size_t>(side)];
					CHECK(s == b->sockets[static_cast<size_t>(opposite(side))]);
					if (a->base_camp || b->base_camp) {
						continue; // GEN-02's cell: its gates sit on the opening rule's tiles (checked in GDScript)
					}
					const std::vector<int32_t> here = edge_floor(a->cell, side);
					const std::vector<int32_t> there = edge_floor(b->cell, opposite(side));
					if (here != covered(s) || there != covered(s)) {
						FAIL("cells (" << x << ", " << y << ") and (" << nb.x << ", " << nb.y << ") disagree at their edge");
					}
					pairs++;
					open_pairs += s.open ? 1 : 0;
				}
			}
		}
	}
	MESSAGE(pairs, " pairs, ", open_pairs, " open");
	CHECK(pairs >= 100000);
	CHECK(open_pairs > 50000);
}

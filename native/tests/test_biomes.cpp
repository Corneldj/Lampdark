// GEN-06: biomes by block and ring, the point-of-interest override and the width rules.

#include "core/gen/biomes.h"
#include "core/rng/rng.h"
#include "core/world/coords.h"
#include "layout_fixture.h"

#include <doctest.h>

#include <algorithm>
#include <map>

using namespace layout_fixture;

namespace {

// The design's table (Gameplay §12.2), as data/tuning/mine.json holds it.
BiomeTable design_table() {
	BiomeTable t;
	t.rings = {
			{{"pit_bottom", 1.0}},
			{{"seam", 0.8}, {"old_workings", 0.2}},
			{{"seam", 0.5}, {"old_workings", 0.5}},
			{{"old_workings", 0.6}, {"black_seam", 0.4}},
			{{"old_mens", 1.0}},
	};
	t.widths = {{"pit_bottom", {2, 3}}, {"seam", {2, 3}}, {"old_workings", {1, 2}}, {"black_seam", {2, 3}}, {"old_mens", {1, 1}},
			{"main_road", {3, 3}}};
	return t;
}

} // namespace

TEST_CASE("GEN-06 a cell's ring is its centre's ring") {
	const BiomeTable t = design_table();
	CHECK(ring_of_cell({0, 0}, t.ring_bounds) == 0);
	CHECK(ring_of_cell({3, 0}, t.ring_bounds) == 0); // centre 70 tiles out
	CHECK(ring_of_cell({4, 0}, t.ring_bounds) == 1); // 90
	CHECK(ring_of_cell({13, 0}, t.ring_bounds) == 2); // 270
	CHECK(ring_of_cell({25, 0}, t.ring_bounds) == 3); // 510
	CHECK(ring_of_cell({40, 0}, t.ring_bounds) == 4); // 810
	CHECK(ring_of_cell({-40, 3}, t.ring_bounds) == 4);
}

TEST_CASE("GEN-06 over 10,000 seeds each ring's biomes come in the table's shares") {
	const BiomeTable t = design_table();
	// Ten probe cells in each ring, each in its own block: 100,000 draws a ring.
	std::vector<Coord> probes[5];
	std::map<Coord, bool> used;
	for (int64_t y = -45; y <= 45; y++) {
		for (int64_t x = -45; x <= 45; x++) {
			const Coord c{x, y};
			const int64_t r = ring_of_cell(c, t.ring_bounds);
			const Coord block = lb::core::world::block_of_cell(c);
			if ((x == 0 && y == 0) || r > 4 || probes[r].size() >= 10 || used.count(block) != 0) {
				continue;
			}
			used[block] = true;
			probes[r].push_back(c);
		}
	}
	for (int r = 0; r < 5; r++) {
		REQUIRE(probes[r].size() == 10);
	}
	std::map<std::string, int64_t> counts[5];
	lb::core::Rng rng(606);
	const int64_t seeds = 10000;
	for (int64_t s = 0; s < seeds; s++) {
		const uint64_t seed = rng.next_u64();
		for (int r = 0; r < 5; r++) {
			for (const Coord &c : probes[r]) {
				counts[r][biome_of(seed, c, t)]++;
			}
		}
	}
	auto share = [&](int r, const char *b) { return static_cast<double>(counts[r][b]) / (seeds * 10); };
	CHECK(counts[0].size() == 1);
	CHECK(share(0, "pit_bottom") == 1.0);
	CHECK(std::abs(share(1, "seam") - 0.8) < 0.01);
	CHECK(std::abs(share(1, "old_workings") - 0.2) < 0.01);
	CHECK(std::abs(share(2, "seam") - 0.5) < 0.01);
	CHECK(std::abs(share(2, "old_workings") - 0.5) < 0.01);
	CHECK(std::abs(share(3, "old_workings") - 0.6) < 0.01);
	CHECK(std::abs(share(3, "black_seam") - 0.4) < 0.01);
	CHECK(share(4, "old_mens") == 1.0);
	MESSAGE("ring 1 seam ", share(1, "seam"), ", ring 2 seam ", share(2, "seam"), ", ring 3 old workings ", share(3, "old_workings"));
}

TEST_CASE("GEN-06 a block's cells in one ring share a biome; a ring edge may split a block") {
	const BiomeTable t = design_table();
	lb::core::Rng rng(607);
	int64_t blocks = 0;
	int64_t split = 0;
	for (int s = 0; s < 200; s++) {
		const uint64_t seed = rng.next_u64();
		for (int64_t by = -20; by <= 20; by++) {
			for (int64_t bx = -20; bx <= 20; bx++) {
				std::map<int64_t, std::string> by_ring;
				for (int64_t dy = 0; dy < 2; dy++) {
					for (int64_t dx = 0; dx < 2; dx++) {
						const Coord cell{bx * 2 + dx, by * 2 + dy};
						if (cell.x == 0 && cell.y == 0) {
							continue;
						}
						CHECK(lb::core::world::block_of_cell(cell) == Coord{bx, by});
						const int64_t ring = ring_of_cell(cell, t.ring_bounds);
						const std::string b = biome_of(seed, cell, t);
						auto it = by_ring.find(ring);
						if (it == by_ring.end()) {
							by_ring[ring] = b;
						} else if (it->second != b) {
							FAIL("block (" << bx << ", " << by << ") splits within ring " << ring);
						}
					}
				}
				blocks++;
				split += by_ring.size() > 1 ? 1 : 0;
			}
		}
	}
	MESSAGE(blocks, " blocks, ", split, " straddling a ring edge");
	CHECK(split > 0);
	CHECK(biome_of(1, {0, 0}, t).empty()); // base camp is no biome
}

TEST_CASE("GEN-06 a point of interest's cells report its biome") {
	BiomeCells cells(99, design_table(), SocketParams{});
	CHECK(cells.classify({40, 0}).biome == "old_mens");
	cells.set_override([](Coord c) -> std::optional<std::string> {
		if (c.x >= 40 && c.x <= 41 && c.y >= 0 && c.y <= 1) {
			return std::string("old_workings"); // the lair, deep in the Old Men's Workings
		}
		return std::nullopt;
	});
	CHECK(cells.classify({40, 0}).biome == "old_workings");
	CHECK(cells.classify({41, 1}).biome == "old_workings");
	CHECK(cells.classify({42, 0}).biome == "old_mens");
	CHECK(cells.classify({40, 0}).widths == std::vector<int32_t>{1, 2});
	CHECK_FALSE(cells.classify({0, 0}).templated);
}

TEST_CASE("GEN-06 every opening's width lies in both biomes' sets, or follows the narrower side") {
	const BiomeTable t = design_table();
	const SocketParams p;
	CHECK(biome_widths(t, "seam", p) == std::vector<int32_t>{2, 3});
	CHECK(biome_widths(t, "old_workings", p) == std::vector<int32_t>{1, 2});
	CHECK(biome_widths(t, "old_mens", p) == std::vector<int32_t>{1});
	CHECK(shared_widths(biome_widths(t, "black_seam", p), biome_widths(t, "old_mens", p), p) == std::vector<int32_t>{1});
	auto set = template_set();
	lb::core::Rng rng(608);
	int64_t open = 0;
	for (int s = 0; s < 40; s++) {
		RunHeader head = header(rng.next_u64());
		BiomeCells cells(head.seed, t, head.sockets);
		DeriveInputs in;
		in.header = &head;
		in.templates = set.get();
		in.cells = &cells;
		for (int i = 0; i < 2500; i++) {
			const Coord c{static_cast<int64_t>(rng.next_u64() % 101) - 50, static_cast<int64_t>(rng.next_u64() % 101) - 50};
			const Edge side = static_cast<Edge>(rng.next_u64() % 4);
			const Socket sock = derive_socket(in, edge_of(c, side));
			if (!sock.open || sock.forced) {
				continue;
			}
			open++;
			const std::vector<int32_t> a = cells.classify(c).widths;
			const std::vector<int32_t> b = cells.classify(neighbour(c, side)).widths;
			const std::vector<int32_t> both = shared_widths(a, b, head.sockets);
			CHECK(std::find(both.begin(), both.end(), sock.width) != both.end());
			const bool shared = std::find(a.begin(), a.end(), sock.width) != a.end() && std::find(b.begin(), b.end(), sock.width) != b.end();
			if (!shared) {
				CHECK(sock.width == std::min(a.back(), b.back())); // none shared: the narrower side's widest
			}
		}
	}
	CHECK(open > 40000);
}

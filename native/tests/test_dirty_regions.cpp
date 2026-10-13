#include "light_fixture.h"

#include "core/rng/rng.h"

#include <doctest.h>

using namespace light_fixture;

TEST_CASE("after each of 10,000 random source and opacity edits, incremental equals full recompute") {
	MineMap mine;
	LightGrid grid(mine);
	std::vector<std::string> rows = open_floor();
	std::vector<uint16_t> door_tiles;
	for (int y = 0; y < 20; y += 4) {
		for (int x = 1; x < 20; x += 3) {
			rows[y][x] = (x + y) % 2 == 0 ? '#' : 'D';
		}
	}
	for (int64_t cy = 0; cy <= 1; cy++) {
		for (int64_t cx = 0; cx <= 1; cx++) {
			auto cell = mine_fixture::cell_from({cx, cy}, rows);
			uint32_t barrier_id = 1;
			for (int y = 0; y < 20; y += 4) {
				for (int x = 1; x < 20; x += 3) {
					if ((x + y) % 2 != 0) {
						lb::core::world::Barrier b;
						b.id = barrier_id++;
						b.tiles = {static_cast<uint16_t>(lb::core::world::Cell::index_of(x, y))};
						cell->barriers.push_back(b);
					}
				}
			}
			mine.commit(std::move(cell));
			grid.on_cell_loaded({cx, cy});
		}
	}
	lb::core::Rng rng(20261011);
	std::vector<uint32_t> ids;
	int mismatches = 0;
	for (int edit = 0; edit < 10000; edit++) {
		const int64_t action = *rng.range(0, 9);
		if (action <= 2 || ids.empty()) {
			SourceDesc d = lamp(*rng.range(0, 3999) / 100.0, *rng.range(0, 3999) / 100.0, *rng.range(5, 140) / 10.0);
			ids.push_back(grid.add_source(d));
		} else if (action <= 5) {
			const uint32_t id = ids[static_cast<size_t>(*rng.range(0, static_cast<int64_t>(ids.size()) - 1))];
			grid.update_point(id, *rng.range(0, 3999) / 100.0, *rng.range(0, 3999) / 100.0, *rng.range(0, 60) / 10.0, 1.0);
		} else if (action == 6) {
			const size_t i = static_cast<size_t>(*rng.range(0, static_cast<int64_t>(ids.size()) - 1));
			grid.remove_source(ids[i]);
			ids.erase(ids.begin() + static_cast<int64_t>(i));
		} else if (action == 7) {
			const uint32_t id = ids[static_cast<size_t>(*rng.range(0, static_cast<int64_t>(ids.size()) - 1))];
			grid.set_radius_modifier(id, rng.chance_ppm(500000) ? 0.7 : 1.0, "guttering");
		} else {
			const Coord cell{*rng.range(0, 1), *rng.range(0, 1)};
			mine.set_barrier(cell, static_cast<uint32_t>(*rng.range(1, 17)), rng.chance_ppm(500000));
			for (const lb::core::world::TileChange &c : mine.take_changes()) {
				grid.on_tiles_changed(c.x0, c.y0, c.x1, c.y1);
			}
		}
		if (ids.size() > 24) {
			grid.remove_source(ids.front());
			ids.erase(ids.begin());
		}
		grid.update();
		if (grid.current_values() != grid.reference_values()) {
			mismatches++;
		}
	}
	CHECK(mismatches == 0);
}

#pragma once
// Helpers for VIS-03's tests: open floor (or a picture) around the origin, exact-value spot
// lights, and a Vision with the starting perception table.

#include "core/light/light_grid.h"
#include "core/vision/seen_set.h"
#include "mine_fixture.h"

#include <memory>
#include <string>
#include <vector>

namespace vision_fixture {

using namespace lb::core::vision;
using lb::core::light::ColourClass;
using lb::core::light::LightGrid;
using lb::core::light::Shape;
using lb::core::light::SourceDesc;
using lb::core::sim::MirrorEntity;
using lb::core::world::Coord;
using lb::core::world::MineMap;

constexpr uint16_t MINER = 1, MOTH = 3, ITEM = 6, COAT_HEAP = 12, STYTHE = 5;

struct World {
	MineMap mine;
	std::unique_ptr<LightGrid> light;
	std::unique_ptr<Vision> vision;

	// Cells from (-r, -r) to (r, r), open floor unless `picture` (rows of the cell at (0, 0)) is given.
	explicit World(int64_t r = 2, std::vector<std::string> picture = {}) {
		for (int64_t cy = -r; cy <= r; cy++) {
			for (int64_t cx = -r; cx <= r; cx++) {
				std::vector<std::string> rows(lb::core::world::CELL_TILES, std::string(lb::core::world::CELL_TILES, '.'));
				if (cx == 0 && cy == 0 && !picture.empty()) {
					rows = picture;
				}
				mine.commit(mine_fixture::cell_from({cx, cy}, rows));
			}
		}
		light = std::make_unique<LightGrid>(mine);
		for (const Coord &c : mine.loaded_cells()) {
			light->on_cell_loaded(c);
		}
		vision = std::make_unique<Vision>(mine, *light);
		PerceptionClass miner;
		miner.size = SizeClass::MINER;
		vision->table.set(MINER, miner);
		vision->table.set(STYTHE, miner);
		PerceptionClass large;
		large.size = SizeClass::LARGE;
		vision->table.set(MOTH, large);
		large.motionless_always = true;
		vision->table.set(COAT_HEAP, large);
		PerceptionClass small;
		small.size = SizeClass::SMALL;
		vision->table.set(ITEM, small);
	}

	// One tile lit to exactly `value` (0-1).
	uint32_t spot(Coord t, double value, ColourClass colour = ColourClass::AMBER) {
		SourceDesc d;
		d.shape = Shape::SPOT;
		d.kind = "test_spot";
		d.colour = colour;
		d.peak = value;
		d.spot = t;
		return light->add_source(d);
	}

	// Every tile in a rectangle lit to `value`.
	uint32_t area(Coord a, Coord b, double value, ColourClass colour = ColourClass::AMBER) {
		SourceDesc d;
		d.shape = Shape::AREA;
		d.kind = "test_area";
		d.colour = colour;
		d.peak = value;
		for (int64_t y = a.y; y <= b.y; y++) {
			for (int64_t x = a.x; x <= b.x; x++) {
				d.tiles.push_back({x, y});
			}
		}
		return light->add_source(d);
	}

	void settle() {
		light->begin_tick(20.0);
		light->update();
	}
};

inline MirrorEntity entity(uint32_t id, uint16_t kind, double x, double y, uint32_t flags = 0) {
	MirrorEntity e;
	e.id = id;
	e.kind = kind;
	e.x = x;
	e.y = y;
	e.flags = flags;
	return e;
}

// Facings: 0 east, 16384 south (+y), 32768 west, 49152 north.
constexpr uint32_t EAST = 0, SOUTH = 16384, WEST = 32768, NORTH = 49152;

} // namespace vision_fixture

#include "light_fixture.h"

#include <doctest.h>

#include <algorithm>
#include <chrono>

using namespace light_fixture;

namespace {

// A fixed scene: rock pillars and roads, five lamps of every wick, a flare, egg-glow, a spot.
uint64_t scene_digest() {
	MineMap mine;
	LightGrid grid(mine);
	std::vector<std::string> rows = open_floor();
	for (int y = 2; y < 20; y += 5) {
		for (int x = 3; x < 20; x += 6) {
			rows[y][x] = '#';
			rows[y][x + 1] = '#';
		}
	}
	for (int64_t cy = -1; cy <= 1; cy++) {
		for (int64_t cx = -1; cx <= 1; cx++) {
			mine.commit(mine_fixture::cell_from({cx, cy}, rows));
			grid.on_cell_loaded({cx, cy});
		}
	}
	grid.add_source(lamp(1.25, 1.75, 2.5));
	grid.add_source(lamp(10.5, 4.33, 4.0));
	grid.add_source(lamp(-7.1, 12.9, 5.5));
	grid.add_source(lamp(15.0, -3.0, 4.0));
	SourceDesc flare = lamp(0.5, 0.5, 14.0);
	flare.colour = ColourClass::PALE_AMBER;
	grid.add_source(flare);
	SourceDesc egg = lamp(-12.5, -12.5, 1.5);
	egg.peak = 0.2;
	egg.colour = ColourClass::EGG_GLOW;
	grid.add_source(egg);
	grid.update();
	return grid.digest();
}

} // namespace

// Recorded on Linux; Windows must match exactly.
constexpr uint64_t GOLDEN_SCENE = 14549250489646288940ULL;

TEST_CASE("the same inputs give the same grid digest on every platform") {
	CHECK(scene_digest() == scene_digest());
	CHECK(scene_digest() == GOLDEN_SCENE);
}

TEST_CASE("update timing: 9 cells, 8 moving lamps, a flare and base-camp light") {
	MineMap mine;
	LightGrid grid(mine);
	load_open(mine, &grid);
	SourceDesc camp;
	camp.shape = Shape::AREA;
	camp.peak = 0.6;
	for (int64_t y = 0; y < 12; y++) {
		for (int64_t x = 0; x < 16; x++) {
			camp.tiles.push_back({x, y});
		}
	}
	grid.add_source(camp);
	std::vector<uint32_t> lamps;
	for (int i = 0; i < 8; i++) {
		lamps.push_back(grid.add_source(lamp(-15.0 + 4 * i, -10.0 + 3 * i, i % 2 == 0 ? 4.0 : 5.5)));
	}
	grid.add_source(lamp(10.0, 10.0, 14.0));
	grid.update();
	std::vector<int64_t> samples;
	for (int tick = 0; tick < 400; tick++) {
		grid.begin_tick(20.0);
		for (size_t i = 0; i < lamps.size(); i++) {
			const double t = tick * 0.15;
			grid.update_point(lamps[i], -15.0 + 4 * i + (tick % 80) * 0.15, -10.0 + 3 * i + t * 0.0, i % 2 == 0 ? 4.0 : 5.5, 1.0);
		}
		const auto start = std::chrono::steady_clock::now();
		grid.update();
		samples.push_back(std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - start).count());
	}
	std::sort(samples.begin(), samples.end());
	const int64_t p99 = samples[samples.size() * 99 / 100];
	MESSAGE("light update p50 " << samples[samples.size() / 2] << " us, p99 " << p99 << " us");
	CHECK(p99 > 0);
}

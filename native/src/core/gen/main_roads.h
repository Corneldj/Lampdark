#pragma once
// GEN-07: the main roads (Gameplay §12.1-12.3). Railed, 3-wide roads run along every 8th row and
// column of cells, crossing at the shaft; they stop at the Deep. Their edges are forced open at the
// road's offset and width. Each 160-tile segment between crossings (base camp counts as one) is
// broken by bends into straight runs of 25-40 tiles, bends falling at in-cell positions 5, 10 or 15
// (gen.mainroad picks the partition). About one straight main-road cell in six holds an old fall
// (gen.oldfall), with an exit forced open on each side of it. Pure; server-only.

#include "core/gen/biomes.h"

#include <functional>
#include <set>

namespace lb::core::gen {

struct MainRoadParams {
	int32_t spacing = 8; // mine.main_road_spacing_cells
	int32_t width = 3; // mine.main_road_width_tiles
	int32_t offset = 10; // mine.main_road_edge_offset_tiles
	int32_t run_min = 25; // mine.main_road_run_min_tiles
	int32_t run_max = 40; // mine.main_road_run_max_tiles
	int32_t max_ring = 3; // mine.main_road_max_ring
	uint32_t old_fall_ppm = 166700; // mine.old_fall_probability, in millionths
	// An old fall's exits: the side edges' offsets on the near (north or west) and far side.
	int32_t fall_exit_near = 5;
	int32_t fall_exit_far = 15;
};

class MainRoads {
public:
	MainRoads(uint64_t seed, MainRoadParams params, std::vector<int64_t> ring_bounds, std::set<lb::core::world::Coord> arch_cells);

	bool on_row(lb::core::world::Coord c) const; // on an east-west line
	bool on_column(lb::core::world::Coord c) const; // on a north-south line
	bool is_main_road_cell(lb::core::world::Coord c) const;
	bool is_crossing(lb::core::world::Coord c) const;
	// Every valid run sequence for a segment, in a fixed order.
	const std::vector<std::vector<int32_t>> &partitions() const { return partitions_; }
	// The runs of segment `segment` of line `line` (rows: axis 0, columns: axis 1).
	const std::vector<int32_t> &segment_runs(int32_t axis, int64_t line, int64_t segment) const;
	// The bend in a main-road cell, as its in-cell position along the road (5, 10 or 15), or -1.
	int32_t bend_in(lb::core::world::Coord c) const;
	bool old_fall(lb::core::world::Coord c) const;
	const MainRoadParams &params() const { return params_; }
	uint64_t seed() const { return seed_; }

	// GEN-08's spine cells take no old fall.
	std::function<bool(lb::core::world::Coord)> is_spine;

	static std::vector<std::vector<int32_t>> enumerate_partitions(const MainRoadParams &p);

private:
	uint64_t seed_;
	MainRoadParams params_;
	std::vector<int64_t> ring_bounds_;
	std::set<lb::core::world::Coord> arch_cells_;
	std::vector<std::vector<int32_t>> partitions_;
};

// The forced sockets of rule 3: main-road edges open at the road's offset and width, and an old
// fall's two exits open (their width hashed among the widths both cells allow).
class MainRoadSockets : public SocketProvider {
public:
	MainRoadSockets(const MainRoads &roads, const CellClassifier &cells, SocketParams params)
		: roads_(roads), cells_(cells), params_(std::move(params)) {}
	std::optional<Socket> query(const EdgeKey &edge) const override;

private:
	const MainRoads &roads_;
	const CellClassifier &cells_;
	SocketParams params_;
};

// Main-road cells over the biome map: kind main road, the template shape the bends ask for, the
// old fall, north-south roads transposed, and dressed by the biome the cell lies in.
class MainRoadCells : public CellClassifier {
public:
	MainRoadCells(const MainRoads &roads, const CellClassifier &base) : roads_(roads), base_(base) {}
	CellClass classify(lb::core::world::Coord cell) const override;

private:
	const MainRoads &roads_;
	const CellClassifier &base_;
};

// GEN-07's grey-box dressing of a main-road cell by its biome: coal faces in the Seam, the Black
// Seam and the pit-bottom roads; stone elsewhere.
void dress(lb::core::world::Cell &cell, const std::string &biome);

} // namespace lb::core::gen

#include "core/gen/main_roads.h"

#include "core/generated/hash_domains.h"
#include "core/rng/hash.h"
#include "core/world/coords.h"

namespace lb::core::gen {

using lb::core::world::CELL_TILES;
using lb::core::world::Coord;
using lb::core::world::floor_div;
using lb::core::world::floor_mod;
using lb::core::world::TileMaterial;

std::vector<std::vector<int32_t>> MainRoads::enumerate_partitions(const MainRoadParams &p) {
	// Runs of run_min to run_max in steps of 5 summing to a segment; no bend on a cell edge: a
	// segment starts at in-cell position `offset`, so a bend b tiles in sits at (offset + b) mod 20.
	const int32_t total = p.spacing * static_cast<int32_t>(CELL_TILES);
	std::vector<int32_t> runs;
	for (int32_t r = p.run_min; r <= p.run_max; r += 5) {
		runs.push_back(r);
	}
	std::vector<std::vector<int32_t>> out;
	std::vector<int32_t> current;
	std::function<void(int32_t)> walk = [&](int32_t at) {
		if (at == total) {
			out.push_back(current);
			return;
		}
		for (int32_t r : runs) {
			const int32_t next = at + r;
			if (next > total) {
				continue;
			}
			if (next < total && floor_mod(p.offset + next, static_cast<int64_t>(CELL_TILES)) == 0) {
				continue;
			}
			current.push_back(r);
			walk(next);
			current.pop_back();
		}
	};
	walk(0);
	return out;
}

MainRoads::MainRoads(uint64_t seed, MainRoadParams params, std::vector<int64_t> ring_bounds, std::set<Coord> arch_cells)
	: seed_(seed), params_(params), ring_bounds_(std::move(ring_bounds)), arch_cells_(std::move(arch_cells)),
	  partitions_(enumerate_partitions(params_)) {}

bool MainRoads::on_row(Coord c) const {
	return floor_mod(c.y, params_.spacing) == 0;
}

bool MainRoads::on_column(Coord c) const {
	return floor_mod(c.x, params_.spacing) == 0;
}

bool MainRoads::is_main_road_cell(Coord c) const {
	if (c.x == 0 && c.y == 0) {
		return false;
	}
	return (on_row(c) || on_column(c)) && ring_of_cell(c, ring_bounds_) <= params_.max_ring;
}

bool MainRoads::is_crossing(Coord c) const {
	return is_main_road_cell(c) && on_row(c) && on_column(c);
}

const std::vector<int32_t> &MainRoads::segment_runs(int32_t axis, int64_t line, int64_t segment) const {
	static const std::vector<int32_t> NONE;
	if (partitions_.empty()) {
		return NONE;
	}
	const int64_t keys[3] = {axis, line, segment};
	return partitions_[hash_u64(seed_, hash_domain::GEN_MAINROAD, keys, 3) % partitions_.size()];
}

int32_t MainRoads::bend_in(Coord c) const {
	if (!is_main_road_cell(c) || is_crossing(c)) {
		return -1;
	}
	const bool row = on_row(c);
	const int32_t axis = row ? 0 : 1;
	const int64_t along = row ? c.x : c.y; // the cell's place along its line
	const int64_t line = floor_div(row ? c.y : c.x, params_.spacing);
	const int64_t segment = floor_div(along, params_.spacing);
	const int64_t start = segment * params_.spacing * CELL_TILES + params_.offset; // the crossing's centre
	const int64_t lo = along * CELL_TILES;
	int64_t at = start;
	for (int32_t r : segment_runs(axis, line, segment)) {
		at += r;
		if (at >= lo && at < lo + CELL_TILES) {
			return static_cast<int32_t>(at - lo);
		}
	}
	return -1;
}

bool MainRoads::old_fall(Coord c) const {
	if (!is_main_road_cell(c) || is_crossing(c) || bend_in(c) >= 0 || arch_cells_.count(c) != 0 || (is_spine && is_spine(c))) {
		return false;
	}
	const int64_t keys[2] = {c.x, c.y};
	return hash_u64(seed_, hash_domain::GEN_OLDFALL, keys, 2) % 1000000u < params_.old_fall_ppm;
}

std::optional<Socket> MainRoadSockets::query(const EdgeKey &edge) const {
	const Coord a{edge.x, edge.y};
	const Coord b = edge.axis == Axis::EAST ? Coord{edge.x + 1, edge.y} : Coord{edge.x, edge.y + 1};
	const MainRoadParams &p = roads_.params();
	// Along a line: both cells main road on the line the edge runs along.
	const bool along = edge.axis == Axis::EAST ? roads_.on_row(a) : roads_.on_column(a);
	const bool base_camp = (a.x == 0 && a.y == 0) || (b.x == 0 && b.y == 0); // GEN-02 forces its own edges
	if (along && !base_camp && roads_.is_main_road_cell(a) && roads_.is_main_road_cell(b)) {
		Socket s;
		s.open = true;
		s.offset = p.offset;
		s.width = p.width;
		s.forced = true;
		return s;
	}
	// Where a main road meets the Deep it stops (Proposed): the edge is shut, its last cell's road
	// a blind heading; the way on is through the maze.
	if (along && !base_camp && roads_.is_main_road_cell(a) != roads_.is_main_road_cell(b)) {
		Socket s;
		s.forced = true;
		return s;
	}
	// An old fall's exits: the near side at fall_exit_near, the far side at fall_exit_far.
	for (const Coord &c : {a, b}) {
		if (!roads_.old_fall(c)) {
			continue;
		}
		const bool row = roads_.on_row(c);
		const Edge near = row ? Edge::NORTH : Edge::WEST;
		const Edge far = row ? Edge::SOUTH : Edge::EAST;
		int32_t offset = 0;
		if (edge_of(c, near) == edge) {
			offset = p.fall_exit_near;
		} else if (edge_of(c, far) == edge) {
			offset = p.fall_exit_far;
		} else {
			continue;
		}
		const std::vector<int32_t> widths = shared_widths(cells_.classify(a).widths, cells_.classify(b).widths, params_);
		const int64_t keys[3] = {edge.x, edge.y, static_cast<int64_t>(edge.axis)};
		Socket s;
		s.open = !widths.empty();
		s.offset = offset;
		s.width = widths.empty() ? 0 : widths[hash_u64(roads_.seed(), hash_domain::GEN_SOCKET_WIDTH, keys, 3) % widths.size()];
		s.forced = true;
		return s;
	}
	return std::nullopt;
}

CellClass MainRoadCells::classify(Coord cell) const {
	CellClass c = base_.classify(cell);
	if (!roads_.is_main_road_cell(cell)) {
		return c;
	}
	c.kind = TemplateKind::MAIN_ROAD;
	c.dress = c.biome;
	c.biome = "main_road";
	if (roads_.is_crossing(cell)) {
		c.shape = "crossing";
	} else {
		const int32_t bend = roads_.bend_in(cell);
		c.shape = bend >= 0 ? "bend_" + std::to_string(bend) : "straight";
		c.transpose = !roads_.on_row(cell);
		c.old_fall = roads_.old_fall(cell);
	}
	return c;
}

void dress(lb::core::world::Cell &cell, const std::string &biome) {
	if (biome != "seam" && biome != "black_seam" && biome != "pit_bottom") {
		return;
	}
	// Rock faces beside floor turn to coal (the pit-bottom roads are Seam beyond their brick).
	std::vector<int64_t> faces;
	for (int64_t y = 0; y < CELL_TILES; y++) {
		for (int64_t x = 0; x < CELL_TILES; x++) {
			if (cell.tiles[static_cast<size_t>(lb::core::world::Cell::index_of(x, y))].material != static_cast<uint8_t>(TileMaterial::ROCK)) {
				continue;
			}
			bool beside = false;
			for (int64_t dy = -1; dy <= 1 && !beside; dy++) {
				for (int64_t dx = -1; dx <= 1 && !beside; dx++) {
					const int64_t nx = x + dx, ny = y + dy;
					beside = nx >= 0 && ny >= 0 && nx < CELL_TILES && ny < CELL_TILES && cell.tiles[static_cast<size_t>(lb::core::world::Cell::index_of(nx, ny))].material == static_cast<uint8_t>(TileMaterial::FLOOR);
				}
			}
			if (beside) {
				faces.push_back(lb::core::world::Cell::index_of(x, y));
			}
		}
	}
	for (int64_t i : faces) {
		cell.tiles[static_cast<size_t>(i)].material = static_cast<uint8_t>(TileMaterial::COAL);
	}
}

} // namespace lb::core::gen

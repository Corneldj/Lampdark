#pragma once
// GEN-06: biomes and rings (Gameplay §12.2). A cell's biome is a hash of the seed and its 2x2-cell
// block, mapped through its ring's weights, so biomes come in patches 40 tiles across and the rock
// shows how deep a crew stands. Each biome allows its own socket widths. Server-only: no biome
// identifier reaches a client.

#include "core/gen/derive.h"

#include <functional>
#include <map>
#include <optional>
#include <string>
#include <utility>
#include <vector>

namespace lb::core::gen {

struct BiomeTable {
	// Per ring 0, 1, ...: (biome, weight) in the table's mapping order (mine.biome_weights_ring<n>).
	std::vector<std::vector<std::pair<std::string, double>>> rings;
	// biome -> [min, max] socket width (mine.biome_socket_widths_min / _max).
	std::map<std::string, std::pair<int32_t, int32_t>> widths;
	// The starts of rings 1.. in tiles (depth.ring_start_tiles).
	std::vector<int64_t> ring_bounds{80, 200, 400, 700};
};

// The ring of a cell: the ring of its centre point (Proposed).
int64_t ring_of_cell(lb::core::world::Coord cell, const std::vector<int64_t> &ring_bounds);

// The biome of a cell by its block's hash (gen.biome) and its ring's weights; "" for base camp.
std::string biome_of(uint64_t seed, lb::core::world::Coord cell, const BiomeTable &table);

// The socket widths a biome allows (its [min, max] among the configured widths), ascending.
std::vector<int32_t> biome_widths(const BiomeTable &table, const std::string &biome, const SocketParams &params);

// GEN-06's classifier: base camp at (0, 0); every other cell a biome cell of biome_of's biome
// (or a point of interest's, through the override GEN-09 registers).
class BiomeCells : public CellClassifier {
public:
	using Override = std::function<std::optional<std::string>(lb::core::world::Coord)>;

	BiomeCells(uint64_t seed, BiomeTable table, SocketParams params);
	CellClass classify(lb::core::world::Coord cell) const override;
	void set_override(Override o) { override_ = std::move(o); }
	const BiomeTable &table() const { return table_; }

private:
	uint64_t seed_;
	BiomeTable table_;
	SocketParams params_;
	Override override_;
};

} // namespace lb::core::gen

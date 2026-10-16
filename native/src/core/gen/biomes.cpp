#include "core/gen/biomes.h"

#include "core/generated/hash_domains.h"
#include "core/rng/hash.h"
#include "core/world/coords.h"

#include <algorithm>
#include <cmath>

namespace lb::core::gen {

using lb::core::world::CELL_TILES;
using lb::core::world::Coord;

int64_t ring_of_cell(Coord cell, const std::vector<int64_t> &ring_bounds) {
	const double cx = static_cast<double>(cell.x * CELL_TILES) + CELL_TILES / 2.0;
	const double cy = static_cast<double>(cell.y * CELL_TILES) + CELL_TILES / 2.0;
	return lb::core::world::ring_of_point(cx, cy, ring_bounds);
}

std::string biome_of(uint64_t seed, Coord cell, const BiomeTable &table) {
	if (cell.x == 0 && cell.y == 0) {
		return "";
	}
	if (table.rings.empty()) {
		return "";
	}
	const int64_t ring = std::min<int64_t>(ring_of_cell(cell, table.ring_bounds), static_cast<int64_t>(table.rings.size()) - 1);
	const std::vector<std::pair<std::string, double>> &weights = table.rings[static_cast<size_t>(ring)];
	if (weights.empty()) {
		return "";
	}
	// Whole millionths, so the mapping is integer arithmetic on every machine.
	std::vector<uint64_t> ppm;
	uint64_t total = 0;
	for (const auto &[biome, w] : weights) {
		ppm.push_back(w > 0.0 ? static_cast<uint64_t>(std::llround(w * 1000000.0)) : 0);
		total += ppm.back();
	}
	if (total == 0) {
		return weights.front().first;
	}
	const Coord block = lb::core::world::block_of_cell(cell);
	const int64_t keys[2] = {block.x, block.y};
	uint64_t u = hash_u64(seed, hash_domain::GEN_BIOME, keys, 2) % total;
	for (size_t i = 0; i < weights.size(); i++) {
		if (u < ppm[i]) {
			return weights[i].first;
		}
		u -= ppm[i];
	}
	return weights.back().first;
}

std::vector<int32_t> biome_widths(const BiomeTable &table, const std::string &biome, const SocketParams &params) {
	std::vector<int32_t> out;
	auto it = table.widths.find(biome);
	for (int32_t w : params.widths) {
		if (it == table.widths.end() || (w >= it->second.first && w <= it->second.second)) {
			out.push_back(w);
		}
	}
	std::sort(out.begin(), out.end());
	return out;
}

BiomeCells::BiomeCells(uint64_t seed, BiomeTable table, SocketParams params)
	: seed_(seed), table_(std::move(table)), params_(std::move(params)) {}

CellClass BiomeCells::classify(Coord cell) const {
	CellClass c;
	if (cell.x == 0 && cell.y == 0) {
		c.kind = TemplateKind::BASE_CAMP;
		c.templated = false;
		c.widths = params_.widths;
		return c;
	}
	std::optional<std::string> poi = override_ ? override_(cell) : std::nullopt;
	c.biome = poi ? *poi : biome_of(seed_, cell, table_);
	c.widths = biome_widths(table_, c.biome, params_);
	return c;
}

} // namespace lb::core::gen

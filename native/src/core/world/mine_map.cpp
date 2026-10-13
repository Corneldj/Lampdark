#include "core/world/mine_map.h"

#include <algorithm>
#include <cmath>
#include <queue>
#include <tuple>

namespace lb::core::world {

namespace {

// Thousandths of a tile from a tile centre to the nearest point of another tile:
// doubled offsets give exact integers, then one correctly rounded sqrt.
uint32_t centre_to_tile_milli(Coord from, Coord to) {
	auto axis = [](int64_t a, int64_t b) -> int64_t {
		// Distance, doubled, from a's centre (2a + 1) to the span [2b, 2b + 2].
		const int64_t c = 2 * a + 1;
		if (c < 2 * b) {
			return 2 * b - c;
		}
		if (c > 2 * b + 2) {
			return c - (2 * b + 2);
		}
		return 0;
	};
	const int64_t dx = axis(from.x, to.x);
	const int64_t dy = axis(from.y, to.y);
	const double d = std::sqrt(static_cast<double>(dx * dx + dy * dy)) / 2.0;
	return static_cast<uint32_t>(std::llround(d * 1000.0));
}

bool is_rock(TileMaterial m) {
	return m == TileMaterial::ROCK || m == TileMaterial::COAL;
}

} // namespace

const Cell *MineMap::cell(Coord coord) const {
	auto it = cells_.find(coord);
	return it == cells_.end() ? nullptr : it->second.get();
}

Cell *MineMap::cell_mut(Coord coord) {
	auto it = cells_.find(coord);
	return it == cells_.end() ? nullptr : it->second.get();
}

std::vector<Coord> MineMap::loaded_cells() const {
	std::vector<Coord> out;
	for (const auto &entry : cells_) {
		out.push_back(entry.first);
	}
	return out;
}

void MineMap::commit(std::unique_ptr<Cell> cell) {
	const Coord coord = cell->coord;
	for (Collapse &c : cell->collapses) {
		for (const TileWrite &w : c.is_fallen ? c.fallen : c.standing) {
			cell->tiles[w.index].material = w.material;
		}
	}
	for (const Barrier &b : cell->barriers) {
		for (uint16_t i : b.tiles) {
			cell->tiles[i].state = b.open ? (cell->tiles[i].state | STATE_OPEN) : (cell->tiles[i].state & ~STATE_OPEN);
		}
	}
	cells_[coord] = std::move(cell);
	rebuild_fields_around(coord);
}

bool MineMap::unload(Coord coord) {
	if (cells_.erase(coord) == 0) {
		return false;
	}
	rebuild_fields_around(coord);
	return true;
}

std::optional<Tile> MineMap::tile_at(Coord tile) const {
	const Cell *c = cell(cell_of(tile));
	if (c == nullptr) {
		return std::nullopt;
	}
	const Coord l = local_of(tile);
	return c->tiles[Cell::index_of(l.x, l.y)];
}

TileMaterial MineMap::effective_material(Coord tile) const {
	std::optional<Tile> t = tile_at(tile);
	if (!t) {
		return TileMaterial::ROCK;
	}
	return MaterialTable::effective(static_cast<TileMaterial>(t->material), t->state);
}

bool MineMap::is_walkable(Coord tile, bool doors_open) const {
	std::optional<Tile> t = tile_at(tile);
	if (!t) {
		return false;
	}
	const TileMaterial m = static_cast<TileMaterial>(t->material);
	if (doors_open && (m == TileMaterial::STEEL || m == TileMaterial::WOODEN_DOOR)) {
		return true;
	}
	return !materials.get(MaterialTable::effective(m, t->state)).solid;
}

bool MineMap::is_solid(Coord tile) const {
	return materials.get(effective_material(tile)).solid;
}

bool MineMap::is_opaque(Coord tile) const {
	return materials.get(effective_material(tile)).opaque;
}

bool MineMap::tapper_face_usable(Coord tile) const {
	if (!tile_at(tile) || !materials.get(effective_material(tile)).tapper_face) {
		return false;
	}
	const Coord around[4] = {{tile.x + 1, tile.y}, {tile.x - 1, tile.y}, {tile.x, tile.y + 1}, {tile.x, tile.y - 1}};
	for (const Coord &n : around) {
		if (is_walkable(n)) {
			return true;
		}
	}
	return false;
}

uint32_t MineMap::strike_milli(Coord tile) const {
	const Cell *c = cell(cell_of(tile));
	if (c == nullptr) {
		return FIELD_FAR;
	}
	const Coord l = local_of(tile);
	return c->strike_milli[Cell::index_of(l.x, l.y)];
}

uint32_t MineMap::depth_milli(Coord tile) const {
	const Cell *c = cell(cell_of(tile));
	if (c == nullptr) {
		return FIELD_FAR;
	}
	const Coord l = local_of(tile);
	return c->depth_milli[Cell::index_of(l.x, l.y)];
}

uint8_t MineMap::thickness(Coord tile) const {
	const Cell *c = cell(cell_of(tile));
	if (c == nullptr) {
		return 0;
	}
	const Coord l = local_of(tile);
	return c->thickness[Cell::index_of(l.x, l.y)];
}

void MineMap::rebuild_fields_around(Coord coord) {
	for (int64_t dy = -1; dy <= 1; dy++) {
		for (int64_t dx = -1; dx <= 1; dx++) {
			if (Cell *c = cell_mut({coord.x + dx, coord.y + dy})) {
				rebuild_fields(*c);
			}
		}
	}
}

void MineMap::rebuild_fields(Cell &cell) {
	const Coord base{cell.coord.x * CELL_TILES, cell.coord.y * CELL_TILES};
	const int64_t reach = FIELD_REACH;
	// A window of the cell plus `reach` tiles of every neighbour, as effective materials.
	const int64_t w = CELL_TILES + 2 * (reach + THICKNESS_CAP);
	const int64_t off = reach + THICKNESS_CAP;
	std::vector<TileMaterial> mat(static_cast<size_t>(w * w));
	std::vector<uint8_t> loaded(static_cast<size_t>(w * w));
	for (int64_t y = 0; y < w; y++) {
		for (int64_t x = 0; x < w; x++) {
			const Coord g{base.x + x - off, base.y + y - off};
			const size_t i = static_cast<size_t>(y * w + x);
			loaded[i] = tile_at(g).has_value() ? 1 : 0;
			mat[i] = effective_material(g);
		}
	}
	auto at = [&](int64_t x, int64_t y) -> TileMaterial { return mat[static_cast<size_t>((y + off) * w + (x + off))]; };
	auto open = [&](int64_t x, int64_t y) -> bool {
		const size_t i = static_cast<size_t>((y + off) * w + (x + off));
		return loaded[i] != 0 && !materials.get(mat[i]).solid;
	};
	auto usable_face = [&](int64_t x, int64_t y) -> bool {
		const TileMaterial m = at(x, y);
		if (!materials.get(m).tapper_face) {
			return false;
		}
		const size_t i = static_cast<size_t>((y + off) * w + (x + off));
		if (loaded[i] == 0) {
			return false;
		}
		return open(x + 1, y) || open(x - 1, y) || open(x, y + 1) || open(x, y - 1);
	};
	for (int64_t ly = 0; ly < CELL_TILES; ly++) {
		for (int64_t lx = 0; lx < CELL_TILES; lx++) {
			const size_t i = static_cast<size_t>(Cell::index_of(lx, ly));
			const bool floor = !materials.get(at(lx, ly)).solid;
			uint32_t best_strike = FIELD_FAR;
			uint32_t best_depth = FIELD_FAR;
			for (int64_t dy = -reach; dy <= reach; dy++) {
				for (int64_t dx = -reach; dx <= reach; dx++) {
					const int64_t x = lx + dx;
					const int64_t y = ly + dy;
					if (floor && usable_face(x, y)) {
						best_strike = std::min(best_strike, centre_to_tile_milli({lx, ly}, {x, y}));
					} else if (!floor && open(x, y)) {
						best_depth = std::min(best_depth, centre_to_tile_milli({lx, ly}, {x, y}));
					}
				}
			}
			const uint32_t cap = static_cast<uint32_t>(reach * 1000);
			cell.strike_milli[i] = floor && best_strike <= cap ? best_strike : FIELD_FAR;
			cell.depth_milli[i] = !floor && best_depth <= cap ? best_depth : FIELD_FAR;
		}
	}
	// Thickness: the largest all-rock square (side up to THICKNESS_CAP) containing each tile.
	const int64_t span = CELL_TILES + 2 * THICKNESS_CAP;
	std::vector<uint8_t> square(static_cast<size_t>(span * span), 0); // largest square ending at (x, y)
	std::vector<uint8_t> best(static_cast<size_t>(span * span), 0);
	auto rock_at = [&](int64_t x, int64_t y) -> bool {
		const size_t i = static_cast<size_t>((y + off) * w + (x + off));
		return loaded[i] != 0 && is_rock(mat[i]);
	};
	for (int64_t y = 0; y < span; y++) {
		for (int64_t x = 0; x < span; x++) {
			const int64_t gx = x - THICKNESS_CAP;
			const int64_t gy = y - THICKNESS_CAP;
			if (!rock_at(gx, gy)) {
				continue;
			}
			uint8_t s = 1;
			if (x > 0 && y > 0) {
				const uint8_t a = square[static_cast<size_t>((y - 1) * span + x)];
				const uint8_t b = square[static_cast<size_t>(y * span + x - 1)];
				const uint8_t c = square[static_cast<size_t>((y - 1) * span + x - 1)];
				s = static_cast<uint8_t>(std::min<int>(THICKNESS_CAP, 1 + std::min({a, b, c})));
			}
			square[static_cast<size_t>(y * span + x)] = s;
			for (int64_t sy = 0; sy < s; sy++) {
				for (int64_t sx = 0; sx < s; sx++) {
					uint8_t &b = best[static_cast<size_t>((y - sy) * span + (x - sx))];
					b = std::max(b, s);
				}
			}
		}
	}
	for (int64_t ly = 0; ly < CELL_TILES; ly++) {
		for (int64_t lx = 0; lx < CELL_TILES; lx++) {
			cell.thickness[static_cast<size_t>(Cell::index_of(lx, ly))] =
					best[static_cast<size_t>((ly + THICKNESS_CAP) * span + lx + THICKNESS_CAP)];
		}
	}
}

bool MineMap::set_barrier(Coord coord, uint32_t barrier_id, bool open) {
	Cell *c = cell_mut(coord);
	if (c == nullptr) {
		return false;
	}
	for (Barrier &b : c->barriers) {
		if (b.id != barrier_id) {
			continue;
		}
		b.open = open;
		TileChange change{coord, INT64_MAX, INT64_MAX, INT64_MIN, INT64_MIN, open ? "barrier_open" : "barrier_shut"};
		for (uint16_t i : b.tiles) {
			Tile &t = c->tiles[i];
			t.state = open ? (t.state | STATE_OPEN) : (t.state & ~STATE_OPEN);
			const int64_t gx = coord.x * CELL_TILES + i % CELL_TILES;
			const int64_t gy = coord.y * CELL_TILES + i / CELL_TILES;
			change.x0 = std::min(change.x0, gx);
			change.y0 = std::min(change.y0, gy);
			change.x1 = std::max(change.x1, gx);
			change.y1 = std::max(change.y1, gy);
		}
		rebuild_fields_around(coord);
		changes_.push_back(change);
		return true;
	}
	return false;
}

bool MineMap::set_collapse(Coord coord, uint32_t collapse_id, bool fallen) {
	Cell *c = cell_mut(coord);
	if (c == nullptr) {
		return false;
	}
	for (Collapse &col : c->collapses) {
		if (col.id != collapse_id) {
			continue;
		}
		col.is_fallen = fallen;
		TileChange change{coord, INT64_MAX, INT64_MAX, INT64_MIN, INT64_MIN, fallen ? "collapse_fallen" : "collapse_standing"};
		for (const TileWrite &wr : fallen ? col.fallen : col.standing) {
			c->tiles[wr.index].material = wr.material;
			const int64_t gx = coord.x * CELL_TILES + wr.index % CELL_TILES;
			const int64_t gy = coord.y * CELL_TILES + wr.index / CELL_TILES;
			change.x0 = std::min(change.x0, gx);
			change.y0 = std::min(change.y0, gy);
			change.x1 = std::max(change.x1, gx);
			change.y1 = std::max(change.y1, gy);
		}
		rebuild_fields_around(coord);
		changes_.push_back(change);
		return true;
	}
	return false;
}

std::vector<TileChange> MineMap::take_changes() {
	std::vector<TileChange> out;
	out.swap(changes_);
	return out;
}

MineMap::Window MineMap::window_around(Coord centre, int64_t radius, bool doors_open) const {
	Window win;
	win.x0 = centre.x - radius;
	win.y0 = centre.y - radius;
	win.w = 2 * radius + 1;
	win.pass.assign(static_cast<size_t>(win.w * win.w), 2);
	const Coord c0 = cell_of({win.x0, win.y0});
	const Coord c1 = cell_of({win.x0 + win.w - 1, win.y0 + win.w - 1});
	for (int64_t cy = c0.y; cy <= c1.y; cy++) {
		for (int64_t cx = c0.x; cx <= c1.x; cx++) {
			const Cell *c = cell({cx, cy});
			if (c == nullptr) {
				continue;
			}
			const int64_t tx0 = std::max(cx * CELL_TILES, win.x0);
			const int64_t ty0 = std::max(cy * CELL_TILES, win.y0);
			const int64_t tx1 = std::min(cx * CELL_TILES + CELL_TILES - 1, win.x0 + win.w - 1);
			const int64_t ty1 = std::min(cy * CELL_TILES + CELL_TILES - 1, win.y0 + win.w - 1);
			for (int64_t ty = ty0; ty <= ty1; ty++) {
				for (int64_t tx = tx0; tx <= tx1; tx++) {
					const Tile &t = c->tiles[Cell::index_of(tx - cx * CELL_TILES, ty - cy * CELL_TILES)];
					const TileMaterial m = static_cast<TileMaterial>(t.material);
					const bool barrier = m == TileMaterial::STEEL || m == TileMaterial::WOODEN_DOOR;
					const bool walkable = (doors_open && barrier) || !materials.get(MaterialTable::effective(m, t.state)).solid;
					win.pass[static_cast<size_t>((ty - win.y0) * win.w + (tx - win.x0))] = walkable ? 1 : 0;
				}
			}
		}
	}
	return win;
}

template <typename Visit>
void MineMap::walk(Coord from, int64_t max_milli, bool doors_open, Visit visit, bool &touched_unloaded) const {
	// Dijkstra over a dense window. Heap keys pack (distance, y, x) so ties settle in global
	// tile order; distances stay below 2^24 thousandths and window indices below 2^20.
	const int64_t radius = max_milli / std::min(orthogonal_cost_milli, diagonal_cost_milli) + 1;
	const Window win = window_around(from, radius, doors_open);
	const int64_t w = win.w;
	const int64_t start = radius * w + radius;
	if (win.pass[static_cast<size_t>(start)] != 1) {
		touched_unloaded = win.pass[static_cast<size_t>(start)] == 2;
		return;
	}
	std::vector<int32_t> best(win.pass.size(), INT32_MAX);
	std::vector<uint64_t> heap;
	auto push = [&](int64_t d, int64_t idx) {
		heap.push_back((static_cast<uint64_t>(d) << 20) | static_cast<uint64_t>(idx));
		std::push_heap(heap.begin(), heap.end(), std::greater<uint64_t>());
	};
	best[static_cast<size_t>(start)] = 0;
	push(0, start);
	const int64_t steps[8][2] = {{1, 0}, {-1, 0}, {0, 1}, {0, -1}, {1, 1}, {1, -1}, {-1, 1}, {-1, -1}};
	while (!heap.empty()) {
		std::pop_heap(heap.begin(), heap.end(), std::greater<uint64_t>());
		const uint64_t key = heap.back();
		heap.pop_back();
		const int64_t d = static_cast<int64_t>(key >> 20);
		const int64_t idx = static_cast<int64_t>(key & 0xFFFFF);
		if (d > best[static_cast<size_t>(idx)]) {
			continue;
		}
		const int64_t x = idx % w;
		const int64_t y = idx / w;
		if (!visit(Coord{win.x0 + x, win.y0 + y}, d)) {
			return;
		}
		for (const auto &step : steps) {
			const int64_t nx = x + step[0];
			const int64_t ny = y + step[1];
			if (nx < 0 || ny < 0 || nx >= w || ny >= w) {
				continue;
			}
			const int64_t nidx = ny * w + nx;
			const uint8_t pass = win.pass[static_cast<size_t>(nidx)];
			if (pass == 2) {
				touched_unloaded = true;
				continue;
			}
			if (pass == 0) {
				continue;
			}
			const bool diagonal = step[0] != 0 && step[1] != 0;
			if (diagonal && (win.pass[static_cast<size_t>(y * w + nx)] != 1 || win.pass[static_cast<size_t>(ny * w + x)] != 1)) {
				continue; // no corner cutting past solid (or unloaded) tiles
			}
			const int64_t nd = d + (diagonal ? diagonal_cost_milli : orthogonal_cost_milli);
			if (nd > max_milli || nd >= best[static_cast<size_t>(nidx)]) {
				continue;
			}
			best[static_cast<size_t>(nidx)] = static_cast<int32_t>(nd);
			push(nd, nidx);
		}
	}
}

PathResult MineMap::path_distance(Coord from, Coord to, int64_t max_milli, bool doors_open) const {
	PathResult result;
	bool reached = false;
	walk(from, max_milli, doors_open, [&](Coord here, int64_t d) -> bool {
		if (here == to) {
			result.distance_milli = d;
			reached = true;
			return false;
		}
		return true;
	}, result.touched_unloaded);
	result.hit_max = !reached;
	return result;
}

size_t MineMap::flood_count(Coord from, int64_t max_milli, bool doors_open) const {
	size_t count = 0;
	bool touched = false;
	walk(from, max_milli, doors_open, [&](Coord, int64_t) -> bool {
		count++;
		return true;
	}, touched);
	return count;
}

std::optional<Coord> MineMap::nearest_open_tile(double x, double y, const std::set<Coord> &exclude, int64_t max_radius) const {
	const Coord centre{static_cast<int64_t>(std::floor(x)), static_cast<int64_t>(std::floor(y))};
	std::optional<Coord> best;
	double best_d2 = 0.0;
	for (int64_t ty = centre.y - max_radius; ty <= centre.y + max_radius; ty++) {
		for (int64_t tx = centre.x - max_radius; tx <= centre.x + max_radius; tx++) {
			const Coord t{tx, ty};
			if (exclude.count(t) != 0 || !is_walkable(t)) {
				continue;
			}
			const double dx = tx + 0.5 - x;
			const double dy = ty + 0.5 - y;
			const double d2 = dx * dx + dy * dy;
			if (!best || d2 < best_d2) { // row-major scan: the first of equals is the lowest (y, x)
				best = t;
				best_d2 = d2;
			}
		}
	}
	return best;
}

} // namespace lb::core::world

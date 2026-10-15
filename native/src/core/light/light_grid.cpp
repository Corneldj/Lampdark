#include "core/light/light_grid.h"

#include "core/generated/hash_domains.h"
#include "core/rng/hash.h"

#include <algorithm>
#include <chrono>
#include <cmath>

namespace lb::core::light {

using lb::core::world::CELL_TILES;
using lb::core::world::Cell;

namespace {

int64_t now_usec() {
	return std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now().time_since_epoch()).count();
}

} // namespace

std::optional<SourceDesc> LightGrid::source(uint32_t id) const {
	auto it = sources_.find(id);
	if (it == sources_.end()) {
		return std::nullopt;
	}
	return it->second.desc;
}

std::vector<uint32_t> LightGrid::source_ids() const {
	std::vector<uint32_t> out;
	out.reserve(sources_.size());
	for (const auto &entry : sources_) {
		out.push_back(entry.first);
	}
	return out;
}

double LightGrid::radius_mult(uint32_t id) const {
	auto it = sources_.find(id);
	return it == sources_.end() ? 1.0 : it->second.radius_mult;
}

std::vector<LightGrid::OwnLight> LightGrid::owned_lights(uint32_t owner) const {
	std::vector<OwnLight> out;
	if (owner == 0) {
		return out;
	}
	for (const auto &[id, s] : sources_) {
		if (s.desc.owner == owner && s.desc.shape == Shape::POINT && s.desc.radius * s.radius_mult > 0.0) {
			out.push_back(OwnLight{s.desc.x, s.desc.y, s.desc.radius * s.radius_mult});
		}
	}
	return out;
}

std::pair<double, double> LightGrid::velocity(uint32_t id) const {
	auto it = sources_.find(id);
	return it == sources_.end() ? std::pair<double, double>{0.0, 0.0} : std::pair<double, double>{it->second.vx, it->second.vy};
}

uint32_t LightGrid::add_source(const SourceDesc &desc) {
	Source s;
	s.id = next_id_++;
	s.desc = desc;
	s.prev_x = desc.x;
	s.prev_y = desc.y;
	sources_[s.id] = std::move(s);
	events_.push_back({LightEvent::Type::ADDED, sources_[next_id_ - 1].id, desc.kind, "", desc.x, desc.y});
	sources_[next_id_ - 1].dirty = true;
	return next_id_ - 1;
}

bool LightGrid::update_point(uint32_t id, double x, double y, double radius, double peak) {
	auto it = sources_.find(id);
	if (it == sources_.end()) {
		return false;
	}
	Source &s = it->second;
	const bool moved = s.desc.x != x || s.desc.y != y;
	const bool radius_changed = s.desc.radius != radius;
	const bool peak_changed = s.desc.peak != peak;
	if (!moved && !radius_changed && !peak_changed) {
		return true;
	}
	s.desc.x = x;
	s.desc.y = y;
	s.desc.radius = radius;
	s.desc.peak = peak;
	if (radius_changed || peak_changed) {
		events_.push_back({LightEvent::Type::CHANGED, id, s.desc.kind, radius_changed ? "radius" : "peak", x, y});
	}
	mark_dirty(s);
	return true;
}

bool LightGrid::set_radius_modifier(uint32_t id, double multiplier, const std::string &cause) {
	auto it = sources_.find(id);
	if (it == sources_.end()) {
		return false;
	}
	Source &s = it->second;
	if (s.radius_mult == multiplier) {
		return true;
	}
	s.radius_mult = multiplier;
	events_.push_back({LightEvent::Type::CHANGED, id, s.desc.kind, cause, s.desc.x, s.desc.y});
	mark_dirty(s);
	return true;
}

bool LightGrid::set_flags(uint32_t id, uint32_t flags) {
	auto it = sources_.find(id);
	if (it == sources_.end()) {
		return false;
	}
	it->second.desc.flags = flags;
	return true;
}

bool LightGrid::remove_source(uint32_t id) {
	auto it = sources_.find(id);
	if (it == sources_.end()) {
		return false;
	}
	if (!it->second.box.empty()) {
		dirty_boxes_.push_back(it->second.box);
	}
	events_.push_back({LightEvent::Type::REMOVED, id, it->second.desc.kind, "", it->second.desc.x, it->second.desc.y});
	sources_.erase(it);
	return true;
}

void LightGrid::mark_dirty(Source &s) {
	if (!s.box.empty()) {
		dirty_boxes_.push_back(s.box);
	}
	s.dirty = true;
}

void LightGrid::on_cell_loaded(Coord cell) {
	cells_[cell] = CellLight{};
	const Box cell_box{cell.x * CELL_TILES, cell.y * CELL_TILES, CELL_TILES, CELL_TILES};
	dirty_boxes_.push_back(cell_box);
	for (auto &entry : sources_) {
		mark_dirty(entry.second); // its reach may now extend into the new cell
	}
}

void LightGrid::on_cell_unloading(Coord cell) {
	cells_.erase(cell);
	for (auto &entry : sources_) {
		Source &s = entry.second;
		const Box cell_box{cell.x * CELL_TILES, cell.y * CELL_TILES, CELL_TILES, CELL_TILES};
		const bool overlap = !(s.box.x0 + s.box.w <= cell_box.x0 || cell_box.x0 + cell_box.w <= s.box.x0 ||
				s.box.y0 + s.box.h <= cell_box.y0 || cell_box.y0 + cell_box.h <= s.box.y0);
		if (overlap || s.box.empty()) {
			mark_dirty(s);
		}
	}
}

void LightGrid::on_tiles_changed(int64_t x0, int64_t y0, int64_t x1, int64_t y1) {
	for (auto &entry : sources_) {
		Source &s = entry.second;
		// Its box, widened by one tile: an opening on its rim can let light in.
		const bool overlap = !(s.box.x0 + s.box.w + 1 <= x0 || x1 + 1 <= s.box.x0 - 1 ||
				s.box.y0 + s.box.h + 1 <= y0 || y1 + 1 <= s.box.y0 - 1);
		if (overlap || s.desc.shape == Shape::SPILL || s.box.empty()) {
			mark_dirty(s);
		}
	}
}

void LightGrid::begin_tick(double tick_hz) {
	std::vector<uint32_t> expired;
	for (auto &entry : sources_) {
		Source &s = entry.second;
		s.vx = (s.desc.x - s.prev_x) * tick_hz;
		s.vy = (s.desc.y - s.prev_y) * tick_hz;
		s.prev_x = s.desc.x;
		s.prev_y = s.desc.y;
		if (s.desc.lifetime_ticks > 0 && s.shown_this_tick) {
			s.ticks_shown++;
			s.shown_this_tick = false;
			if (s.ticks_shown >= s.desc.lifetime_ticks) {
				expired.push_back(s.id);
			}
		}
	}
	for (uint32_t id : expired) {
		remove_source(id);
	}
}

bool LightGrid::blocks(Coord tile) const {
	return !mine_.tile_at(tile).has_value() || mine_.is_opaque(tile);
}

void LightGrid::contribution(const Source &s, Box &box, std::vector<uint16_t> &out) const {
	box = Box{};
	out.clear();
	const SourceDesc &d = s.desc;
	auto put = [&](Coord t, int64_t milli) {
		if (milli <= 0 || !box.contains(t) || !mine_.tile_at(t).has_value()) {
			return;
		}
		uint16_t &slot = out[static_cast<size_t>((t.y - box.y0) * box.w + (t.x - box.x0))];
		slot = static_cast<uint16_t>(std::max<int64_t>(slot, std::min<int64_t>(milli, 65535)));
	};
	switch (d.shape) {
		case Shape::POINT: {
			const double radius = d.radius * s.radius_mult;
			const Coord origin{static_cast<int64_t>(std::floor(d.x)), static_cast<int64_t>(std::floor(d.y))};
			if (radius <= 0.0 || blocks(origin)) {
				return;
			}
			const int64_t r = static_cast<int64_t>(std::ceil(radius)) + 1;
			box = {origin.x - r, origin.y - r, 2 * r + 1, 2 * r + 1};
			out.assign(static_cast<size_t>(box.w * box.h), 0);
			shadowcast(origin, r, [&](Coord t) { return blocks(t); }, [&](Coord t) {
				const double dx = t.x + 0.5 - d.x;
				const double dy = t.y + 0.5 - d.y;
				put(t, falloff_milli(std::sqrt(dx * dx + dy * dy), radius, d.peak, params));
			});
			return;
		}
		case Shape::AREA: {
			if (d.tiles.empty()) {
				return;
			}
			int64_t x0 = INT64_MAX, y0 = INT64_MAX, x1 = INT64_MIN, y1 = INT64_MIN;
			for (const Coord &t : d.tiles) {
				x0 = std::min(x0, t.x);
				y0 = std::min(y0, t.y);
				x1 = std::max(x1, t.x);
				y1 = std::max(y1, t.y);
			}
			box = {x0, y0, x1 - x0 + 1, y1 - y0 + 1};
			out.assign(static_cast<size_t>(box.w * box.h), 0);
			for (const Coord &t : d.tiles) {
				put(t, std::llround(d.peak * static_cast<double>(params.scale)));
			}
			return;
		}
		case Shape::SPOT: {
			box = {d.spot.x, d.spot.y, 1, 1};
			out.assign(1, 0);
			put(d.spot, std::llround(d.peak * static_cast<double>(params.scale)));
			return;
		}
		case Shape::SPILL: {
			if (d.tiles.empty()) {
				return;
			}
			for (const Coord &door : d.tiles) {
				if (blocks(door)) {
					return; // a shut gate spills nothing
				}
			}
			const int64_t r = static_cast<int64_t>(std::ceil(d.radius)) + 1;
			int64_t x0 = INT64_MAX, y0 = INT64_MAX, x1 = INT64_MIN, y1 = INT64_MIN;
			for (const Coord &t : d.tiles) {
				x0 = std::min(x0, t.x - r);
				y0 = std::min(y0, t.y - r);
				x1 = std::max(x1, t.x + r);
				y1 = std::max(y1, t.y + r);
			}
			box = {x0, y0, x1 - x0 + 1, y1 - y0 + 1};
			out.assign(static_cast<size_t>(box.w * box.h), 0);
			for (const Coord &door : d.tiles) {
				shadowcast(door, r, [&](Coord t) { return blocks(t); }, [&](Coord t) {
					const int64_t depth = (t.x - door.x) * d.dir.x + (t.y - door.y) * d.dir.y;
					if (depth < 1) {
						return; // only the half-plane outside the doorway
					}
					const double dist = static_cast<double>(depth) - 0.5;
					if (dist > d.radius) {
						return;
					}
					const double v = d.peak + (d.end_value - d.peak) * (dist / d.radius);
					put(t, std::llround(v * static_cast<double>(params.scale)));
				});
			}
			return;
		}
	}
}

TileLight *LightGrid::tile_mut(Coord tile) {
	auto it = cells_.find(lb::core::world::cell_of(tile));
	if (it == cells_.end()) {
		return nullptr;
	}
	const Coord l = lb::core::world::local_of(tile);
	return &it->second.tiles[static_cast<size_t>(Cell::index_of(l.x, l.y))];
}

TileLight LightGrid::sum_at(Coord tile) const {
	TileLight out;
	int64_t total = 0;
	int64_t best = 0;
	for (const auto &entry : sources_) {
		const Source &s = entry.second;
		if (!s.box.contains(tile)) {
			continue;
		}
		const int64_t v = s.contrib[static_cast<size_t>((tile.y - s.box.y0) * s.box.w + (tile.x - s.box.x0))];
		if (v <= 0) {
			continue;
		}
		total += v;
		if (v > best) {
			best = v;
			out.colour = s.desc.colour;
			out.brightest = s.id;
		}
	}
	out.value = std::min<int64_t>(total, std::llround(params.cap * static_cast<double>(params.scale)));
	return out;
}

void LightGrid::resum(const Box &box) {
	for (int64_t y = box.y0; y < box.y0 + box.h; y++) {
		for (int64_t x = box.x0; x < box.x0 + box.w; x++) {
			if (TileLight *t = tile_mut({x, y})) {
				*t = sum_at({x, y});
			}
		}
	}
}

void LightGrid::update() {
	const int64_t start = now_usec();
	for (auto &entry : sources_) {
		Source &s = entry.second;
		s.shown_this_tick = true;
		if (!s.dirty) {
			continue;
		}
		contribution(s, s.box, s.contrib);
		if (!s.box.empty()) {
			dirty_boxes_.push_back(s.box);
		}
		s.dirty = false;
	}
	std::vector<Box> boxes;
	boxes.swap(dirty_boxes_);
	for (const Box &b : boxes) {
		resum(b);
	}
	last_update_usec = now_usec() - start;
}

int64_t LightGrid::value(Coord tile) const {
	return tile_light(tile).value;
}

int64_t LightGrid::value_at(double x, double y) const {
	return value({static_cast<int64_t>(std::floor(x)), static_cast<int64_t>(std::floor(y))});
}

TileLight LightGrid::tile_light(Coord tile) const {
	auto it = cells_.find(lb::core::world::cell_of(tile));
	if (it == cells_.end()) {
		return {};
	}
	const Coord l = lb::core::world::local_of(tile);
	return it->second.tiles[static_cast<size_t>(Cell::index_of(l.x, l.y))];
}

int64_t LightGrid::value_from(Coord tile, const std::vector<uint32_t> &owners) const {
	if (cells_.count(lb::core::world::cell_of(tile)) == 0) {
		return 0;
	}
	int64_t total = 0;
	for (const auto &entry : sources_) {
		const Source &s = entry.second;
		if (!s.box.contains(tile) || std::find(owners.begin(), owners.end(), s.desc.owner) == owners.end()) {
			continue;
		}
		total += s.contrib[static_cast<size_t>((tile.y - s.box.y0) * s.box.w + (tile.x - s.box.x0))];
	}
	return std::min<int64_t>(total, std::llround(params.cap * static_cast<double>(params.scale)));
}

std::pair<int64_t, uint32_t> LightGrid::value_excluding(Coord tile, const std::vector<uint32_t> &excluded) const {
	if (cells_.count(lb::core::world::cell_of(tile)) == 0) {
		return {0, 0};
	}
	if (excluded.empty()) {
		const TileLight t = tile_light(tile);
		return {t.value, t.brightest};
	}
	int64_t total = 0;
	int64_t best = 0;
	uint32_t best_id = 0;
	for (const auto &entry : sources_) {
		const Source &s = entry.second;
		if (!s.box.contains(tile) || std::find(excluded.begin(), excluded.end(), entry.first) != excluded.end()) {
			continue;
		}
		const int64_t c = s.contrib[static_cast<size_t>((tile.y - s.box.y0) * s.box.w + (tile.x - s.box.x0))];
		total += c;
		if (c > best || (c == best && c > 0 && entry.first < best_id)) {
			best = c;
			best_id = entry.first;
		}
	}
	return {std::min<int64_t>(total, std::llround(params.cap * static_cast<double>(params.scale))), best_id};
}

std::vector<Coord> LightGrid::tiles_at_or_above(int64_t threshold, int64_t x0, int64_t y0, int64_t x1, int64_t y1) const {
	std::vector<Coord> out;
	for (int64_t y = y0; y <= y1; y++) {
		for (int64_t x = x0; x <= x1; x++) {
			if (value({x, y}) >= threshold) {
				out.push_back({x, y});
			}
		}
	}
	return out;
}

std::vector<uint8_t> LightGrid::light_bytes(int64_t x0, int64_t y0, int64_t w, int64_t h) const {
	std::vector<uint8_t> out;
	if (w <= 0 || h <= 0) {
		return out;
	}
	out.reserve(static_cast<size_t>(w * h));
	for (int64_t y = y0; y < y0 + h; y++) {
		for (int64_t x = x0; x < x0 + w; x++) {
			out.push_back(quantise_u8(value({x, y})));
		}
	}
	return out;
}

std::vector<uint32_t> LightGrid::flame_sources(double x0, double y0, double x1, double y1) const {
	std::vector<uint32_t> out;
	for (const auto &entry : sources_) {
		const SourceDesc &d = entry.second.desc;
		if ((d.flags & flag::FLAME) != 0 && d.x >= x0 && d.x <= x1 && d.y >= y0 && d.y <= y1) {
			out.push_back(entry.first);
		}
	}
	return out;
}

std::vector<LightEvent> LightGrid::take_events() {
	std::vector<LightEvent> out;
	out.swap(events_);
	return out;
}

std::map<Coord, std::array<int64_t, CELL_AREA>> LightGrid::current_values() const {
	std::map<Coord, std::array<int64_t, CELL_AREA>> out;
	for (const auto &entry : cells_) {
		std::array<int64_t, CELL_AREA> values{};
		for (size_t i = 0; i < static_cast<size_t>(CELL_AREA); i++) {
			values[i] = entry.second.tiles[i].value;
		}
		out[entry.first] = values;
	}
	return out;
}

std::map<Coord, std::array<int64_t, CELL_AREA>> LightGrid::reference_values() const {
	// Fresh contributions for every source, summed into every loaded tile.
	std::vector<std::pair<Box, std::vector<uint16_t>>> fresh;
	for (const auto &entry : sources_) {
		Box box;
		std::vector<uint16_t> contrib;
		contribution(entry.second, box, contrib);
		fresh.emplace_back(box, std::move(contrib));
	}
	const int64_t cap = std::llround(params.cap * static_cast<double>(params.scale));
	std::map<Coord, std::array<int64_t, CELL_AREA>> out;
	for (const auto &entry : cells_) {
		std::array<int64_t, CELL_AREA> values{};
		for (int64_t ly = 0; ly < CELL_TILES; ly++) {
			for (int64_t lx = 0; lx < CELL_TILES; lx++) {
				const Coord t{entry.first.x * CELL_TILES + lx, entry.first.y * CELL_TILES + ly};
				int64_t total = 0;
				for (const auto &f : fresh) {
					if (f.first.contains(t)) {
						total += f.second[static_cast<size_t>((t.y - f.first.y0) * f.first.w + (t.x - f.first.x0))];
					}
				}
				values[static_cast<size_t>(Cell::index_of(lx, ly))] = std::min(total, cap);
			}
		}
		out[entry.first] = values;
	}
	return out;
}

uint64_t LightGrid::digest() const {
	std::vector<int64_t> keys;
	for (const auto &entry : cells_) {
		keys.push_back(entry.first.x);
		keys.push_back(entry.first.y);
		for (const TileLight &t : entry.second.tiles) {
			keys.push_back(t.value * 16 + static_cast<int64_t>(t.colour));
		}
	}
	return hash_u64(0, hash_domain::LIGHT_GRID_DIGEST, keys.data(), keys.size());
}

} // namespace lb::core::light

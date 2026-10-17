#include "core/gen/validator.h"

#include <algorithm>

namespace lb::core::gen {

using lb::core::world::Cell;
using lb::core::world::CELL_TILES;
using lb::core::world::Coord;
using lb::core::world::TileMaterial;

namespace {

// The 3x3 window's side in tiles.
constexpr int64_t WINDOW = 3 * CELL_TILES;

Verdict fail(Check check, Coord tile, std::string detail) {
	Verdict v;
	v.check = check;
	v.tile = tile;
	v.detail = std::move(detail);
	return v;
}

int64_t sq(int64_t v) { return v * v; }

int64_t dist2(Coord a, Coord b) { return sq(a.x - b.x) + sq(a.y - b.y); }

bool is_gas(const Placement &x) { return x.kind == PlacedKind::FIREDAMP || x.kind == PlacedKind::BLACKDAMP; }

bool is_trap(const Placement &x) {
	return x.kind == PlacedKind::MAN_TRAP || x.kind == PlacedKind::STAPLE_PIT || x.kind == PlacedKind::SUMP_MUD;
}

// A required item: a point of interest's contents or the plan's own (the revolver, its boxes).
bool is_required(const Placement &x) { return x.kind == PlacedKind::ITEM && (x.source == "poi" || x.source == "plan"); }

bool passable(uint8_t material) {
	const TileMaterial m = static_cast<TileMaterial>(material);
	return m == TileMaterial::FLOOR || m == TileMaterial::STEEL || m == TileMaterial::WOODEN_DOOR;
}

// A collapse placement's tiles: its alternate's in the cell's layout, else its box's.
std::vector<Coord> tiles_of_collapse(const PlacementContext &c, const Placement &x) {
	std::vector<Coord> out;
	if (c.layout) {
		out = collapse_tiles(*c.layout, x.collapse);
	}
	if (out.empty()) {
		for (int64_t y = x.tile.y; y < x.tile.y + std::max(1, x.h); y++) {
			for (int64_t t = x.tile.x; t < x.tile.x + std::max(1, x.w); t++) {
				out.push_back({t, y});
			}
		}
	}
	return out;
}

// The window index of a world tile, or -1 outside it.
int64_t window_index(const PlacementContext &c, Coord t) {
	const int64_t x = t.x - (c.cell.x - 1) * CELL_TILES;
	const int64_t y = t.y - (c.cell.y - 1) * CELL_TILES;
	return x < 0 || y < 0 || x >= WINDOW || y >= WINDOW ? -1 : y * WINDOW + x;
}

bool is_base_camp_tile(Coord t) { return lb::core::world::cell_of(t) == Coord{0, 0}; }

// Rule 1's path test: the first phone, point-of-interest door or base camp tile fewer than
// `limit` steps by path (4-connected over the window's floor, doors open, the target itself
// stepped onto last however solid) from any of `from`; nullopt if none is that near.
std::optional<Coord> site_by_path(const PlacementContext &c, const std::vector<Coord> &from, int64_t limit) {
	auto target = [&](Coord t) {
		return is_base_camp_tile(t) || std::find(c.phones.begin(), c.phones.end(), t) != c.phones.end() ||
				std::find(c.doors.begin(), c.doors.end(), t) != c.doors.end();
	};
	// The window's distances, stamped per search so nothing is cleared between them.
	thread_local std::vector<uint32_t> stamp(static_cast<size_t>(WINDOW * WINDOW), 0);
	thread_local std::vector<int32_t> dist(static_cast<size_t>(WINDOW * WINDOW), 0);
	thread_local uint32_t search = 0;
	if (++search == 0) {
		std::fill(stamp.begin(), stamp.end(), 0);
		search = 1;
	}
	std::vector<Coord> q;
	q.reserve(64);
	for (const Coord &t : from) {
		if (target(t)) {
			return t;
		}
		const int64_t i = window_index(c, t);
		if (i >= 0 && stamp[static_cast<size_t>(i)] != search) {
			stamp[static_cast<size_t>(i)] = search;
			dist[static_cast<size_t>(i)] = 0;
			q.push_back(t);
		}
	}
	for (size_t head = 0; head < q.size(); head++) {
		const Coord t = q[head];
		const int32_t d = dist[static_cast<size_t>(window_index(c, t))];
		if (d + 1 >= limit) {
			continue;
		}
		const Coord next[4] = {{t.x + 1, t.y}, {t.x - 1, t.y}, {t.x, t.y + 1}, {t.x, t.y - 1}};
		for (const Coord &n : next) {
			if (target(n)) {
				return n;
			}
			const int64_t i = window_index(c, n);
			if (i < 0 || stamp[static_cast<size_t>(i)] == search || c.walk[static_cast<size_t>(i)] == 0) {
				continue;
			}
			stamp[static_cast<size_t>(i)] = search;
			dist[static_cast<size_t>(i)] = d + 1;
			q.push_back(n);
		}
	}
	return std::nullopt;
}

// The first tile of `tiles` that `x` covers.
std::optional<Coord> covered(const Placement &x, const std::vector<Coord> &tiles) {
	for (const Coord &t : tiles) {
		if (x.covers(t)) {
			return t;
		}
	}
	return std::nullopt;
}

// `x` against the context and the placements before it (`earlier`, all kept): the first check
// the pair or `x` alone breaks.
Verdict check_one(const PlacementContext &c, const std::vector<Placement> &earlier, const Placement &x) {
	const char *kind = placed_kind_name(x.kind);
	if (c.facts.base_camp || is_base_camp_tile(x.tile)) {
		return fail(Check::CLEAR_GROUND, x.tile, std::string(kind) + " in base camp");
	}
	if ((is_gas(x) || is_trap(x)) && c.facts.ring <= 0) {
		return fail(Check::NEAR_HOME, x.tile, std::string(kind) + " in ring 0");
	}
	if (is_gas(x) && c.facts.spine) {
		return fail(Check::GAS, x.tile, std::string(kind) + " on a spine");
	}
	if (x.kind == PlacedKind::AIR_DOOR) {
		for (const Coord &t : c.arch) {
			if (x.covers(t)) {
				return fail(Check::ARCHES, t, "an air door on the arch past base camp's gate");
			}
		}
	}
	if (x.kind == PlacedKind::COLLAPSE) {
		if (c.facts.spine) {
			return fail(Check::SPINE_COLLAPSE, x.tile, "a collapse point armed on a spine cell");
		}
		const std::vector<Coord> tiles = tiles_of_collapse(c, x);
		const int64_t camp2 = sq(c.collapse_min_from_basecamp);
		for (const Coord &t : tiles) {
			const Coord near{std::clamp<int64_t>(t.x, 0, CELL_TILES - 1), std::clamp<int64_t>(t.y, 0, CELL_TILES - 1)};
			if (dist2(t, near) < camp2) {
				return fail(Check::COLLAPSE_SPACING, t, "a collapse point within " + std::to_string(c.collapse_min_from_basecamp) + " tiles of base camp");
			}
		}
		const int64_t apart2 = sq(c.collapse_min_spacing);
		auto too_near = [&](const std::vector<Coord> &other) -> std::optional<Coord> {
			for (const Coord &t : tiles) {
				for (const Coord &u : other) {
					if (dist2(t, u) < apart2) {
						return t;
					}
				}
			}
			return std::nullopt;
		};
		for (const std::vector<Coord> &o : c.neighbour_collapses) {
			if (std::optional<Coord> t = too_near(o)) {
				return fail(Check::COLLAPSE_SPACING, *t, "collapse points under " + std::to_string(c.collapse_min_spacing) + " tiles apart");
			}
		}
		for (const Placement &y : earlier) {
			if (y.kind != PlacedKind::COLLAPSE) {
				continue;
			}
			if (std::optional<Coord> t = too_near(tiles_of_collapse(c, y))) {
				return fail(Check::COLLAPSE_SPACING, *t, "collapse points under " + std::to_string(c.collapse_min_spacing) + " tiles apart");
			}
		}
		if (std::optional<Coord> s = site_by_path(c, tiles, c.collapse_min_from_sites)) {
			return fail(Check::NEAR_HOME, *s, "a collapse point under " + std::to_string(c.collapse_min_from_sites) + " tiles by path of a pit phone, a point of interest's door or base camp");
		}
		for (const Placement &y : earlier) {
			if (std::optional<Coord> t = covered(y, tiles)) {
				return fail(Check::CLEAR_GROUND, *t, std::string(placed_kind_name(y.kind)) + " on a collapse point's tiles");
			}
		}
	} else {
		for (const Placement &y : earlier) {
			if (y.kind == PlacedKind::COLLAPSE) {
				if (std::optional<Coord> t = covered(x, tiles_of_collapse(c, y))) {
					return fail(Check::CLEAR_GROUND, *t, std::string(kind) + " on a collapse point's tiles");
				}
			}
		}
	}
	for (const Placement &y : earlier) {
		const bool x_over_y = is_gas(x) && x.covers(y.tile);
		const bool y_over_x = is_gas(y) && y.covers(x.tile);
		if ((x_over_y && is_required(y)) || (y_over_x && is_required(x))) {
			return fail(Check::GAS, x_over_y ? y.tile : x.tile, "a required item in gas");
		}
		if ((x_over_y && x.kind == PlacedKind::BLACKDAMP && y.kind == PlacedKind::REMAINS) ||
				(y_over_x && y.kind == PlacedKind::BLACKDAMP && x.kind == PlacedKind::REMAINS)) {
			return fail(Check::GAS, x_over_y ? y.tile : x.tile, "remains in blackdamp");
		}
	}
	return {};
}

} // namespace

PlacementContext placement_context(const PlacementWorld &world, const PlacementParams &pp, const ValidatorParams &vp, Coord cell) {
	PlacementContext c;
	c.cell = cell;
	c.facts = world.facts(cell);
	c.layout = world.layout(cell);
	c.collapse_min_from_sites = pp.collapse_min_from_sites;
	c.collapse_min_spacing = pp.collapse_min_spacing;
	c.collapse_min_from_basecamp = pp.collapse_min_from_basecamp;
	c.walk.assign(static_cast<size_t>(WINDOW * WINDOW), 0);
	std::set<Coord> doors;
	for (int64_t dy = -1; dy <= 1; dy++) {
		for (int64_t dx = -1; dx <= 1; dx++) {
			const Coord n{cell.x + dx, cell.y + dy};
			const bool middle = dx == 0 && dy == 0;
			const std::optional<Layout> nl = middle ? c.layout : world.layout(n);
			if (nl && !nl->base_camp) {
				for (int64_t y = 0; y < CELL_TILES; y++) {
					for (int64_t x = 0; x < CELL_TILES; x++) {
						const size_t at = static_cast<size_t>(((dy + 1) * CELL_TILES + y) * WINDOW + (dx + 1) * CELL_TILES + x);
						c.walk[at] = passable(nl->cell.tiles[static_cast<size_t>(Cell::index_of(x, y))].material) ? 1 : 0;
					}
				}
			}
			for (const Coord &t : phone_tiles(world, pp, n)) {
				c.phones.push_back(t);
			}
			for (const Coord &t : poi_door_tiles(world, n)) {
				if (doors.insert(t).second) {
					c.doors.push_back(t);
				}
			}
			if (!middle) {
				std::vector<Coord> armed = armed_collapse_tiles(world, pp, n);
				if (!armed.empty()) {
					c.neighbour_collapses.push_back(std::move(armed));
				}
			}
		}
	}
	if (c.layout) {
		for (const Coord &t : gate_arch_tiles(*c.layout, vp)) {
			c.arch.insert(t);
		}
	}
	return c;
}

Verdict validate_placement(const PlacementContext &ctx, const std::vector<Placement> &list) {
	std::vector<Placement> earlier;
	earlier.reserve(list.size());
	for (const Placement &x : list) {
		const Verdict v = check_one(ctx, earlier, x);
		if (!v.ok()) {
			return v;
		}
		earlier.push_back(x);
	}
	return {};
}

std::vector<Placement> strict_placement(const PlacementContext &ctx, const std::vector<Placement> &list, int32_t *dropped) {
	std::vector<Placement> kept;
	std::vector<int32_t> now(list.size(), -1);
	int32_t gone = 0;
	for (size_t i = 0; i < list.size(); i++) {
		Placement x = list[i];
		if (x.with >= 0) {
			// What a man carried goes with him (and never rides on one placed after it).
			if (static_cast<size_t>(x.with) >= i || now[static_cast<size_t>(x.with)] < 0) {
				gone++;
				continue;
			}
			x.with = now[static_cast<size_t>(x.with)];
		}
		if (!check_one(ctx, kept, x).ok()) {
			gone++;
			continue;
		}
		now[i] = static_cast<int32_t>(kept.size());
		kept.push_back(x);
	}
	if (dropped != nullptr) {
		*dropped = gone;
	}
	return kept;
}

PlacedCell place_validated(const PlacementWorld &world, const PlacementParams &pp, const ValidatorParams &vp, Coord cell) {
	PlacedCell out;
	if (cell == Coord{0, 0}) {
		return out;
	}
	const std::optional<Layout> l = world.layout(cell);
	if (!l || l->base_camp) {
		return out;
	}
	const PlacementContext c = placement_context(world, pp, vp, cell);
	std::vector<Placement> first;
	for (int32_t r = 0; r <= std::max<int32_t>(0, vp.max_retries); r++) {
		std::vector<Placement> list = place_cell(world, pp, cell, r);
		const Verdict v = validate_placement(c, list);
		if (v.ok()) {
			out.list = std::move(list);
			out.retry = r;
			return out;
		}
		if (r == 0) {
			first = list;
		}
		// The validator never fails a cell twice for one reason: the second time, strict mode.
		const bool again = !out.failures.empty() && v.same(out.failures.back());
		out.failures.push_back(v);
		if (again) {
			break;
		}
	}
	out.strict = true;
	out.list = strict_placement(c, first, &out.dropped);
	return out;
}

} // namespace lb::core::gen

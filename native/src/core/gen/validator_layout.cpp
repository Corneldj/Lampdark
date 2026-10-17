#include "core/gen/validator.h"

#include "core/gen/stub_fill.h"

#include <deque>

namespace lb::core::gen {

using lb::core::world::AnchorType;
using lb::core::world::Cell;
using lb::core::world::CELL_TILES;
using lb::core::world::Coord;
using lb::core::world::TileMaterial;

const char *check_name(Check check) {
	static const char *const NAMES[] = {"none", "near_home", "gas", "gates", "widths", "poi_sockets", "spine_reach", "connected", "throats",
			"tapper_reach", "landmark", "arches", "collapse_spacing", "spine_collapse", "clear_ground"};
	static_assert(sizeof(NAMES) / sizeof(NAMES[0]) == static_cast<size_t>(Check::COUNT), "a name for every check");
	const size_t i = static_cast<size_t>(check);
	return i < static_cast<size_t>(Check::COUNT) ? NAMES[i] : "";
}

std::string describe(const Verdict &v) {
	if (v.ok()) {
		return "ok";
	}
	std::string s = "rule " + std::to_string(v.number()) + " (" + check_name(v.check) + ") at (" + std::to_string(v.tile.x) + ", " +
			std::to_string(v.tile.y) + ")";
	return v.detail.empty() ? s : s + ": " + v.detail;
}

namespace {

Verdict fail(Check check, Coord tile, std::string detail) {
	Verdict v;
	v.check = check;
	v.tile = tile;
	v.detail = std::move(detail);
	return v;
}

bool passable(uint8_t material) {
	const TileMaterial m = static_cast<TileMaterial>(material);
	return m == TileMaterial::FLOOR || m == TileMaterial::STEEL || m == TileMaterial::WOODEN_DOOR;
}

bool in_cell(int64_t x, int64_t y) {
	return x >= 0 && y >= 0 && x < CELL_TILES && y < CELL_TILES;
}

uint8_t material_at(const Cell &c, int64_t x, int64_t y) {
	return c.tiles[static_cast<size_t>(Cell::index_of(x, y))].material;
}

// The local tile `along` tiles along `side` (from its west or north end).
Coord edge_tile(Edge side, int64_t along) {
	switch (side) {
		case Edge::NORTH:
			return {along, 0};
		case Edge::SOUTH:
			return {along, CELL_TILES - 1};
		case Edge::WEST:
			return {0, along};
		default:
			return {CELL_TILES - 1, along};
	}
}

// Whether a point of interest's cell's `side` faces out of its footprint (every side of any other cell).
bool outer_edge(const CellClass &cls, Edge side) {
	if (cls.kind != TemplateKind::POI || cls.poi_template == nullptr) {
		return true;
	}
	const Coord n = neighbour(cls.poi_cell, side);
	return n.x < 0 || n.y < 0 || n.x >= cls.poi_template->footprint_w || n.y >= cls.poi_template->footprint_h;
}

// Rule 8: on every outward edge, passable tiles exactly at the open socket's opening.
Verdict check_throats(const Layout &l, const CellClass &cls) {
	for (int32_t e = 0; e < 4; e++) {
		const Edge side = static_cast<Edge>(e);
		if (!outer_edge(cls, side)) {
			continue;
		}
		const Socket &s = l.sockets[static_cast<size_t>(e)];
		const int64_t first = s.open ? opening_first(s.offset, s.width) : CELL_TILES;
		const int64_t last = s.open ? first + s.width : CELL_TILES;
		for (int64_t a = 0; a < CELL_TILES; a++) {
			const Coord t = edge_tile(side, a);
			const bool open = passable(material_at(l.cell, t.x, t.y));
			const bool want = a >= first && a < last;
			if (open != want) {
				return fail(Check::THROATS, lb::core::world::tile_of(l.coord, t),
						open ? "floor at the edge outside the socket's opening" : "the socket's opening is not floor its whole width");
			}
		}
	}
	return {};
}

// Rule 5: a point of interest's door on an open socket at its offset; the lair joins no socket but
// its door's.
Verdict check_poi_sockets(const Layout &l, const CellClass &cls, const ValidatorParams &p) {
	if (cls.kind != TemplateKind::POI || cls.poi_template == nullptr) {
		return {};
	}
	const Template &t = *cls.poi_template;
	int32_t doors = 0;
	for (const Stub &st : t.stubs) {
		if (!st.door || !(st.cell == cls.poi_cell)) {
			continue;
		}
		doors++;
		const Socket &s = l.sockets[static_cast<size_t>(st.edge)];
		if (!s.open || s.offset != st.offset) {
			return fail(Check::POI_SOCKETS, lb::core::world::tile_of(l.coord, edge_tile(st.edge, st.offset)),
					"a point of interest's door on a shut socket");
		}
	}
	if (t.poi_kind == p.rules.lair_kind) {
		int32_t open = 0;
		Coord at = lb::core::world::tile_of(l.coord, {CELL_TILES / 2, CELL_TILES / 2});
		for (int32_t e = 0; e < 4; e++) {
			const Socket &s = l.sockets[static_cast<size_t>(e)];
			if (outer_edge(cls, static_cast<Edge>(e)) && s.open) {
				open++;
				at = lb::core::world::tile_of(l.coord, edge_tile(static_cast<Edge>(e), s.offset));
			}
		}
		if (open != doors) {
			return fail(Check::POI_SOCKETS, at, "the lair joins " + std::to_string(open) + " sockets here, not its door's " + std::to_string(doors));
		}
	}
	return {};
}

// Rules 7, 4 and 9 by GEN-04's own code, cell by cell.
Verdict check_fitted(const Layout &l, const CellClass &cls, const ValidatorParams &p) {
	const TemplateKind kind = l.fallback ? TemplateKind::FALLBACK : cls.kind;
	const bool old_fall = kind == TemplateKind::MAIN_ROAD && cls.old_fall;
	for (const Problem &pr : validate_fitted(l.cell, kind, old_fall, p.rules)) {
		Check c = Check::NONE;
		if (pr.rule == "connected_floor") {
			c = Check::CONNECTED;
		} else if (pr.rule == "widths") {
			c = Check::WIDTHS;
		} else if (pr.rule == "tapper_reach") {
			c = Check::TAPPER_REACH;
		}
		if (c != Check::NONE) {
			const Coord local = pr.x >= 0 ? Coord{pr.x, pr.y} : Coord{0, 0};
			return fail(c, lb::core::world::tile_of(l.coord, local), pr.message);
		}
	}
	return {};
}

// Rule 10: one landmark site.
Verdict check_landmark(const Layout &l) {
	int32_t n = 0;
	Coord at{0, 0};
	for (const lb::core::world::Anchor &a : l.cell.anchors) {
		if (a.type == AnchorType::LANDMARK) {
			n++;
			at = {a.x, a.y};
		}
	}
	if (n != 1) {
		return fail(Check::LANDMARK, lb::core::world::tile_of(l.coord, at), std::to_string(n) + " landmark sites, not one");
	}
	return {};
}

} // namespace

// The arch tiles a gate cell carries (GEN-02's flood: from the gate's opening over floor, the
// opening's tiles the first step), and the first door tile beside one the flood would have gone
// on from. Empty for any other cell.
std::vector<Coord> gate_arch_tiles(const Layout &l, const ValidatorParams &p, std::optional<Coord> *door) {
	std::vector<Coord> out;
	for (int32_t e = 0; e < 4; e++) {
		const Edge side = static_cast<Edge>(e);
		const int32_t reach = p.arch_reach[static_cast<size_t>(e)];
		if (reach <= 0 || !(l.coord == neighbour({0, 0}, side))) {
			continue;
		}
		const Edge in = opposite(side);
		const Socket &s = l.sockets[static_cast<size_t>(in)];
		if (!s.open) {
			continue;
		}
		std::vector<int32_t> step(static_cast<size_t>(CELL_TILES * CELL_TILES), 0);
		std::deque<Coord> q;
		const int64_t first = opening_first(s.offset, s.width);
		for (int64_t a = first; a < first + s.width; a++) {
			const Coord t = edge_tile(in, a);
			if (in_cell(t.x, t.y) && material_at(l.cell, t.x, t.y) == static_cast<uint8_t>(TileMaterial::FLOOR)) {
				step[static_cast<size_t>(Cell::index_of(t.x, t.y))] = 1;
				q.push_back(t);
			}
		}
		while (!q.empty()) {
			const Coord t = q.front();
			q.pop_front();
			out.push_back(lb::core::world::tile_of(l.coord, t));
			const int32_t d = step[static_cast<size_t>(Cell::index_of(t.x, t.y))];
			if (d >= reach) {
				continue;
			}
			const Coord next[4] = {{t.x + 1, t.y}, {t.x - 1, t.y}, {t.x, t.y + 1}, {t.x, t.y - 1}};
			for (const Coord &n : next) {
				if (!in_cell(n.x, n.y) || step[static_cast<size_t>(Cell::index_of(n.x, n.y))] != 0) {
					continue;
				}
				const TileMaterial m = static_cast<TileMaterial>(material_at(l.cell, n.x, n.y));
				if (m == TileMaterial::FLOOR) {
					step[static_cast<size_t>(Cell::index_of(n.x, n.y))] = d + 1;
					q.push_back(n);
				} else if ((m == TileMaterial::WOODEN_DOOR || m == TileMaterial::STEEL) && door != nullptr && !door->has_value()) {
					*door = lb::core::world::tile_of(l.coord, n);
				}
			}
		}
	}
	return out;
}

Verdict validate_layout(const Layout &layout, const CellClass &cls, const ValidatorParams &p) {
	if (layout.base_camp) {
		return {};
	}
	if (Verdict v = check_throats(layout, cls); !v.ok()) {
		return v;
	}
	if (Verdict v = check_poi_sockets(layout, cls, p); !v.ok()) {
		return v;
	}
	if (cls.kind == TemplateKind::POI && cls.poi_template != nullptr) {
		return {}; // its floor, widths and reach are GEN-04's, over the whole template
	}
	if (Verdict v = check_fitted(layout, cls, p); !v.ok()) {
		return v;
	}
	if (Verdict v = check_landmark(layout); !v.ok()) {
		return v;
	}
	std::optional<Coord> door;
	gate_arch_tiles(layout, p, &door);
	if (door) {
		return fail(Check::ARCHES, *door, "a door on the arch past base camp's gate");
	}
	return {};
}

std::optional<Layout> derive_final(const DeriveInputs &in, Coord cell, std::vector<LayoutTry> *tried,
		const std::function<std::optional<Layout>(int32_t)> &derive_at) {
	auto at = [&](int32_t reroll) { return derive_at ? derive_at(reroll) : derive_layout(in, cell, reroll); };
	if (in.validator == nullptr) {
		return at(0);
	}
	const CellClass cls = in.cells->classify(cell);
	const int32_t limit = std::max<int32_t>(0, in.header->reroll_limit);
	for (int32_t k = 0; k <= limit; k++) {
		std::optional<Layout> l = at(k);
		if (!l) {
			return std::nullopt; // no template covers it and its biome has no fallback
		}
		l->reroll = k;
		if (l->base_camp) {
			return l;
		}
		const Verdict v = validate_layout(*l, cls, *in.validator);
		if (v.ok()) {
			return l;
		}
		if (tried != nullptr) {
			tried->push_back({k, l->template_id, v});
		}
		// The fallback is the last word, and a point of interest's cell its template's whatever the reroll.
		if (l->fallback || (cls.kind == TemplateKind::POI && cls.poi_template != nullptr)) {
			return l;
		}
	}
	return std::nullopt;
}

std::vector<CoverageFailure> fallback_coverage(const TemplateSet &set, const std::string &biome, const std::vector<int32_t> &widths,
		const SocketParams &sockets, const ValidatorParams &p, size_t *checked) {
	std::vector<CoverageFailure> out;
	if (checked != nullptr) {
		*checked = 0;
	}
	const Template *fb = set.fallback(biome);
	if (fb == nullptr) {
		CoverageFailure f;
		f.verdict = fail(Check::THROATS, {0, 0}, "no plain fallback for biome '" + biome + "'");
		out.push_back(f);
		return out;
	}
	// Each edge shut, or open at each offset and width.
	std::vector<Socket> states{Socket{}};
	for (int32_t offset : sockets.offsets) {
		for (int32_t w : widths) {
			Socket s;
			s.open = true;
			s.offset = offset;
			s.width = w;
			states.push_back(s);
		}
	}
	CellClass cls;
	cls.kind = TemplateKind::BIOME_CELL;
	cls.biome = biome;
	const Coord at{3, 7}; // any cell clear of base camp and its gates
	size_t n = 0;
	const size_t k = states.size();
	for (size_t i = 0; i < k * k * k * k; i++) {
		CellSockets s{};
		s[0] = states[i % k];
		s[1] = states[(i / k) % k];
		s[2] = states[(i / (k * k)) % k];
		s[3] = states[(i / (k * k * k)) % k];
		Layout l;
		l.coord = at;
		l.fallback = true;
		l.template_id = fb->id;
		l.sockets = s;
		l.cell = fill_stubs(*fb, s, at);
		n++;
		const Verdict v = validate_layout(l, cls, p);
		if (!v.ok()) {
			out.push_back({s, v});
		}
	}
	if (checked != nullptr) {
		*checked = n;
	}
	return out;
}

} // namespace lb::core::gen

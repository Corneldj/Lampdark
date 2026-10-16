#include "core/gen/template.h"

#include "core/sound/zone_block.h"
#include "core/world/mine_map.h"

#include <algorithm>
#include <deque>
#include <map>
#include <memory>
#include <set>

namespace lb::core::gen {

using lb::core::sound::CellBlock;
using lb::core::sound::ZoneKind;
using lb::core::world::Anchor;
using lb::core::world::AnchorType;
using lb::core::world::Cell;
using lb::core::world::CELL_AREA;
using lb::core::world::CELL_TILES;
using lb::core::world::Coord;
using lb::core::world::MineMap;
using lb::core::world::TileMaterial;

namespace {

const char *const KIND_NAMES[] = {"biome_cell", "main_road", "poi", "fallback", "base_camp"};

// The template's footprint as one grid of footprint-global tiles.
struct Grid {
	int32_t w = 20;
	int32_t h = 20;
	std::vector<uint8_t> walk; // walkable, doors and gates counted open
	std::vector<uint8_t> material;
	std::vector<int16_t> zone_kind; // -1 for none
	bool in(int32_t x, int32_t y) const { return x >= 0 && y >= 0 && x < w && y < h; }
	size_t at(int32_t x, int32_t y) const { return static_cast<size_t>(y) * w + x; }
};

const Cell *cell_of(const Template &t, Coord c) {
	for (const Cell &cell : t.cells) {
		if (cell.coord == c) {
			return &cell;
		}
	}
	return nullptr;
}

Coord cell_coord(int32_t gx, int32_t gy) { return Coord{gx / CELL_TILES, gy / CELL_TILES}; }

std::map<uint16_t, ZoneKind> zone_kinds(const Cell &cell) {
	std::map<uint16_t, ZoneKind> out;
	if (std::optional<CellBlock> b = lb::core::sound::decode_block(cell.road_graph)) {
		for (const auto &z : b->zones) {
			out[z.id] = z.kind;
		}
	}
	return out;
}

Grid build_grid(const Template &t, const MineMap &mine) {
	Grid g;
	g.w = t.footprint_w * CELL_TILES;
	g.h = t.footprint_h * CELL_TILES;
	const size_t n = static_cast<size_t>(g.w) * g.h;
	g.walk.assign(n, 0);
	g.material.assign(n, static_cast<uint8_t>(TileMaterial::ROCK));
	g.zone_kind.assign(n, -1);
	std::map<Coord, std::map<uint16_t, ZoneKind>> kinds;
	for (const Cell &c : t.cells) {
		kinds[c.coord] = zone_kinds(c);
	}
	for (int32_t y = 0; y < g.h; y++) {
		for (int32_t x = 0; x < g.w; x++) {
			const Coord tile{x, y};
			g.walk[g.at(x, y)] = mine.is_walkable(tile, true) ? 1 : 0;
			g.material[g.at(x, y)] = static_cast<uint8_t>(mine.effective_material(tile));
			const Cell *c = cell_of(t, cell_coord(x, y));
			if (c != nullptr) {
				const uint16_t z = c->tiles[Cell::index_of(x % CELL_TILES, y % CELL_TILES)].zone;
				auto k = kinds[c->coord].find(z);
				if (k != kinds[c->coord].end()) {
					g.zone_kind[g.at(x, y)] = static_cast<int16_t>(k->second);
				}
			}
		}
	}
	return g;
}

// The walkable tiles reached 4-connected from `start` through `walk`.
std::vector<uint8_t> flood4(const Grid &g, const std::vector<uint8_t> &walk, Coord start) {
	std::vector<uint8_t> seen(walk.size(), 0);
	if (!g.in(start.x, start.y) || !walk[g.at(start.x, start.y)]) {
		return seen;
	}
	std::deque<Coord> q{start};
	seen[g.at(start.x, start.y)] = 1;
	while (!q.empty()) {
		const Coord c = q.front();
		q.pop_front();
		const Coord next[4] = {{c.x + 1, c.y}, {c.x - 1, c.y}, {c.x, c.y + 1}, {c.x, c.y - 1}};
		for (const Coord &n : next) {
			if (g.in(n.x, n.y) && walk[g.at(n.x, n.y)] && !seen[g.at(n.x, n.y)]) {
				seen[g.at(n.x, n.y)] = 1;
				q.push_back(n);
			}
		}
	}
	return seen;
}

struct Out {
	std::vector<Problem> &list;
	void add(const std::string &rule, int32_t gx, int32_t gy, const std::string &message) {
		Problem p;
		p.rule = rule;
		if (gx >= 0 && gy >= 0) {
			p.cell = cell_coord(gx, gy);
			p.x = gx % CELL_TILES;
			p.y = gy % CELL_TILES;
		}
		p.message = message;
		list.push_back(p);
	}
};

std::vector<std::pair<Coord, const Anchor *>> anchors_of(const Template &t, AnchorType type) {
	std::vector<std::pair<Coord, const Anchor *>> out;
	for (const Cell &c : t.cells) {
		for (const Anchor &a : c.anchors) {
			if (a.type == type) {
				out.emplace_back(Coord{c.coord.x * CELL_TILES + a.x, c.coord.y * CELL_TILES + a.y}, &a);
			}
		}
	}
	return out;
}

bool rect_has(Coord origin, const Anchor &a, int32_t x, int32_t y) {
	return x >= origin.x && y >= origin.y && x < origin.x + a.w && y < origin.y + a.h;
}

std::string span(int32_t lo, int32_t hi) {
	return std::to_string(lo) + "-" + std::to_string(hi);
}

// Thousandths of a tile as a short decimal ("1.5", "0.25").
std::string tiles(uint32_t milli) {
	std::string s = std::to_string(milli / 1000);
	uint32_t frac = milli % 1000;
	if (frac != 0) {
		std::string digits = std::to_string(1000 + frac).substr(1);
		while (!digits.empty() && digits.back() == '0') {
			digits.pop_back();
		}
		s += "." + digits;
	}
	return s;
}

bool is_face(uint8_t material) {
	return material == static_cast<uint8_t>(TileMaterial::COAL) || material == static_cast<uint8_t>(TileMaterial::ROCK);
}

int32_t floor_neighbours(const Grid &g, int32_t x, int32_t y) {
	int32_t n = 0;
	const Coord next[4] = {{x + 1, y}, {x - 1, y}, {x, y + 1}, {x, y - 1}};
	for (const Coord &c : next) {
		n += g.in(c.x, c.y) && g.walk[g.at(c.x, c.y)] ? 1 : 0;
	}
	return n;
}

std::set<size_t> throat_set(const Template &t, const Grid &g) {
	std::set<size_t> out;
	for (const Stub &s : t.stubs) {
		for (const Coord &c : throat(t, s, s.max_width)) {
			if (g.in(c.x, c.y)) {
				out.insert(g.at(c.x, c.y));
			}
		}
	}
	return out;
}

// Each walkable tile's 4-connected piece, numbered from 1 in scan order (0 for none).
std::vector<int32_t> pieces(const Grid &g, const std::vector<uint8_t> &walk, int32_t &count) {
	std::vector<int32_t> label(walk.size(), 0);
	count = 0;
	for (int32_t y = 0; y < g.h; y++) {
		for (int32_t x = 0; x < g.w; x++) {
			if (!walk[g.at(x, y)] || label[g.at(x, y)] != 0) {
				continue;
			}
			count++;
			std::deque<Coord> q{Coord{x, y}};
			label[g.at(x, y)] = count;
			while (!q.empty()) {
				const Coord c = q.front();
				q.pop_front();
				const Coord next[4] = {{c.x + 1, c.y}, {c.x - 1, c.y}, {c.x, c.y + 1}, {c.x, c.y - 1}};
				for (const Coord &n : next) {
					const int32_t nx = static_cast<int32_t>(n.x);
					const int32_t ny = static_cast<int32_t>(n.y);
					if (g.in(nx, ny) && walk[g.at(nx, ny)] && label[g.at(nx, ny)] == 0) {
						label[g.at(nx, ny)] = count;
						q.push_back(n);
					}
				}
			}
		}
	}
	return label;
}

// A tile of `after` (a subset of `before`'s floor) cut off from floor it shared a piece with in
// `before`: removing tiles split a piece. nullopt if every piece stayed whole.
std::optional<Coord> split_from(const Grid &g, const std::vector<uint8_t> &before, const std::vector<uint8_t> &after) {
	int32_t nb = 0;
	int32_t na = 0;
	const std::vector<int32_t> lb = pieces(g, before, nb);
	const std::vector<int32_t> la = pieces(g, after, na);
	std::map<int32_t, int32_t> first_after; // before piece -> the first after piece inside it
	for (int32_t y = 0; y < g.h; y++) {
		for (int32_t x = 0; x < g.w; x++) {
			const int32_t a = la[g.at(x, y)];
			if (a == 0) {
				continue;
			}
			auto it = first_after.find(lb[g.at(x, y)]);
			if (it == first_after.end()) {
				first_after[lb[g.at(x, y)]] = a;
			} else if (it->second != a) {
				return Coord{x, y};
			}
		}
	}
	return std::nullopt;
}

void rule_connected(const Template &t, const Grid &g, Out &out) {
	// One piece; a main road's old fall leaves two, one on each side (GEN-07's rule checks which).
	const int32_t allowed = t.kind == TemplateKind::MAIN_ROAD && t.old_fall ? 2 : 1;
	int32_t count = 0;
	const std::vector<int32_t> label = pieces(g, g.walk, count);
	if (count <= allowed) {
		return;
	}
	for (int32_t y = 0; y < g.h; y++) {
		for (int32_t x = 0; x < g.w; x++) {
			if (label[g.at(x, y)] == allowed + 1) {
				out.add("connected_floor", x, y, "floor not 4-connected to the rest with every collapse standing");
				return;
			}
		}
	}
}

// The side of the largest all-floor square holding each walkable tile (GEN-04's width measure,
// Proposed: a road and its crossings read their width, a chamber its own; the ticket's shorter-run
// measure read every crossroads as wider than 8).
std::vector<int32_t> open_square(const Grid &g) {
	std::vector<int32_t> end(g.walk.size(), 0); // largest square with its bottom-right here
	for (int32_t y = 0; y < g.h; y++) {
		for (int32_t x = 0; x < g.w; x++) {
			if (!g.walk[g.at(x, y)]) {
				continue;
			}
			const int32_t up = y > 0 ? end[g.at(x, y - 1)] : 0;
			const int32_t left = x > 0 ? end[g.at(x - 1, y)] : 0;
			const int32_t diag = (x > 0 && y > 0) ? end[g.at(x - 1, y - 1)] : 0;
			end[g.at(x, y)] = 1 + std::min(up, std::min(left, diag));
		}
	}
	std::vector<int32_t> side(g.walk.size(), 0);
	for (int32_t y = 0; y < g.h; y++) {
		for (int32_t x = 0; x < g.w; x++) {
			const int32_t s = end[g.at(x, y)];
			for (int32_t dy = 0; dy < s; dy++) {
				for (int32_t dx = 0; dx < s; dx++) {
					side[g.at(x - dx, y - dy)] = std::max(side[g.at(x - dx, y - dy)], s);
				}
			}
		}
	}
	return side;
}

// A junction tile: both its floor runs longer than a road is wide (the middle of a crossroads).
bool junction(const Grid &g, int32_t x, int32_t y, int32_t road_max) {
	int32_t x0 = x, x1 = x, y0 = y, y1 = y;
	while (g.in(x0 - 1, y) && g.walk[g.at(x0 - 1, y)]) x0--;
	while (g.in(x1 + 1, y) && g.walk[g.at(x1 + 1, y)]) x1++;
	while (g.in(x, y0 - 1) && g.walk[g.at(x, y0 - 1)]) y0--;
	while (g.in(x, y1 + 1) && g.walk[g.at(x, y1 + 1)]) y1++;
	return x1 - x0 + 1 > road_max && y1 - y0 + 1 > road_max;
}

void rule_widths(const Template &t, const Grid &g, const ValidateParams &p, Out &out) {
	const auto chambers = anchors_of(t, AnchorType::CHAMBER);
	for (const auto &[origin, a] : chambers) {
		if (a->w < p.chamber_min || a->h < p.chamber_min || a->w > p.chamber_max || a->h > p.chamber_max) {
			out.add("widths", static_cast<int32_t>(origin.x), static_cast<int32_t>(origin.y),
					"chamber anchor " + std::to_string(a->w) + "x" + std::to_string(a->h) + " is not " + span(p.chamber_min, p.chamber_max) + " across");
		}
	}
	const std::vector<int32_t> side = open_square(g);
	for (int32_t y = 0; y < g.h; y++) {
		for (int32_t x = 0; x < g.w; x++) {
			if (!g.walk[g.at(x, y)]) {
				continue;
			}
			const int32_t w = side[g.at(x, y)];
			if (w >= p.road_width_min && w <= p.road_width_max) {
				continue;
			}
			bool in_chamber = false;
			for (const auto &[origin, a] : chambers) {
				in_chamber = in_chamber || rect_has(origin, *a, x, y);
			}
			if (w >= p.chamber_min && w <= p.chamber_max && in_chamber) {
				continue;
			}
			out.add("widths", x, y, "floor " + std::to_string(w) + " across: a road is " + span(p.road_width_min, p.road_width_max) + ", a chamber " + span(p.chamber_min, p.chamber_max) + " inside a chamber anchor, never " + std::to_string(p.chamber_forbidden_width));
			return;
		}
	}
}

void rule_rib(const Template &t, const Grid &g, const ValidateParams &p, Out &out) {
	for (const RibOffset &r : t.rib) {
		const int32_t gx = r.cell.x * CELL_TILES + r.index % CELL_TILES;
		const int32_t gy = r.cell.y * CELL_TILES + r.index / CELL_TILES;
		if (r.milli > p.rib_wander_max_milli) {
			out.add("rib_art", gx, gy, "rib offset " + tiles(r.milli) + " tile exceeds " + tiles(p.rib_wander_max_milli));
		} else if (g.in(gx, gy) && g.walk[g.at(gx, gy)]) {
			out.add("rib_art", gx, gy, "rib offset on a floor tile");
		}
	}
}

void rule_tapper_reach(const Grid &g, const MineMap &mine, const ValidateParams &p, Out &out) {
	for (int32_t y = 0; y < g.h; y++) {
		for (int32_t x = 0; x < g.w; x++) {
			if (!g.walk[g.at(x, y)] || g.zone_kind[g.at(x, y)] != static_cast<int16_t>(ZoneKind::ROAD)) {
				continue;
			}
			// Brick-lined: a brick wall within a road's width (the middle of a 3-wide road is 2 away).
			const int32_t r = std::max(1, p.road_width_max - 1);
			bool brick = false;
			for (int32_t dy = -r; dy <= r; dy++) {
				for (int32_t dx = -r; dx <= r; dx++) {
					brick = brick || (g.in(x + dx, y + dy) && g.material[g.at(x + dx, y + dy)] == static_cast<uint8_t>(TileMaterial::BRICK));
				}
			}
			if (!brick && !junction(g, x, y, p.road_width_max) && mine.strike_milli(Coord{x, y}) > p.tapper_reach_milli) {
				out.add("tapper_reach", x, y, "road tile beyond " + tiles(p.tapper_reach_milli) + " tiles of a strike face");
				return;
			}
		}
	}
}

void rule_stubs(const Template &t, const Grid &g, const ValidateParams &p, Out &out) {
	std::set<std::tuple<int32_t, int32_t, int32_t, int32_t>> seen;
	for (const Stub &s : t.stubs) {
		// Problems name the stub's mouth: its first tile on the edge.
		const std::vector<Coord> mouth = throat(t, s, 1);
		const int32_t ex = mouth.empty() ? static_cast<int32_t>(s.cell.x * CELL_TILES) : static_cast<int32_t>(mouth[0].x);
		const int32_t ey = mouth.empty() ? static_cast<int32_t>(s.cell.y * CELL_TILES) : static_cast<int32_t>(mouth[0].y);
		if (s.offset != 5 && s.offset != 10 && s.offset != 15) {
			out.add("stubs", ex, ey, "stub offset " + std::to_string(s.offset) + " is not 5, 10 or 15");
			continue;
		}
		if (s.max_width < 1 || s.max_width > std::min(3, p.biome_stub_width_max)) {
			out.add("stubs", ex, ey, "stub width " + std::to_string(s.max_width) + " wider than the biome allows (" + std::to_string(std::min(3, p.biome_stub_width_max)) + ")");
			continue;
		}
		if (s.depth < 1 || s.depth > CELL_TILES / 2) {
			out.add("stubs", ex, ey, "stub throat depth " + std::to_string(s.depth) + " outside 1 to half a cell");
			continue;
		}
		if (!seen.insert(std::make_tuple(static_cast<int32_t>(s.cell.x), static_cast<int32_t>(s.cell.y), static_cast<int32_t>(s.edge), s.offset)).second) {
			out.add("stubs", ex, ey, "two stubs at one edge position");
			continue;
		}
		for (const Coord &c : throat(t, s, s.max_width)) {
			if (!g.in(c.x, c.y) || !g.walk[g.at(c.x, c.y)]) {
				out.add("stubs", c.x, c.y, "stub throat tile is not floor");
				return;
			}
		}
	}
	// The outer edge is rock but for the stubs' throats, so the sockets alone decide what joins.
	const std::set<size_t> throats = throat_set(t, g);
	// A door or gate beside a throat would be stranded when the stub fills: its portal would join
	// one zone (GEN-11's finding).
	for (const Cell &c : t.cells) {
		for (const auto &b : c.barriers) {
			for (uint16_t i : b.tiles) {
				const int32_t bx = static_cast<int32_t>(c.coord.x * CELL_TILES) + i % CELL_TILES;
				const int32_t by = static_cast<int32_t>(c.coord.y * CELL_TILES) + i / CELL_TILES;
				const Coord next[4] = {{bx + 1, by}, {bx - 1, by}, {bx, by + 1}, {bx, by - 1}};
				for (const Coord &n : next) {
					if (g.in(static_cast<int32_t>(n.x), static_cast<int32_t>(n.y)) && throats.count(g.at(static_cast<int32_t>(n.x), static_cast<int32_t>(n.y))) != 0) {
						out.add("stubs", bx, by, "a door or gate beside a stub's throat, stranded when the stub fills");
						return;
					}
				}
			}
		}
	}
	for (int32_t y = 0; y < g.h; y++) {
		for (int32_t x = 0; x < g.w; x++) {
			const bool edge = x == 0 || y == 0 || x == g.w - 1 || y == g.h - 1;
			if (edge && g.walk[g.at(x, y)] && throats.count(g.at(x, y)) == 0) {
				out.add("stubs", x, y, "floor on the outer edge outside every stub's throat");
				return;
			}
		}
	}
	const size_t n = t.stubs.size();
	if (n > 16) {
		out.add("stubs", -1, -1, std::to_string(n) + " stubs: more than 16 to check every subset");
		return;
	}
	if (n == 0) {
		return;
	}
	// Filling any subset of stubs leaves the remaining floor connected.
	for (uint32_t mask = 1; mask < (1u << n); mask++) {
		std::vector<uint8_t> walk = g.walk;
		for (size_t i = 0; i < n; i++) {
			if (mask & (1u << i)) {
				for (const Coord &c : throat(t, t.stubs[i], t.stubs[i].max_width)) {
					if (g.in(c.x, c.y)) {
						walk[g.at(c.x, c.y)] = 0;
					}
				}
			}
		}
		if (std::optional<Coord> c = split_from(g, g.walk, walk)) {
			out.add("stubs", static_cast<int32_t>(c->x), static_cast<int32_t>(c->y), "filling stubs (mask " + std::to_string(mask) + ") splits the floor");
			return;
		}
	}
	// Narrowing any stub's throat to each width up to its maximum keeps it connected.
	for (const Stub &s : t.stubs) {
		for (int32_t w = 1; w < s.max_width; w++) {
			std::vector<uint8_t> walk = g.walk;
			std::set<size_t> keep;
			for (const Coord &c : throat(t, s, w)) {
				keep.insert(g.at(c.x, c.y));
			}
			for (const Coord &c : throat(t, s, s.max_width)) {
				if (g.in(c.x, c.y) && keep.count(g.at(c.x, c.y)) == 0) {
					walk[g.at(c.x, c.y)] = 0;
				}
			}
			if (std::optional<Coord> c = split_from(g, g.walk, walk)) {
				out.add("stubs", static_cast<int32_t>(c->x), static_cast<int32_t>(c->y), "narrowing a stub to " + std::to_string(w) + " splits the floor");
				return;
			}
		}
	}
}

// What validate_block cannot see: two zones touching with no portal between them, and a portal
// touching a zone beyond the two it joins or another portal (sound would skip or stall there).
void block_shape(const Cell &c, const CellBlock &b, const std::string &state, Out &out) {
	std::map<uint16_t, size_t> portal_of;
	for (size_t k = 0; k < b.portals.size(); k++) {
		for (uint16_t t : b.portals[k].tiles) {
			portal_of[t] = k;
		}
	}
	const auto floor = [&](int64_t i) { return c.tiles[static_cast<size_t>(i)].material == static_cast<uint8_t>(TileMaterial::FLOOR); };
	std::set<std::string> said;
	for (int64_t i = 0; i < CELL_AREA; i++) {
		const int32_t x = static_cast<int32_t>(i % CELL_TILES);
		const int32_t y = static_cast<int32_t>(i / CELL_TILES);
		const int32_t gx = static_cast<int32_t>(c.coord.x * CELL_TILES) + x;
		const int32_t gy = static_cast<int32_t>(c.coord.y * CELL_TILES) + y;
		std::vector<int64_t> next;
		if (x + 1 < CELL_TILES)
			next.push_back(i + 1);
		if (y + 1 < CELL_TILES)
			next.push_back(i + CELL_TILES);
		if (x > 0)
			next.push_back(i - 1);
		if (y > 0)
			next.push_back(i - CELL_TILES);
		auto pi = portal_of.find(static_cast<uint16_t>(i));
		for (int64_t n : next) {
			auto pn = portal_of.find(static_cast<uint16_t>(n));
			const uint16_t zi = c.tiles[static_cast<size_t>(i)].zone;
			const uint16_t zn = c.tiles[static_cast<size_t>(n)].zone;
			std::string why;
			if (pi == portal_of.end() && pn == portal_of.end()) {
				if (n > i && floor(i) && floor(n) && zi != 0 && zn != 0 && zi != zn) {
					why = "zones " + std::to_string(std::min(zi, zn)) + " and " + std::to_string(std::max(zi, zn)) + " touch with no portal between them";
				}
			} else if (pi != portal_of.end() && pn != portal_of.end()) {
				if (pi->second != pn->second && n > i) {
					why = "portals " + std::to_string(b.portals[pi->second].id) + " and " + std::to_string(b.portals[pn->second].id) + " touch with no zone between them";
				}
			} else if (pi != portal_of.end() && floor(n) && zn != 0) {
				const auto &p = b.portals[pi->second];
				if (zn != p.zone_a && zn != p.zone_b) {
					why = "portal " + std::to_string(p.id) + " touches zone " + std::to_string(zn) + " beyond the two it joins";
				}
			}
			if (!why.empty() && said.insert(why).second) {
				out.add("zones_portals", gx, gy, state + why);
			}
		}
	}
}

void rule_zones(const Template &t, const Grid &g, Out &out) {
	for (const Cell &c : t.cells) {
		std::optional<CellBlock> block = lb::core::sound::decode_block(c.road_graph);
		const int32_t ox = static_cast<int32_t>(c.coord.x * CELL_TILES);
		const int32_t oy = static_cast<int32_t>(c.coord.y * CELL_TILES);
		if (!block) {
			out.add("zones_portals", ox, oy, "no readable zone and portal block");
			continue;
		}
		for (const std::string &why : lb::core::sound::validate_block(c, *block)) {
			out.add("zones_portals", ox, oy, why);
		}
		block_shape(c, *block, "", out);
		for (const auto &col : c.collapses) {
			Cell fallen = c;
			for (const auto &wr : col.fallen) {
				fallen.tiles[wr.index].material = wr.material;
			}
			for (const auto &z : col.zones) {
				fallen.tiles[z.index].zone = z.fallen;
			}
			std::optional<CellBlock> fb = col.fallen_road_graph.empty() ? std::nullopt : lb::core::sound::decode_block(col.fallen_road_graph);
			if (!fb) {
				out.add("zones_portals", ox, oy, "collapse " + std::to_string(col.id) + " has no fallen zone and portal set");
				continue;
			}
			const std::string state = "collapse " + std::to_string(col.id) + " fallen: ";
			for (const std::string &why : lb::core::sound::validate_block(fallen, *fb)) {
				out.add("zones_portals", ox, oy, state + why);
			}
			block_shape(fallen, *fb, state, out);
		}
	}
	// Floor crossing between the template's own cells: both sides zoned, for the edge links.
	for (int32_t y = 0; y < g.h; y++) {
		for (int32_t x = 0; x < g.w; x++) {
			const bool east = (x + 1) % CELL_TILES == 0 && x + 1 < g.w;
			const bool south = (y + 1) % CELL_TILES == 0 && y + 1 < g.h;
			for (const Coord &n : {Coord{x + 1, y}, Coord{x, y + 1}}) {
				if ((n.x != x && !east) || (n.y != y && !south)) {
					continue;
				}
				const size_t a = g.at(x, y);
				const size_t b = g.at(static_cast<int32_t>(n.x), static_cast<int32_t>(n.y));
				if (g.walk[a] && g.walk[b] && (g.zone_kind[a] < 0 || g.zone_kind[b] < 0)) {
					out.add("zones_portals", x, y, "floor crosses a cell edge at a portal tile: no edge link there");
					return;
				}
			}
		}
	}
	// Each stub's mouth opens on the footprint edge: an edge link the Road Graph stitches (a zoned
	// floor tile at the edge).
	for (const Stub &s : t.stubs) {
		const std::vector<Coord> mouth = throat(t, s, s.max_width);
		for (const Coord &m : mouth) {
			const bool edge = m.x == 0 || m.y == 0 || m.x == g.w - 1 || m.y == g.h - 1;
			if (!edge) {
				continue;
			}
			const Cell *c = cell_of(t, cell_coord(m.x, m.y));
			const uint16_t z = c != nullptr ? c->tiles[Cell::index_of(m.x % CELL_TILES, m.y % CELL_TILES)].zone : 0;
			if (!g.walk[g.at(m.x, m.y)] || z == 0) {
				out.add("zones_portals", m.x, m.y, "stub mouth without a zone for its edge link");
				return;
			}
		}
	}
}

void rule_collapses(const Template &t, const Grid &g, const ValidateParams &p, Out &out) {
	const std::set<size_t> throats = throat_set(t, g);
	std::vector<std::pair<Coord, const Anchor *>> blocked = anchors_of(t, AnchorType::DOOR_SITE);
	for (const auto &w : anchors_of(t, AnchorType::WALL_FIXTURE)) {
		blocked.push_back(w);
	}
	for (const Cell &c : t.cells) {
		for (const auto &col : c.collapses) {
			std::vector<Coord> falls;
			for (const auto &wr : col.fallen) {
				const int32_t gx = c.coord.x * CELL_TILES + wr.index % CELL_TILES;
				const int32_t gy = c.coord.y * CELL_TILES + wr.index / CELL_TILES;
				if (!g.walk[g.at(gx, gy)] || g.zone_kind[g.at(gx, gy)] != static_cast<int16_t>(ZoneKind::ROAD)) {
					out.add("collapses", gx, gy, "collapse " + std::to_string(col.id) + " off road floor");
					return;
				}
				if (throats.count(g.at(gx, gy)) != 0) {
					out.add("collapses", gx, gy, "collapse " + std::to_string(col.id) + " over a stub throat");
					return;
				}
				for (const auto &[origin, a] : blocked) {
					if (rect_has(origin, *a, gx, gy)) {
						out.add("collapses", gx, gy, "collapse " + std::to_string(col.id) + " over a door site or wall fixture");
						return;
					}
				}
				if (wr.material != static_cast<uint8_t>(TileMaterial::FLOOR)) {
					falls.push_back(Coord{gx, gy});
				}
			}
			if (falls.empty()) {
				out.add("collapses", c.coord.x * CELL_TILES, c.coord.y * CELL_TILES, "collapse " + std::to_string(col.id) + " turns no floor to rock");
				return;
			}
			int64_t x0 = falls[0].x, x1 = x0, y0 = falls[0].y, y1 = y0;
			for (const Coord &f : falls) {
				x0 = std::min(x0, f.x);
				x1 = std::max(x1, f.x);
				y0 = std::min(y0, f.y);
				y1 = std::max(y1, f.y);
			}
			// Across a road at most 3 wide and at most 3 long: neither span above the maximum.
			if (std::max(x1 - x0 + 1, y1 - y0 + 1) > std::max(p.collapse_length_max, p.road_width_max)) {
				out.add("collapses", falls[0].x, falls[0].y, "collapse " + std::to_string(col.id) + " longer than " + std::to_string(p.collapse_length_max) + " tiles");
				return;
			}
			// The fallen set chokes its road: it splits a piece of floor.
			std::vector<uint8_t> walk = g.walk;
			for (const Coord &f : falls) {
				walk[g.at(f.x, f.y)] = 0;
			}
			if (!split_from(g, g.walk, walk)) {
				out.add("collapses", falls[0].x, falls[0].y, "collapse " + std::to_string(col.id) + " does not choke its road");
				return;
			}
		}
	}
}

void rule_hooks(const Template &t, const Grid &g, const ValidateParams &p, Out &out) {
	const auto hooks = anchors_of(t, AnchorType::TIMBER_HOOK);
	std::vector<int32_t> dist(g.walk.size(), -1);
	std::deque<Coord> q;
	for (const auto &[origin, a] : hooks) {
		if (g.in(origin.x, origin.y) && g.walk[g.at(origin.x, origin.y)] && dist[g.at(origin.x, origin.y)] < 0) {
			dist[g.at(origin.x, origin.y)] = 0;
			q.push_back(origin);
		}
	}
	while (!q.empty()) {
		const Coord c = q.front();
		q.pop_front();
		const Coord next[4] = {{c.x + 1, c.y}, {c.x - 1, c.y}, {c.x, c.y + 1}, {c.x, c.y - 1}};
		for (const Coord &n : next) {
			if (g.in(n.x, n.y) && g.walk[g.at(n.x, n.y)] && dist[g.at(n.x, n.y)] < 0) {
				dist[g.at(n.x, n.y)] = dist[g.at(c.x, c.y)] + 1;
				q.push_back(n);
			}
		}
	}
	bool far = false;
	for (int32_t y = 0; y < g.h && !far; y++) {
		for (int32_t x = 0; x < g.w && !far; x++) {
			if (g.walk[g.at(x, y)] && g.zone_kind[g.at(x, y)] == static_cast<int16_t>(ZoneKind::ROAD) && (dist[g.at(x, y)] < 0 || dist[g.at(x, y)] > p.hook_reach_tiles)) {
				out.add("timber_hooks", x, y, "road tile more than " + std::to_string(p.hook_reach_tiles) + " tiles by path from a timber hook");
				far = true;
			}
		}
	}
	for (const auto &[origin, a] : anchors_of(t, AnchorType::CHAMBER)) {
		bool has = false;
		for (const auto &[ho, h] : hooks) {
			has = has || rect_has(origin, *a, ho.x, ho.y);
		}
		if (!has) {
			out.add("timber_hooks", static_cast<int32_t>(origin.x), static_cast<int32_t>(origin.y), "a chamber without a timber hook");
			break;
		}
	}
	if (t.kind == TemplateKind::POI) {
		bool has = false;
		for (const auto &[ho, h] : hooks) {
			has = has || (g.in(ho.x, ho.y) && g.zone_kind[g.at(ho.x, ho.y)] == static_cast<int16_t>(ZoneKind::POI));
		}
		if (!has) {
			out.add("timber_hooks", 0, 0, "a point of interest without a timber hook in its rooms");
		}
	}
}

void rule_landmark(const Template &t, const ValidateParams &p, Out &out) {
	if (t.kind != TemplateKind::BIOME_CELL && t.kind != TemplateKind::MAIN_ROAD && t.kind != TemplateKind::FALLBACK) {
		return;
	}
	const size_t landmarks = anchors_of(t, AnchorType::LANDMARK).size();
	const size_t rubble = anchors_of(t, AnchorType::RUBBLE_HEAP).size();
	if (landmarks != 1) {
		out.add("landmark_rubble", -1, -1, std::to_string(landmarks) + " landmarks, not exactly one");
	}
	if (static_cast<int32_t>(rubble) < p.rubble_min || static_cast<int32_t>(rubble) > p.rubble_max) {
		out.add("landmark_rubble", -1, -1, std::to_string(rubble) + " rubble heaps, not " + span(p.rubble_min, p.rubble_max));
	}
}

void rule_anchor_fit(const Template &t, const Grid &g, const MineMap &mine, const ValidateParams &p, Out &out) {
	for (const auto &[o, a] : anchors_of(t, AnchorType::RICH_ROCK)) {
		for (int32_t y = o.y; y < o.y + a->h; y++) {
			for (int32_t x = o.x; x < o.x + a->w; x++) {
				if (!g.in(x, y) || g.walk[g.at(x, y)] || mine.thickness(Coord{x, y}) < p.rich_rock_min_thickness) {
					out.add("anchor_fit", x, y, "rich_rock not on solid " + std::to_string(p.rich_rock_min_thickness) + " or more tiles thick");
					return;
				}
			}
		}
	}
	for (const auto &[o, a] : anchors_of(t, AnchorType::GAS_AREA)) {
		if (std::max(a->w, a->h) < p.gas_area_min || std::max(a->w, a->h) > p.gas_area_max) {
			out.add("anchor_fit", o.x, o.y, "gas_area not " + span(p.gas_area_min, p.gas_area_max) + " tiles across");
			return;
		}
	}
	for (const auto &[o, a] : anchors_of(t, AnchorType::GAS_DEAD_END)) {
		const int32_t len = std::max(a->w, a->h);
		bool all_floor = true;
		bool dead_end = false;
		for (int32_t y = o.y; y < o.y + a->h; y++) {
			for (int32_t x = o.x; x < o.x + a->w; x++) {
				all_floor = all_floor && g.in(x, y) && g.walk[g.at(x, y)];
				dead_end = dead_end || (g.in(x, y) && g.walk[g.at(x, y)] && floor_neighbours(g, x, y) == 1);
			}
		}
		if (len < p.gas_dead_end_min || len > p.gas_dead_end_max || !all_floor || !dead_end) {
			out.add("anchor_fit", o.x, o.y, "gas_dead_end not " + span(p.gas_dead_end_min, p.gas_dead_end_max) + " tiles of road ending in a dead end");
			return;
		}
	}
	for (const auto &[o, a] : anchors_of(t, AnchorType::REMAINS)) {
		if (!g.in(o.x, o.y) || !g.walk[g.at(o.x, o.y)] || floor_neighbours(g, o.x, o.y) > 2) {
			out.add("anchor_fit", o.x, o.y, "remains not in a corner, stall or dead end");
			return;
		}
	}
	for (const auto &[o, a] : anchors_of(t, AnchorType::DOOR_SITE)) {
		bool all_floor = true;
		for (int32_t y = o.y; y < o.y + a->h; y++) {
			for (int32_t x = o.x; x < o.x + a->w; x++) {
				all_floor = all_floor && g.in(x, y) && g.walk[g.at(x, y)];
			}
		}
		if (std::min(a->w, a->h) != 1 || std::max(a->w, a->h) > 3 || !all_floor) {
			out.add("anchor_fit", o.x, o.y, "door_site not across a passage mouth 3 wide or less");
			return;
		}
	}
	for (const auto &[o, a] : anchors_of(t, AnchorType::WALL_FIXTURE)) {
		if (!g.in(o.x, o.y) || g.walk[g.at(o.x, o.y)] || !is_face(g.material[g.at(o.x, o.y)]) || floor_neighbours(g, o.x, o.y) == 0) {
			out.add("anchor_fit", o.x, o.y, "wall_fixture not on a coal or stone face");
			return;
		}
	}
}

void rule_poi(const Template &t, const ValidateParams &p, Out &out) {
	if (t.kind != TemplateKind::POI) {
		return;
	}
	size_t doors = 0;
	for (const Stub &s : t.stubs) {
		doors += s.door ? 1 : 0;
	}
	if (doors == 0) {
		out.add("poi", -1, -1, "a point of interest without a door stub");
	}
	if (t.poi_kind == p.lair_kind && t.stubs.size() != 1) {
		out.add("poi", -1, -1, "the lair has " + std::to_string(t.stubs.size()) + " stubs, not exactly one");
	}
	auto need = p.poi_slots.find(t.poi_kind);
	const size_t slots = anchors_of(t, AnchorType::POI_SLOT).size();
	if (need != p.poi_slots.end() && static_cast<int32_t>(slots) < need->second) {
		out.add("poi", -1, -1, std::to_string(slots) + " poi_slots for " + std::to_string(need->second) + " contents lines");
	}
	if (p.poi_phone_kinds.count(t.poi_kind) != 0) {
		bool phone = false;
		for (const auto &[o, a] : anchors_of(t, AnchorType::WALL_FIXTURE)) {
			phone = phone || a->kind == "phone";
		}
		if (!phone) {
			out.add("poi", -1, -1, "no phone wall_fixture where its kind has a phone");
		}
	}
}

void rule_fallback(const Template &t, const ValidateParams &p, Out &out) {
	if (t.kind != TemplateKind::FALLBACK) {
		return;
	}
	std::set<std::pair<int32_t, int32_t>> have;
	for (const Stub &s : t.stubs) {
		if (s.max_width == std::min(3, p.biome_stub_width_max)) {
			have.insert({static_cast<int32_t>(s.edge), s.offset});
		}
	}
	for (int32_t e = 0; e < static_cast<int32_t>(Edge::COUNT); e++) {
		for (int32_t offset : {5, 10, 15}) {
			if (have.count({e, offset}) == 0) {
				out.add("fallback", -1, -1, "a plain fallback needs a stub at every edge position at the biome's maximum width");
				return;
			}
		}
	}
}

// GEN-07: a main-road template, drawn east to west: its road stubs at the road's offset and width,
// rails on the centre line at every road mouth, a bend that breaks the line of sight, and an old
// fall that chokes the road with an exit on each side (north at 5, south at 15).
void rule_main_road(const Template &t, const Grid &g, const ValidateParams &p, Out &out) {
	if (t.kind != TemplateKind::MAIN_ROAD) {
		return;
	}
	static const std::set<std::string> SHAPES{"straight", "bend_5", "bend_10", "bend_15", "crossing"};
	if (t.footprint_w != 1 || t.footprint_h != 1) {
		out.add("main_road", -1, -1, "a main road is one cell");
		return;
	}
	if (SHAPES.count(t.shape) == 0) {
		out.add("main_road", -1, -1, "shape '" + t.shape + "' is not straight, bend_5, bend_10, bend_15 or crossing");
		return;
	}
	if (t.old_fall && t.shape != "straight") {
		out.add("main_road", -1, -1, "only a straight main road holds an old fall");
		return;
	}
	const Cell &cell = t.cells.front();
	std::vector<Edge> ends{Edge::WEST, Edge::EAST};
	if (t.shape == "crossing") {
		ends.push_back(Edge::NORTH);
		ends.push_back(Edge::SOUTH);
	}
	const int32_t o = p.main_road_offset;
	for (Edge e : ends) {
		bool found = false;
		for (const Stub &s : t.stubs) {
			found = found || (s.edge == e && s.offset == o && s.max_width == p.main_road_width);
		}
		const Coord mouth = e == Edge::WEST ? Coord{0, o} : e == Edge::EAST ? Coord{CELL_TILES - 1, o}
				: e == Edge::NORTH                                          ? Coord{o, 0}
																			: Coord{o, CELL_TILES - 1};
		const auto &tile = cell.tiles[static_cast<size_t>(Cell::index_of(mouth.x, mouth.y))];
		if (!found) {
			out.add("main_road", static_cast<int32_t>(mouth.x), static_cast<int32_t>(mouth.y),
					"no road stub here at offset " + std::to_string(o) + ", " + std::to_string(p.main_road_width) + " wide");
		} else if (tile.material != static_cast<uint8_t>(TileMaterial::FLOOR) || (tile.state & lb::core::world::STATE_RAIL) == 0) {
			out.add("main_road", static_cast<int32_t>(mouth.x), static_cast<int32_t>(mouth.y), "no rail on the road's centre line at its mouth");
		}
	}
	if (t.shape.rfind("bend_", 0) == 0) {
		// The bend breaks the line of sight (Proposed measure): no straight floor run along the road
		// reaches from bend_reach tiles before it to bend_reach after.
		const int32_t at = std::stoi(t.shape.substr(5));
		for (int32_t y = 0; y < g.h; y++) {
			bool through = true;
			for (int32_t x = std::max(0, at - p.bend_reach); x <= std::min(g.w - 1, at + p.bend_reach); x++) {
				through = through && g.walk[g.at(x, y)];
			}
			if (through) {
				out.add("main_road", at, y, "a straight line of sight runs through the bend");
				break;
			}
		}
	}
	if (t.old_fall) {
		const Stub *north = nullptr;
		const Stub *south = nullptr;
		for (const Stub &s : t.stubs) {
			north = s.edge == Edge::NORTH && s.offset == 5 ? &s : north;
			south = s.edge == Edge::SOUTH && s.offset == 15 ? &s : south;
		}
		if (north == nullptr || south == nullptr) {
			out.add("main_road", -1, -1, "an old fall needs a side stub north at 5 and south at 15");
			return;
		}
		int32_t count = 0;
		const std::vector<int32_t> label = pieces(g, g.walk, count);
		const Coord nw = throat(t, *north, 1).front();
		const Coord se = throat(t, *south, 1).front();
		const int32_t west = label[g.at(0, o)];
		const int32_t east = label[g.at(CELL_TILES - 1, o)];
		if (count != 2 || west == east || label[g.at(static_cast<int32_t>(nw.x), static_cast<int32_t>(nw.y))] != west || label[g.at(static_cast<int32_t>(se.x), static_cast<int32_t>(se.y))] != east) {
			out.add("main_road", o, o, "the old fall must split the road in two, the north exit with the west end and the south exit with the east");
		}
	}
}

} // namespace

Template transpose(const Template &t) {
	Template out = t;
	if (t.cells.size() != 1) {
		return out;
	}
	auto flip = [](uint16_t i) { return static_cast<uint16_t>((i % CELL_TILES) * CELL_TILES + i / CELL_TILES); };
	const Cell &c = t.cells.front();
	Cell n = c;
	for (int64_t y = 0; y < CELL_TILES; y++) {
		for (int64_t x = 0; x < CELL_TILES; x++) {
			n.tiles[static_cast<size_t>(Cell::index_of(y, x))] = c.tiles[static_cast<size_t>(Cell::index_of(x, y))];
		}
	}
	for (Anchor &a : n.anchors) {
		std::swap(a.x, a.y);
		std::swap(a.w, a.h);
	}
	for (auto &col : n.collapses) {
		for (auto &w : col.standing) {
			w.index = flip(w.index);
		}
		for (auto &w : col.fallen) {
			w.index = flip(w.index);
		}
	}
	using lb::core::sound::ZoneKind;
	const uint8_t room = static_cast<uint8_t>(t.kind == TemplateKind::POI ? ZoneKind::POI : ZoneKind::CHAMBER);
	cut_zones(n, room, t.kind == TemplateKind::BASE_CAMP);
	cut_collapses(n, room, t.kind == TemplateKind::BASE_CAMP);
	out.cells = {n};
	for (Stub &s : out.stubs) {
		static const Edge SWAP[4] = {Edge::WEST, Edge::SOUTH, Edge::EAST, Edge::NORTH}; // N->W, E->S, S->E, W->N
		s.edge = SWAP[static_cast<size_t>(s.edge)];
	}
	for (RibOffset &r : out.rib) {
		r.index = flip(r.index);
	}
	return out;
}

std::vector<Coord> throat(const Template &t, const Stub &s, int32_t width) {
	std::vector<Coord> out;
	const int32_t w = std::max(1, std::min(width, s.max_width));
	const int32_t first = s.offset - w / 2; // GEN-05's opening rule: 2 wide covers o - 1 and o
	const int32_t ox = s.cell.x * CELL_TILES;
	const int32_t oy = s.cell.y * CELL_TILES;
	(void)t;
	for (int32_t d = 0; d < std::max(1, s.depth); d++) {
		for (int32_t i = 0; i < w; i++) {
			const int32_t along = first + i;
			switch (s.edge) {
				case Edge::NORTH: out.push_back(Coord{ox + along, oy + d}); break;
				case Edge::SOUTH: out.push_back(Coord{ox + along, oy + CELL_TILES - 1 - d}); break;
				case Edge::WEST: out.push_back(Coord{ox + d, oy + along}); break;
				default: out.push_back(Coord{ox + CELL_TILES - 1 - d, oy + along}); break;
			}
		}
	}
	return out;
}

std::vector<Problem> validate(const Template &t, const ValidateParams &p) {
	std::vector<Problem> list;
	Out out{list};
	if (t.footprint_w < 1 || t.footprint_h < 1 || t.footprint_w > 2 || t.footprint_h > 2 || t.cells.size() != static_cast<size_t>(t.footprint_w * t.footprint_h)) {
		out.add("footprint", -1, -1, "footprint must be a 1x1, 1x2, 2x1 or 2x2 rectangle with a cell for each place");
		return list;
	}
	MineMap mine;
	for (const Cell &c : t.cells) {
		mine.commit(std::make_unique<Cell>(c));
	}
	const Grid g = build_grid(t, mine);
	rule_connected(t, g, out);
	rule_widths(t, g, p, out);
	rule_rib(t, g, p, out);
	rule_tapper_reach(g, mine, p, out);
	rule_stubs(t, g, p, out);
	rule_zones(t, g, out);
	rule_collapses(t, g, p, out);
	rule_hooks(t, g, p, out);
	rule_landmark(t, p, out);
	rule_anchor_fit(t, g, mine, p, out);
	rule_poi(t, p, out);
	rule_fallback(t, p, out);
	rule_main_road(t, g, p, out);
	return list;
}

std::string describe(const Template &t, const Problem &problem) {
	// No iostreams: the extension links libstdc++ statically, and its stream locale is not ours.
	std::string s = "template " + t.id + ": " + problem.rule + ": ";
	if (problem.x >= 0) {
		s += "cell (" + std::to_string(problem.cell.x) + ", " + std::to_string(problem.cell.y) + ") tile (" + std::to_string(problem.x) + ", " + std::to_string(problem.y) + "): ";
	}
	return s + problem.message;
}

const char *kind_name(TemplateKind k) {
	return k < TemplateKind::COUNT ? KIND_NAMES[static_cast<size_t>(k)] : "";
}

std::optional<TemplateKind> kind_from(const std::string &name) {
	for (size_t i = 0; i < static_cast<size_t>(TemplateKind::COUNT); i++) {
		if (name == KIND_NAMES[i]) {
			return static_cast<TemplateKind>(i);
		}
	}
	return std::nullopt;
}

} // namespace lb::core::gen

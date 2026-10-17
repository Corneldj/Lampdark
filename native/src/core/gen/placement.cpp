#include "core/gen/placement.h"

#include "core/generated/hash_domains.h"
#include "core/rng/rng.h"
#include "core/world/materials.h"

#include <algorithm>
#include <set>

namespace lb::core::gen {

using lb::core::world::Anchor;
using lb::core::world::AnchorType;
using lb::core::world::Coord;

namespace hd = lb::core::hash_domain;

const char *placed_kind_name(PlacedKind kind) {
	static const char *const NAMES[] = {"item", "remains", "phone", "air_door", "collapse", "firedamp", "blackdamp", "man_trap",
			"staple_pit", "sump_mud", "coat_heap", "rich_rock", "landmark", "prop"};
	static_assert(sizeof(NAMES) / sizeof(NAMES[0]) == static_cast<size_t>(PlacedKind::COUNT), "a name for every kind");
	const size_t i = static_cast<size_t>(kind);
	return i < static_cast<size_t>(PlacedKind::COUNT) ? NAMES[i] : "";
}

namespace {

const char *const TOOLS[] = {"spanner", "hammer", "crowbar", "wire_cutters"};

uint64_t cell_hash(uint64_t seed, uint64_t domain, Coord cell, int64_t what, int64_t extra = 0) {
	const int64_t keys[4] = {cell.x, cell.y, what, extra};
	return hash_u64(seed, domain, keys, 4);
}

bool roll(uint64_t seed, uint64_t domain, Coord cell, int64_t what, int64_t ppm) {
	if (ppm <= 0) {
		return false;
	}
	return ppm >= 1000000 || static_cast<int64_t>(cell_hash(seed, domain, cell, what) % 1000000u) < ppm;
}

Rng stream(uint64_t seed, uint64_t domain, Coord cell, int64_t what) {
	return Rng(cell_hash(seed, domain, cell, what, 0x5157ull));
}

int64_t sq(int64_t v) { return v * v; }

int64_t dist2(Coord a, Coord b) { return sq(a.x - b.x) + sq(a.y - b.y); }

// Doubled coordinates make tile centres exact: (2x + 1, 2y + 1). Squared distance between two
// tile centres, in quarter tiles.
int64_t centre_dist2_x4(Coord a, Coord b) { return sq(2 * (a.x - b.x)) + sq(2 * (a.y - b.y)); }

Coord anchor_tile(const Layout &l, const Anchor &a) {
	return lb::core::world::tile_of(l.coord, {a.x, a.y});
}

std::vector<int32_t> anchors_of(const Layout &l, AnchorType type) {
	std::vector<int32_t> out;
	for (size_t i = 0; i < l.cell.anchors.size(); i++) {
		if (l.cell.anchors[i].type == type) {
			out.push_back(static_cast<int32_t>(i));
		}
	}
	return out;
}

bool has_tag(const Anchor &a, const std::string &tag) {
	return std::find(a.tags.begin(), a.tags.end(), tag) != a.tags.end();
}

bool is_floor(const Layout &l, int64_t lx, int64_t ly) {
	if (lx < 0 || ly < 0 || lx >= lb::core::world::CELL_TILES || ly >= lb::core::world::CELL_TILES) {
		return false;
	}
	return l.cell.tiles[static_cast<size_t>(lb::core::world::Cell::index_of(lx, ly))].material ==
			static_cast<uint8_t>(lb::core::world::TileMaterial::FLOOR);
}

// The floor tile nearest the cell's centre (ties by index): where a planned thing goes in a cell
// whose template has no anchor for it.
std::optional<Coord> centre_floor(const Layout &l) {
	std::optional<Coord> best;
	int64_t best_d = 0;
	for (int64_t y = 0; y < lb::core::world::CELL_TILES; y++) {
		for (int64_t x = 0; x < lb::core::world::CELL_TILES; x++) {
			if (!is_floor(l, x, y)) {
				continue;
			}
			const int64_t d = sq(2 * x + 1 - lb::core::world::CELL_TILES) + sq(2 * y + 1 - lb::core::world::CELL_TILES);
			if (!best || d < best_d) {
				best = lb::core::world::tile_of(l.coord, {x, y});
				best_d = d;
			}
		}
	}
	return best;
}

TileBox box_of(const Layout &l, const Anchor &a) {
	const Coord t = anchor_tile(l, a);
	return {t.x, t.y, a.w, a.h};
}

bool box_has(const TileBox &b, Coord t) { return t.x >= b.x && t.y >= b.y && t.x < b.x + b.w && t.y < b.y + b.h; }

// A box's centre in doubled tiles.
Coord box_centre_x2(const TileBox &b) { return {2 * b.x + b.w, 2 * b.y + b.h}; }

bool one_lamp(const RunHeader &h) { return h.hard_variant == "one_lamp"; }
bool dead_lines(const RunHeader &h) { return h.hard_variant == "dead_lines"; }

// The pit phones a cell has by its own roll (not its point of interest's, nor the near-gate ones).
std::vector<Placement> own_phones(const PlacementWorld &world, const PlacementParams &p, Coord cell, const Layout &l,
		const CellFacts &f, bool in_poi) {
	std::vector<Placement> out;
	const RunHeader &h = world.header();
	if (dead_lines(h) || f.base_camp || in_poi || f.ring <= 0) {
		return out;
	}
	const int64_t ppm = f.ring <= 2 ? p.phone_ring12_ppm : p.phone_beyond_ppm;
	if (!roll(h.seed, hd::GEN_PLACE_PHONE, cell, 0, ppm)) {
		return out;
	}
	std::vector<int32_t> sites;
	for (int32_t i : anchors_of(l, AnchorType::WALL_FIXTURE)) {
		const std::string &kind = l.cell.anchors[static_cast<size_t>(i)].kind;
		if (kind.empty() || kind == "phone") {
			sites.push_back(i);
		}
	}
	if (sites.empty()) {
		return out;
	}
	Rng r = stream(h.seed, hd::GEN_PLACE_PHONE, cell, 1);
	const int32_t a = sites[static_cast<size_t>(*r.range(0, static_cast<int64_t>(sites.size()) - 1))];
	Placement ph;
	ph.kind = PlacedKind::PHONE;
	ph.source = "phone";
	ph.anchor = a;
	ph.tile = anchor_tile(l, l.cell.anchors[static_cast<size_t>(a)]);
	out.push_back(ph);
	return out;
}

// A point of interest's door tiles: its door cell's socket on the door's side (the edge's middle
// without a layout).
std::vector<Coord> door_tiles(const PlacementWorld &world, const Poi &poi) {
	std::vector<Coord> out;
	const std::optional<Layout> l = world.layout(poi.door);
	const int32_t side = static_cast<int32_t>(poi.door_side);
	int32_t first = 9;
	int32_t width = 2;
	if (l && l->sockets[static_cast<size_t>(side)].open) {
		const Socket &s = l->sockets[static_cast<size_t>(side)];
		first = opening_first(s.offset, s.width);
		width = s.width;
	}
	for (int32_t i = 0; i < width; i++) {
		Coord local;
		switch (poi.door_side) {
			case Edge::NORTH:
				local = {first + i, 0};
				break;
			case Edge::SOUTH:
				local = {first + i, lb::core::world::CELL_TILES - 1};
				break;
			case Edge::WEST:
				local = {0, first + i};
				break;
			default:
				local = {lb::core::world::CELL_TILES - 1, first + i};
				break;
		}
		out.push_back(lb::core::world::tile_of(poi.door, local));
	}
	return out;
}

struct CollapseCandidate {
	Coord cell;
	uint32_t id = 0;
	std::vector<Coord> tiles; // standing and fallen
	uint64_t priority = 0;
};

// A cell's collapse candidate by its own roll and static rules (one alternate at most; never base
// camp or a spine; every tile 20 or more from base camp's cell): the cross-cell rules come after.
std::optional<CollapseCandidate> collapse_candidate(const PlacementWorld &world, const PlacementParams &p, Coord cell, const Layout &l,
		const CellFacts &f) {
	const RunHeader &h = world.header();
	if (f.base_camp || f.spine || l.cell.collapses.empty() || !roll(h.seed, hd::GEN_PLACE_COLLAPSE, cell, 0, p.collapse_ppm)) {
		return std::nullopt;
	}
	CollapseCandidate c;
	c.cell = cell;
	const size_t pick = static_cast<size_t>(cell_hash(h.seed, hd::GEN_PLACE_COLLAPSE, cell, 1) % l.cell.collapses.size());
	const lb::core::world::Collapse &alt = l.cell.collapses[pick];
	c.id = alt.id;
	std::set<uint16_t> seen;
	for (const auto *list : {&alt.standing, &alt.fallen}) {
		for (const lb::core::world::TileWrite &w : *list) {
			if (seen.insert(w.index).second) {
				c.tiles.push_back(lb::core::world::tile_of(cell, {w.index % lb::core::world::CELL_TILES, w.index / lb::core::world::CELL_TILES}));
			}
		}
	}
	if (c.tiles.empty()) {
		return std::nullopt;
	}
	// Base camp is cell (0, 0): tiles 0-19 both ways. The nearest of its tiles to each tile.
	const int64_t min2 = sq(p.collapse_min_from_basecamp);
	for (const Coord &t : c.tiles) {
		const int64_t nx = std::clamp<int64_t>(t.x, 0, lb::core::world::CELL_TILES - 1);
		const int64_t ny = std::clamp<int64_t>(t.y, 0, lb::core::world::CELL_TILES - 1);
		if (dist2(t, {nx, ny}) < min2) {
			return std::nullopt;
		}
	}
	c.priority = cell_hash(h.seed, hd::GEN_PLACE_COLLAPSE, cell, 2);
	return c;
}

bool within(const std::vector<Coord> &a, const std::vector<Coord> &b, int64_t tiles) {
	const int64_t lim = sq(tiles);
	for (const Coord &x : a) {
		for (const Coord &y : b) {
			if (dist2(x, y) < lim) {
				return true;
			}
		}
	}
	return false;
}

// One cell's pipeline.
class Placer {
public:
	Placer(const PlacementWorld &world, const PlacementParams &p, Coord cell, const Layout &l)
		: w_(world), p_(p), h_(world.header()), cell_(cell), l_(l), f_(world.facts(cell)), homes_(read_homes(world.header())) {
		poi_ = w_.poi_at(cell);
	}

	std::vector<Placement> run() {
		contents();
		landmark();
		phones();
		doors();
		collapse();
		gas();
		traps();
		remains();
		loose();
		heaps();
		rich_rock();
		exclusions();
		ids();
		return std::move(out_);
	}

private:
	const PlacementWorld &w_;
	const PlacementParams &p_;
	const RunHeader &h_;
	Coord cell_;
	const Layout &l_;
	CellFacts f_;
	Homes homes_;
	PoiRef poi_;
	std::vector<Placement> out_;
	std::set<int32_t> used_; // anchors already holding something

	Placement make(PlacedKind kind, const std::string &source, int32_t anchor, Coord tile) const {
		Placement x;
		x.kind = kind;
		x.source = source;
		x.anchor = anchor;
		x.tile = tile;
		return x;
	}

	Placement at_anchor(PlacedKind kind, const std::string &source, int32_t anchor) const {
		const Anchor &a = l_.cell.anchors[static_cast<size_t>(anchor)];
		Placement x = make(kind, source, anchor, anchor_tile(l_, a));
		return x;
	}

	Placement area(PlacedKind kind, const std::string &source, int32_t anchor) const {
		const Anchor &a = l_.cell.anchors[static_cast<size_t>(anchor)];
		Placement x = at_anchor(kind, source, anchor);
		x.w = a.w;
		x.h = a.h;
		return x;
	}

	// An anchor of `type` not yet used, by the stream; -1 if none.
	int32_t pick_free(Rng &r, AnchorType type) {
		std::vector<int32_t> free;
		for (int32_t i : anchors_of(l_, type)) {
			if (!used_.count(i)) {
				free.push_back(i);
			}
		}
		if (free.empty()) {
			return -1;
		}
		const int32_t a = free[static_cast<size_t>(*r.range(0, static_cast<int64_t>(free.size()) - 1))];
		used_.insert(a);
		return a;
	}

	void found_lamp(Rng &r, Placement &x) const {
		x.thing = "gauze_lamp";
		x.oil_milli = static_cast<int32_t>(*r.range(p_.found_oil_min_milli, p_.found_oil_max_milli));
		x.notches = static_cast<int32_t>(*r.range(p_.found_notches_min, p_.found_notches_max));
	}

	// 1. GEN-09's contents whose slot lies here, the plan's revolver and boxes.
	void contents() {
		if (poi_) {
			const Poi &poi = *poi_;
			const std::vector<TileRect> slots = poi.slots();
			const std::vector<Content> lines = w_.contents(poi);
			std::map<int32_t, int32_t> placed_at; // contents index -> our index
			std::map<int32_t, int32_t> on_slot; // things laid on each line so far
			int32_t phone_anchor = -1;
			for (int32_t i : anchors_of(l_, AnchorType::WALL_FIXTURE)) {
				if (l_.cell.anchors[static_cast<size_t>(i)].kind == "phone") {
					phone_anchor = i;
					break;
				}
			}
			for (size_t i = 0; i < lines.size(); i++) {
				const Content &k = lines[i];
				Coord tile;
				int32_t anchor = -1;
				if (k.line < 0) {
					if (phone_anchor < 0) {
						continue; // the phone's wall fixture is in another of its cells
					}
					anchor = phone_anchor;
					tile = anchor_tile(l_, l_.cell.anchors[static_cast<size_t>(anchor)]);
				} else {
					if (static_cast<size_t>(k.line) >= slots.size()) {
						continue;
					}
					const TileRect &s = slots[static_cast<size_t>(k.line)];
					if (lb::core::world::cell_of({s.x, s.y}) != cell_) {
						continue;
					}
					const int32_t n = on_slot[k.line]++;
					const int32_t area = std::max(1, s.w * s.h);
					tile = {s.x + (n % area) % std::max(1, s.w), s.y + (n % area) / std::max(1, s.w)};
				}
				Placement x = make(PlacedKind::ITEM, "poi", anchor, tile);
				x.thing = k.thing;
				x.oil_milli = k.oil_milli;
				x.notches = k.notches;
				if (k.thing == "remains") {
					x.kind = PlacedKind::REMAINS;
					x.thing = "";
				} else if (k.thing == "phone") {
					x.kind = PlacedKind::PHONE;
					x.thing = "";
				} else if (k.thing == "coats") {
					x.kind = PlacedKind::COAT_HEAP;
					x.thing = "";
				} else if (k.thing == "lore" || k.thing == "brass_checks") {
					x.kind = PlacedKind::PROP;
				}
				if (k.with >= 0) {
					const auto it = placed_at.find(k.with);
					if (it == placed_at.end()) {
						continue; // its remains lie in another of its cells
					}
					x.with = it->second;
				}
				placed_at[static_cast<int32_t>(i)] = static_cast<int32_t>(out_.size());
				out_.push_back(x);
			}
		}
		// GEN-08: the revolver on a deputy's remains, each box at an item anchor, on spine cells.
		if (h_.plan.revolver && h_.plan.revolver_cell == cell_) {
			Rng r = stream(h_.seed, hd::GEN_PLACE_CONTENTS, cell_, 1);
			int32_t a = pick_free(r, AnchorType::REMAINS);
			if (a < 0) {
				a = pick_free(r, AnchorType::ITEM);
			}
			std::optional<Coord> t = a >= 0 ? std::optional<Coord>(anchor_tile(l_, l_.cell.anchors[static_cast<size_t>(a)])) : centre_floor(l_);
			if (t) {
				Placement deputy = make(PlacedKind::REMAINS, "plan", a, *t);
				deputy.thing = "deputy";
				out_.push_back(deputy);
				Placement gun = make(PlacedKind::ITEM, "plan", a, *t);
				gun.thing = "revolver";
				gun.count = static_cast<int32_t>(p_.revolver_rounds);
				gun.with = static_cast<int32_t>(out_.size()) - 1;
				out_.push_back(gun);
			}
		}
		int64_t box = 0;
		for (const Coord &c : h_.plan.box_cells) {
			if (c != cell_) {
				box++;
				continue;
			}
			Rng r = stream(h_.seed, hd::GEN_PLACE_CONTENTS, cell_, 2 + box);
			const int32_t a = pick_free(r, AnchorType::ITEM);
			std::optional<Coord> t = a >= 0 ? std::optional<Coord>(anchor_tile(l_, l_.cell.anchors[static_cast<size_t>(a)])) : centre_floor(l_);
			if (t) {
				Placement rounds = make(PlacedKind::ITEM, "plan", a, *t);
				rounds.thing = "rounds";
				rounds.count = static_cast<int32_t>(p_.box_rounds);
				out_.push_back(rounds);
			}
			box++;
		}
	}

	// The landmark: one a cell, at its first landmark site.
	void landmark() {
		const std::vector<int32_t> sites = anchors_of(l_, AnchorType::LANDMARK);
		if (sites.empty()) {
			return;
		}
		Placement x = at_anchor(PlacedKind::LANDMARK, "landmark", sites[0]);
		x.thing = l_.cell.anchors[static_cast<size_t>(sites[0])].kind;
		x.variant = landmark_variant(h_.seed, cell_, p_.landmark_palette, p_.landmark_no_repeat_cells);
		out_.push_back(x);
	}

	// 2. Pit phones: the near-gate ones the homes pass placed, then the cell's own roll.
	void phones() {
		if (dead_lines(h_)) {
			return;
		}
		for (const Coord &t : homes_.gate_phones) {
			if (lb::core::world::cell_of(t) == cell_) {
				out_.push_back(make(PlacedKind::PHONE, "home", -1, t));
			}
		}
		for (Placement &x : own_phones(w_, p_, cell_, l_, f_, static_cast<bool>(poi_))) {
			used_.insert(x.anchor);
			out_.push_back(x);
		}
	}

	// 3. Air doors: about one in three door sites on side passages off a main road (a main-road
	// cell, or one open to a main road).
	void doors() {
		if (poi_) {
			return;
		}
		bool off_main = f_.main_road;
		for (int e = 0; e < 4 && !off_main; e++) {
			if (l_.sockets[static_cast<size_t>(e)].open && w_.facts(neighbour(cell_, static_cast<Edge>(e))).main_road) {
				off_main = true;
			}
		}
		if (!off_main) {
			return;
		}
		for (int32_t a : anchors_of(l_, AnchorType::DOOR_SITE)) {
			if (roll(h_.seed, hd::GEN_PLACE_DOOR, cell_, a, p_.air_door_ppm)) {
				out_.push_back(area(PlacedKind::AIR_DOOR, "door", a));
				used_.insert(a);
			}
		}
	}

	// 4. Collapse arming, one alternate at most, then the cross-cell rules over the 3x3 cells: 7 or
	// more tiles (straight line, so never fewer by path) from every pit phone and point-of-interest
	// door, 12 or more from every nearby candidate of a higher priority.
	void collapse() {
		const std::optional<CollapseCandidate> mine = collapse_candidate(w_, p_, cell_, l_, f_);
		if (!mine) {
			return;
		}
		std::vector<Coord> sites;
		std::set<std::pair<Coord, int32_t>> doors_seen;
		for (const Coord &t : homes_.gate_phones) {
			sites.push_back(t);
		}
		for (int64_t dy = -1; dy <= 1; dy++) {
			for (int64_t dx = -1; dx <= 1; dx++) {
				const Coord n{cell_.x + dx, cell_.y + dy};
				const std::optional<Layout> nl = (dx == 0 && dy == 0) ? std::optional<Layout>(l_) : w_.layout(n);
				const PoiRef np = (dx == 0 && dy == 0) ? poi_ : w_.poi_at(n);
				if (nl) {
					const CellFacts nf = (dx == 0 && dy == 0) ? f_ : w_.facts(n);
					for (const Placement &ph : own_phones(w_, p_, n, *nl, nf, static_cast<bool>(np))) {
						sites.push_back(ph.tile);
					}
					// A point of interest's own phone at its phone fixture.
					if (np && !dead_lines(h_)) {
						for (int32_t i : anchors_of(*nl, AnchorType::WALL_FIXTURE)) {
							if (nl->cell.anchors[static_cast<size_t>(i)].kind == "phone") {
								sites.push_back(anchor_tile(*nl, nl->cell.anchors[static_cast<size_t>(i)]));
							}
						}
					}
				}
				if (np && doors_seen.insert({np->door, static_cast<int32_t>(np->door_side)}).second) {
					for (const Coord &t : door_tiles(w_, *np)) {
						sites.push_back(t);
					}
				}
			}
		}
		if (within(mine->tiles, sites, p_.collapse_min_from_sites)) {
			return;
		}
		for (int64_t dy = -1; dy <= 1; dy++) {
			for (int64_t dx = -1; dx <= 1; dx++) {
				if (dx == 0 && dy == 0) {
					continue;
				}
				const Coord n{cell_.x + dx, cell_.y + dy};
				const std::optional<Layout> nl = w_.layout(n);
				if (!nl) {
					continue;
				}
				const std::optional<CollapseCandidate> other = collapse_candidate(w_, p_, n, *nl, w_.facts(n));
				if (!other || !within(mine->tiles, other->tiles, p_.collapse_min_spacing)) {
					continue;
				}
				const bool beats = other->priority != mine->priority ? other->priority > mine->priority : n < cell_;
				if (beats) {
					return;
				}
			}
		}
		Coord lo = mine->tiles[0];
		Coord hi = mine->tiles[0];
		for (const Coord &t : mine->tiles) {
			lo = {std::min(lo.x, t.x), std::min(lo.y, t.y)};
			hi = {std::max(hi.x, t.x), std::max(hi.y, t.y)};
		}
		Placement x = make(PlacedKind::COLLAPSE, "collapse", -1, lo);
		x.w = static_cast<int32_t>(hi.x - lo.x + 1);
		x.h = static_cast<int32_t>(hi.y - lo.y + 1);
		x.collapse = mine->id;
		out_.push_back(x);
		collapse_tiles_ = mine->tiles;
	}

	std::vector<Coord> collapse_tiles_;

	// 5. Gas: firedamp pockets from ring 2 (about one a cell in the Black Seam), blackdamp runs in
	// the Old Workings; never in ring 0, on a spine or in a point of interest.
	void gas() {
		if (f_.base_camp || f_.ring <= 0 || f_.spine || poi_) {
			return;
		}
		int64_t ppm = 0;
		if (f_.biome == "black_seam") {
			ppm = p_.firedamp_black_seam_ppm;
		} else if (f_.ring == 2) {
			ppm = p_.firedamp_ring2_ppm;
		} else if (f_.ring >= 3) {
			ppm = p_.firedamp_beyond_ppm;
		}
		if (roll(h_.seed, hd::GEN_PLACE_GAS, cell_, 0, ppm)) {
			Rng r = stream(h_.seed, hd::GEN_PLACE_GAS, cell_, 1);
			const int32_t a = pick_free(r, AnchorType::GAS_AREA);
			if (a >= 0) {
				out_.push_back(area(PlacedKind::FIREDAMP, "gas", a));
			}
		}
		if (f_.biome == "old_workings" && roll(h_.seed, hd::GEN_PLACE_GAS, cell_, 2, p_.blackdamp_ppm)) {
			// Dead ends first: a run tagged dead_end before any other.
			std::vector<int32_t> runs;
			for (int32_t i : anchors_of(l_, AnchorType::GAS_DEAD_END)) {
				if (has_tag(l_.cell.anchors[static_cast<size_t>(i)], "dead_end")) {
					runs.push_back(i);
				}
			}
			if (runs.empty()) {
				runs = anchors_of(l_, AnchorType::GAS_DEAD_END);
			}
			if (!runs.empty()) {
				Rng r = stream(h_.seed, hd::GEN_PLACE_GAS, cell_, 3);
				const int32_t a = runs[static_cast<size_t>(*r.range(0, static_cast<int64_t>(runs.size()) - 1))];
				used_.insert(a);
				out_.push_back(area(PlacedKind::BLACKDAMP, "gas", a));
			}
		}
	}

	// 6. Traps (none in ring 0, nor below traps_min_ring in a staged run 1): man-traps at trap sites
	// from ring 2 and HAZ-01's on the lair's approaches; staple pits in the Old Workings; sump mud
	// on low roads.
	void traps() {
		const int64_t floor_ring = std::max<int64_t>(1, staged_value(h_, p_.staged_traps_min_ring, p_.traps_min_ring));
		if (f_.base_camp || f_.ring < floor_ring) {
			return;
		}
		if (f_.ring >= p_.man_trap_min_ring && roll(h_.seed, hd::GEN_PLACE_TRAP, cell_, 0, p_.man_trap_ppm)) {
			Rng r = stream(h_.seed, hd::GEN_PLACE_TRAP, cell_, 1);
			const int32_t a = pick_free(r, AnchorType::TRAP_SITE);
			if (a >= 0) {
				out_.push_back(at_anchor(PlacedKind::MAN_TRAP, "trap", a));
			}
		}
		if (p_.lair_traps) {
			for (Placement x : p_.lair_traps(w_, cell_)) {
				x.source = "trap";
				out_.push_back(x);
			}
		}
		if (f_.biome == "old_workings" && f_.ring >= p_.staple_pit_min_ring && roll(h_.seed, hd::GEN_PLACE_TRAP, cell_, 2, p_.staple_pit_ppm)) {
			Rng r = stream(h_.seed, hd::GEN_PLACE_TRAP, cell_, 3);
			const int32_t a = pick_free(r, AnchorType::TRAP_SITE);
			if (a >= 0) {
				out_.push_back(at_anchor(PlacedKind::STAPLE_PIT, "trap", a));
			}
		}
		if (f_.ring >= p_.sump_mud_min_ring && roll(h_.seed, hd::GEN_PLACE_TRAP, cell_, 4, p_.sump_mud_ppm)) {
			Rng r = stream(h_.seed, hd::GEN_PLACE_TRAP, cell_, 5);
			const int32_t a = pick_free(r, AnchorType::LOW_ROAD);
			if (a >= 0) {
				out_.push_back(area(PlacedKind::SUMP_MUD, "trap", a));
			}
		}
	}

	// 7. The men in-bye's remains: about one in six cells of rings 1-3, at a remains anchor, with
	// what the man carried (the table's rolls in order, the first two kept; never a lamp under One Lamp).
	void remains() {
		if (f_.base_camp || poi_ || f_.ring < p_.remains_ring_min || f_.ring > p_.remains_ring_max ||
				!roll(h_.seed, hd::GEN_PLACE_REMAINS, cell_, 0, p_.remains_ppm)) {
			return;
		}
		Rng r = stream(h_.seed, hd::GEN_PLACE_REMAINS, cell_, 1);
		const int32_t a = pick_free(r, AnchorType::REMAINS);
		if (a < 0) {
			return;
		}
		const int32_t at = static_cast<int32_t>(out_.size());
		out_.push_back(at_anchor(PlacedKind::REMAINS, "remains", a));
		int64_t held = 0;
		for (const auto &[name, ppm] : p_.remains_items) {
			const bool got = r.chance_ppm(ppm);
			if (!got || held >= p_.remains_items_max) {
				continue;
			}
			Placement x = at_anchor(PlacedKind::ITEM, "remains", a);
			x.with = at;
			if (name == "lamp") {
				if (one_lamp(h_)) {
					continue;
				}
				found_lamp(r, x);
			} else if (name == "kit") {
				x.thing = "healing_kit";
			} else if (name == "tool") {
				x.thing = TOOLS[*r.range(0, 3)];
			} else {
				x.thing = name;
			}
			out_.push_back(x);
			held++;
		}
	}

	// 8. Loose finds: single paraffin cans in rings 1-2 at an item anchor, and the electric lamp in
	// the cell the homes pass named.
	void loose() {
		if (f_.base_camp) {
			return;
		}
		if (!poi_ && f_.ring >= p_.paraffin_ring_min && f_.ring <= p_.paraffin_ring_max &&
				roll(h_.seed, hd::GEN_PLACE_LOOSE, cell_, 0, p_.paraffin_ppm)) {
			Rng r = stream(h_.seed, hd::GEN_PLACE_LOOSE, cell_, 1);
			const int32_t a = pick_free(r, AnchorType::ITEM);
			if (a >= 0) {
				Placement x = at_anchor(PlacedKind::ITEM, "loose", a);
				x.thing = "paraffin_can";
				out_.push_back(x);
			}
		}
		if (homes_.electric_lamp && *homes_.electric_lamp == cell_ && !one_lamp(h_)) {
			int32_t a = -1;
			for (AnchorType type : {AnchorType::REMAINS, AnchorType::ITEM}) {
				for (int32_t i : anchors_of(l_, type)) {
					if (!used_.count(i)) {
						a = i;
						break;
					}
				}
				if (a >= 0) {
					break;
				}
			}
			const std::optional<Coord> t = a >= 0 ? std::optional<Coord>(anchor_tile(l_, l_.cell.anchors[static_cast<size_t>(a)])) : centre_floor(l_);
			if (t) {
				Placement x = make(PlacedKind::ITEM, "home", a, *t);
				x.thing = "electric_lamp";
				out_.push_back(x);
				if (a >= 0) {
					used_.insert(a);
				}
			}
		}
	}

	// Coat heaps in a chamber: `n` of its floor tiles against its walls, by the stream.
	void heap_chamber(int32_t anchor, int64_t n, Rng &r) {
		const Anchor &a = l_.cell.anchors[static_cast<size_t>(anchor)];
		std::vector<Coord> wall;
		for (int32_t y = a.y; y < a.y + a.h; y++) {
			for (int32_t x = a.x; x < a.x + a.w; x++) {
				if (!is_floor(l_, x, y)) {
					continue;
				}
				if (!is_floor(l_, x - 1, y) || !is_floor(l_, x + 1, y) || !is_floor(l_, x, y - 1) || !is_floor(l_, x, y + 1)) {
					wall.push_back({x, y});
				}
			}
		}
		r.shuffle(wall);
		for (int64_t i = 0; i < n && i < static_cast<int64_t>(wall.size()); i++) {
			Placement x = make(PlacedKind::COAT_HEAP, "heap", anchor, lb::core::world::tile_of(cell_, wall[static_cast<size_t>(i)]));
			out_.push_back(x);
		}
	}

	// Coat heaps: the roosts the homes pass chose, about half the chambers within 80 tiles of the
	// hoard and 5% elsewhere; 3-6 a chamber, more nearer the hoard (Proposed).
	void heaps() {
		if (f_.base_camp || poi_) {
			return;
		}
		for (int32_t i : anchors_of(l_, AnchorType::CHAMBER)) {
			const TileBox b = box_of(l_, l_.cell.anchors[static_cast<size_t>(i)]);
			const bool roost = std::find(homes_.roosts.begin(), homes_.roosts.end(), b) != homes_.roosts.end();
			int64_t near_x4 = -1; // squared doubled distance to the hoard
			if (homes_.hoard) {
				const Coord c = box_centre_x2(b);
				const Coord hc{2 * homes_.hoard->x + 1, 2 * homes_.hoard->y + 1};
				near_x4 = dist2(c, hc);
			}
			const int64_t lim_x4 = sq(2 * p_.coat_heap_near_hoard);
			const bool near = near_x4 >= 0 && near_x4 <= lim_x4;
			if (!roost && !roll(h_.seed, hd::GEN_PLACE_HEAP, cell_, i, near ? p_.coat_heap_near_ppm : p_.coat_heap_far_ppm)) {
				continue;
			}
			// More nearer the hoard: the count falls from the maximum at the hoard to the minimum at
			// 80 tiles and beyond, the most k with d <= near * (span - k) / span (squared: exact).
			int64_t n = p_.coat_heaps_min;
			if (near) {
				const int64_t span = std::max<int64_t>(0, p_.coat_heaps_max - p_.coat_heaps_min);
				for (int64_t k = span; k >= 0; k--) {
					if (near_x4 * sq(span) <= lim_x4 * sq(span - k)) {
						n = p_.coat_heaps_min + k;
						break;
					}
				}
			}
			Rng r = stream(h_.seed, hd::GEN_PLACE_HEAP, cell_, 1000 + i);
			heap_chamber(i, n, r);
		}
	}

	// Tapper-rich rock: in each of the region's picked cells, its thickest rich_rock anchor.
	void rich_rock() {
		if (f_.base_camp) {
			return;
		}
		const Coord region = lb::core::world::region_of_cell(cell_);
		const std::vector<Coord> picks = rich_rock_cells(h_.seed, region, p_.rich_rock_per_region);
		if (std::find(picks.begin(), picks.end(), cell_) == picks.end()) {
			return;
		}
		int32_t best = -1;
		int32_t best_t = 0;
		for (int32_t i : anchors_of(l_, AnchorType::RICH_ROCK)) {
			const Anchor &a = l_.cell.anchors[static_cast<size_t>(i)];
			const int32_t t = std::min(a.w, a.h);
			if (t >= p_.rich_rock_min_thickness && t > best_t) {
				best = i;
				best_t = t;
			}
		}
		if (best >= 0) {
			out_.push_back(area(PlacedKind::RICH_ROCK, "rich_rock", best));
		}
	}

	// 9. The exclusions, absolute: nothing on an armed collapse's tiles; no remains (nor what they
	// carried) in blackdamp; no gas or trap in ring 0; no gas on a spine or in a point of interest;
	// no trap below a staged run 1's ring; no lamp under One Lamp; no phone under Dead Lines.
	void exclusions() {
		std::vector<bool> drop(out_.size(), false);
		std::vector<TileBox> blackdamp;
		for (const Placement &x : out_) {
			if (x.kind == PlacedKind::BLACKDAMP) {
				blackdamp.push_back({x.tile.x, x.tile.y, x.w, x.h});
			}
		}
		const int64_t trap_floor = std::max<int64_t>(1, staged_value(h_, p_.staged_traps_min_ring, p_.traps_min_ring));
		for (size_t i = 0; i < out_.size(); i++) {
			const Placement &x = out_[i];
			if (x.kind == PlacedKind::COLLAPSE) {
				continue;
			}
			bool on_collapse = false;
			for (const Coord &t : collapse_tiles_) {
				if (x.covers(t)) {
					on_collapse = true;
					break;
				}
			}
			const bool gas = x.kind == PlacedKind::FIREDAMP || x.kind == PlacedKind::BLACKDAMP;
			const bool trap = x.kind == PlacedKind::MAN_TRAP || x.kind == PlacedKind::STAPLE_PIT || x.kind == PlacedKind::SUMP_MUD;
			const bool lamp = x.kind == PlacedKind::ITEM && (x.thing == "gauze_lamp" || x.thing == "electric_lamp");
			bool in_blackdamp = false;
			if (x.kind == PlacedKind::REMAINS) {
				for (const TileBox &b : blackdamp) {
					if (box_has(b, x.tile)) {
						in_blackdamp = true;
					}
				}
			}
			if (on_collapse || in_blackdamp || ((gas || trap) && f_.ring <= 0) || (gas && (f_.spine || poi_)) || (trap && f_.ring < trap_floor) ||
					(lamp && one_lamp(h_)) || (x.kind == PlacedKind::PHONE && dead_lines(h_))) {
				drop[i] = true;
			}
		}
		// What a dropped remains carried goes with it.
		for (size_t i = 0; i < out_.size(); i++) {
			if (out_[i].with >= 0 && drop[static_cast<size_t>(out_[i].with)]) {
				drop[i] = true;
			}
		}
		std::vector<Placement> kept;
		std::vector<int32_t> now(out_.size(), -1);
		for (size_t i = 0; i < out_.size(); i++) {
			if (!drop[i]) {
				now[i] = static_cast<int32_t>(kept.size());
				kept.push_back(out_[i]);
			}
		}
		for (Placement &x : kept) {
			if (x.with >= 0) {
				x.with = now[static_cast<size_t>(x.with)];
			}
		}
		out_ = std::move(kept);
	}

	// Each placement's GEN-13 key: the cell, its kind, its anchor and its ordinal among those.
	void ids() {
		std::map<std::pair<int32_t, int32_t>, int64_t> ordinal;
		for (Placement &x : out_) {
			const int64_t n = ordinal[{static_cast<int32_t>(x.kind), x.anchor}]++;
			const int64_t keys[5] = {cell_.x, cell_.y, static_cast<int64_t>(x.kind), x.anchor, n};
			x.id = hash_u64(h_.seed, hd::GEN_PLACE_ID, keys, 5);
		}
	}
};

} // namespace

int64_t staged_value(const RunHeader &header, const std::vector<int64_t> &table, int64_t plain) {
	if (plain > 0) {
		return plain;
	}
	if (header.staging.size() != 1 || header.staging[0] < '1' || header.staging[0] > '9') {
		return 0;
	}
	const size_t stage = static_cast<size_t>(header.staging[0] - '1');
	return stage < table.size() ? table[stage] : 0;
}

std::vector<Placement> place_cell(const PlacementWorld &world, const PlacementParams &params, Coord cell) {
	if (cell == Coord{0, 0}) {
		return {};
	}
	const std::optional<Layout> l = world.layout(cell);
	if (!l || l->base_camp) {
		return {};
	}
	return Placer(world, params, cell, *l).run();
}

uint64_t placement_digest(const std::vector<Placement> &list) {
	uint64_t h = mix64(list.size() + 1);
	for (const Placement &x : list) {
		const int64_t keys[] = {static_cast<int64_t>(x.kind), x.anchor, x.tile.x, x.tile.y, x.w, x.h, x.count, x.oil_milli,
				x.notches, x.variant, static_cast<int64_t>(x.collapse), x.with, static_cast<int64_t>(x.id)};
		h = mix64(h ^ hash_u64(h, 0, keys, sizeof(keys) / sizeof(keys[0])));
		for (char ch : x.thing) {
			h = mix64(h ^ static_cast<uint8_t>(ch));
		}
	}
	return h;
}

int32_t landmark_variant(uint64_t seed, Coord cell, int64_t palette, int64_t no_repeat) {
	// A lattice of period 2n + 1: two cells within n (Chebyshev) differ in x or y modulo the
	// period, so their colours differ; the run's permutation of the palette names each colour.
	const int64_t period = 2 * std::max<int64_t>(0, no_repeat) + 1;
	const int64_t colours = period * period;
	const int64_t entries = std::max(palette, colours);
	std::vector<int32_t> perm(static_cast<size_t>(entries));
	for (int64_t i = 0; i < entries; i++) {
		perm[static_cast<size_t>(i)] = static_cast<int32_t>(i);
	}
	const int64_t key = 0;
	Rng r(hash_u64(seed, hd::GEN_PLACE_LANDMARK, &key, 1));
	r.shuffle(perm);
	const int64_t colour = lb::core::world::floor_mod(cell.x, period) + period * lb::core::world::floor_mod(cell.y, period);
	return perm[static_cast<size_t>(colour)];
}

std::vector<Coord> rich_rock_cells(uint64_t seed, Coord region, int64_t per_region) {
	const int64_t n = lb::core::world::REGION_CELLS;
	std::vector<int32_t> order(static_cast<size_t>(n * n));
	for (int32_t i = 0; i < static_cast<int32_t>(order.size()); i++) {
		order[static_cast<size_t>(i)] = i;
	}
	const int64_t keys[3] = {region.x, region.y, 0};
	Rng r(hash_u64(seed, hd::GEN_PLACE_RICH_ROCK, keys, 3));
	r.shuffle(order);
	std::vector<Coord> out;
	for (int64_t i = 0; i < per_region && i < static_cast<int64_t>(order.size()); i++) {
		const Coord c{region.x * n + order[static_cast<size_t>(i)] % n, region.y * n + order[static_cast<size_t>(i)] / n};
		if (c != Coord{0, 0}) {
			out.push_back(c);
		}
	}
	std::sort(out.begin(), out.end());
	return out;
}

std::vector<TileBox> rich_rock_masses(const PlacementWorld &world, const PlacementParams &params, Coord region) {
	std::vector<TileBox> out;
	for (const Coord &c : rich_rock_cells(world.header().seed, region, params.rich_rock_per_region)) {
		const std::optional<Layout> l = world.layout(c);
		if (!l || l->base_camp) {
			continue;
		}
		int32_t best = -1;
		int32_t best_t = 0;
		for (int32_t i : anchors_of(*l, AnchorType::RICH_ROCK)) {
			const Anchor &a = l->cell.anchors[static_cast<size_t>(i)];
			const int32_t t = std::min(a.w, a.h);
			if (t >= params.rich_rock_min_thickness && t > best_t) {
				best = i;
				best_t = t;
			}
		}
		if (best >= 0) {
			out.push_back(box_of(*l, l->cell.anchors[static_cast<size_t>(best)]));
		}
	}
	return out;
}

std::map<std::string, int64_t> find_counts(const std::vector<std::vector<Placement>> &cells) {
	std::map<std::string, int64_t> out;
	for (const std::vector<Placement> &list : cells) {
		for (const Placement &x : list) {
			std::string key = placed_kind_name(x.kind);
			if (x.kind == PlacedKind::ITEM || x.kind == PlacedKind::PROP) {
				key += ":" + x.thing;
			}
			out[key] += 1;
		}
	}
	return out;
}

} // namespace lb::core::gen

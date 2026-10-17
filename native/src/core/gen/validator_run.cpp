#include "core/gen/validator.h"

#include <algorithm>
#include <cstdlib>
#include <deque>
#include <queue>
#include <tuple>

namespace lb::core::gen {

using lb::core::world::Cell;
using lb::core::world::CELL_TILES;
using lb::core::world::Coord;
using lb::core::world::TileMaterial;

namespace {

Verdict fail(Check check, Coord tile, std::string detail) {
	Verdict v;
	v.check = check;
	v.tile = tile;
	v.detail = std::move(detail);
	return v;
}

bool passable(uint8_t material) { return walk_passable(material); }

Coord middle_of(Coord cell) { return lb::core::world::tile_of(cell, {CELL_TILES / 2, CELL_TILES / 2}); }

std::vector<Coord> opening_tiles(Coord cell, const Socket &s, Edge side) { return socket_opening_tiles(cell, s, side); }

// Floor over a set of cells (doors open).
struct Floor {
	std::map<Coord, Cell> cells;
	bool walkable(Coord t) const {
		const auto it = cells.find(lb::core::world::cell_of(t));
		if (it == cells.end()) {
			return false;
		}
		const Coord l = lb::core::world::local_of(t);
		return passable(it->second.tiles[static_cast<size_t>(Cell::index_of(l.x, l.y))].material);
	}
	// The tiles reached 4-connected from `from` (the walkable ones).
	std::set<Coord> flood(const std::vector<Coord> &from) const {
		std::set<Coord> seen;
		std::deque<Coord> q;
		for (const Coord &t : from) {
			if (walkable(t) && seen.insert(t).second) {
				q.push_back(t);
			}
		}
		while (!q.empty()) {
			const Coord t = q.front();
			q.pop_front();
			const Coord next[4] = {{t.x + 1, t.y}, {t.x - 1, t.y}, {t.x, t.y + 1}, {t.x, t.y - 1}};
			for (const Coord &n : next) {
				if (walkable(n) && seen.insert(n).second) {
					q.push_back(n);
				}
			}
		}
		return seen;
	}
};

} // namespace

bool walk_passable(uint8_t material) {
	const TileMaterial m = static_cast<TileMaterial>(material);
	return m == TileMaterial::FLOOR || m == TileMaterial::STEEL || m == TileMaterial::WOODEN_DOOR;
}

std::vector<Coord> socket_opening_tiles(Coord cell, const Socket &s, Edge side) {
	std::vector<Coord> out;
	if (!s.open) {
		return out;
	}
	const int64_t first = opening_first(s.offset, s.width);
	for (int64_t a = first; a < first + s.width; a++) {
		Coord local;
		switch (side) {
			case Edge::NORTH:
				local = {a, 0};
				break;
			case Edge::SOUTH:
				local = {a, CELL_TILES - 1};
				break;
			case Edge::WEST:
				local = {0, a};
				break;
			default:
				local = {CELL_TILES - 1, a};
				break;
		}
		out.push_back(lb::core::world::tile_of(cell, local));
	}
	return out;
}

RouteHome route_home(const PlacementWorld &world, Coord from, int32_t max_cells, int64_t max_explored) {
	RouteHome out;
	const RunHeader &h = world.header();
	std::set<Coord> goals;
	for (int32_t e = 0; e < 4; e++) {
		const std::optional<Socket> s = h.forced.query(edge_of({0, 0}, static_cast<Edge>(e)));
		if (!s || !s->open) {
			continue;
		}
		const Coord cell = neighbour({0, 0}, static_cast<Edge>(e));
		const std::optional<Layout> l = world.layout(cell);
		if (!l || l->base_camp) {
			continue;
		}
		const Edge in = opposite(static_cast<Edge>(e));
		for (const Coord &t : opening_tiles(cell, l->sockets[static_cast<size_t>(in)], in)) {
			goals.insert(t);
		}
	}
	if (goals.empty()) {
		return out;
	}
	std::map<Coord, std::optional<Cell>> cells;
	const auto cell_at = [&](Coord c) -> const Cell * {
		auto it = cells.find(c);
		if (it == cells.end()) {
			std::optional<Cell> got;
			if (std::max(std::abs(c.x), std::abs(c.y)) <= max_cells) {
				const std::optional<Layout> l = world.layout(c);
				if (l && !l->base_camp) {
					got = l->cell;
				}
			}
			it = cells.emplace(c, std::move(got)).first;
		}
		return it->second ? &*it->second : nullptr;
	};
	const auto walkable = [&](Coord t) -> bool {
		const Cell *cell = cell_at(lb::core::world::cell_of(t));
		if (cell == nullptr) {
			return false;
		}
		const Coord l = lb::core::world::local_of(t);
		return passable(cell->tiles[static_cast<size_t>(Cell::index_of(l.x, l.y))].material);
	};
	const auto estimate = [&goals](Coord t) -> int64_t {
		int64_t best = INT64_MAX;
		for (const Coord &g : goals) {
			best = std::min(best, std::abs(t.x - g.x) + std::abs(t.y - g.y));
		}
		return best;
	};
	// A*, ordered by (f, h, y, x) so ties break the same way everywhere.
	using Key = std::tuple<int64_t, int64_t, int64_t, int64_t>;
	std::priority_queue<Key, std::vector<Key>, std::greater<Key>> open;
	std::map<Coord, int64_t> cost;
	std::map<Coord, Coord> came;
	std::vector<Coord> starts;
	if (walkable(from)) {
		starts.push_back(from);
	} else {
		for (const Coord &n : {Coord{from.x + 1, from.y}, Coord{from.x, from.y + 1}, Coord{from.x - 1, from.y}, Coord{from.x, from.y - 1}}) {
			if (walkable(n)) {
				starts.push_back(n);
			}
		}
	}
	for (const Coord &s : starts) {
		cost[s] = 0;
		const int64_t e = estimate(s);
		open.push({e, e, s.y, s.x});
	}
	bool found = false;
	Coord reached = from;
	while (!open.empty()) {
		const auto [f, est, y, x] = open.top();
		open.pop();
		const Coord t{x, y};
		const int64_t g = cost[t];
		if (f != g + est) {
			continue; // a stale entry: a shorter way here was found since
		}
		if (goals.count(t) != 0) {
			found = true;
			reached = t;
			break;
		}
		if (++out.explored > max_explored) {
			break;
		}
		for (const Coord &n : {Coord{t.x + 1, t.y}, Coord{t.x, t.y + 1}, Coord{t.x - 1, t.y}, Coord{t.x, t.y - 1}}) {
			if (!walkable(n)) {
				continue;
			}
			const auto it = cost.find(n);
			if (it != cost.end() && it->second <= g + 1) {
				continue;
			}
			cost[n] = g + 1;
			came[n] = t;
			const int64_t e = estimate(n);
			open.push({g + 1 + e, e, n.y, n.x});
		}
	}
	if (!found) {
		return out;
	}
	for (Coord t = reached;;) {
		out.tiles.push_back(t);
		const auto it = came.find(t);
		if (it == came.end()) {
			break;
		}
		t = it->second;
	}
	std::reverse(out.tiles.begin(), out.tiles.end());
	out.found = true;
	const std::set<Coord> on(out.tiles.begin(), out.tiles.end());
	for (const auto &[c, cell] : cells) {
		if (!cell) {
			continue;
		}
		for (const lb::core::world::Collapse &alt : cell->collapses) {
			for (const lb::core::world::TileWrite &w : alt.fallen) {
				const Coord t = lb::core::world::tile_of(c, {w.index % CELL_TILES, w.index / CELL_TILES});
				if (!passable(w.material) && on.count(t) != 0) {
					out.crossings.push_back({c, alt.id});
					break;
				}
			}
		}
	}
	return out;
}

Verdict check_gates(const PlacementWorld &world) {
	const RunHeader &h = world.header();
	std::vector<Edge> gates;
	for (int32_t e = 0; e < 4; e++) {
		const std::optional<Socket> s = h.forced.query(edge_of({0, 0}, static_cast<Edge>(e)));
		if (s && s->open) {
			gates.push_back(static_cast<Edge>(e));
		}
	}
	if (gates.size() != 3) {
		return fail(Check::GATES, middle_of({0, 0}), std::to_string(gates.size()) + " of base camp's sides open, not three gates");
	}
	for (Edge side : gates) {
		const Coord cell = neighbour({0, 0}, side);
		const std::optional<Layout> l = world.layout(cell);
		if (!l || l->base_camp) {
			return fail(Check::GATES, middle_of(cell), "no road beyond base camp's gate");
		}
		const Edge in = opposite(side);
		const std::vector<Coord> start = opening_tiles(cell, l->sockets[static_cast<size_t>(in)], in);
		if (start.empty()) {
			return fail(Check::GATES, middle_of(cell), "the cell beyond the gate is shut to it");
		}
		Floor f;
		f.cells[cell] = l->cell;
		const std::set<Coord> reached = f.flood(start);
		bool onward = false;
		for (int32_t e = 0; e < 4 && !onward; e++) {
			if (static_cast<Edge>(e) == in) {
				continue;
			}
			for (const Coord &t : opening_tiles(cell, l->sockets[static_cast<size_t>(e)], static_cast<Edge>(e))) {
				onward = onward || reached.count(t) != 0;
			}
		}
		if (!onward) {
			return fail(Check::GATES, start.front(), "the gate's road leads to no other socket");
		}
	}
	return {};
}

Verdict walk_spine(const PlacementWorld &world, const PlacementParams &pp, const ValidatorParams &vp, const RunPlan &plan, size_t spine,
		bool all_alternates) {
	if (spine >= plan.spines.size()) {
		return fail(Check::SPINE_REACH, middle_of({0, 0}), "no such spine");
	}
	const Spine &sp = plan.spines[spine];
	if (sp.site < 0 || static_cast<size_t>(sp.site) >= plan.sites.size() || sp.cells.empty()) {
		return fail(Check::SPINE_REACH, middle_of({0, 0}), "a spine without a site or cells");
	}
	const PlannedSite &site = plan.sites[static_cast<size_t>(sp.site)];
	std::vector<Coord> cells = sp.cells;
	cells.push_back(site.door);
	Floor f;
	std::map<Coord, Layout> layouts;
	for (const Coord &c : cells) {
		const std::optional<Layout> l = world.layout(c);
		if (!l || l->base_camp) {
			return fail(Check::SPINE_REACH, middle_of(c), "a spine cell with no layout");
		}
		Cell cell = l->cell;
		std::set<uint32_t> fallen;
		if (all_alternates) {
			for (const lb::core::world::Collapse &alt : cell.collapses) {
				fallen.insert(alt.id);
			}
		} else {
			for (const Placement &x : place_validated(world, pp, vp, c).list) {
				if (x.kind == PlacedKind::COLLAPSE) {
					fallen.insert(x.collapse);
				}
			}
		}
		for (const lb::core::world::Collapse &alt : cell.collapses) {
			if (fallen.count(alt.id) != 0) {
				for (const lb::core::world::TileWrite &w : alt.fallen) {
					cell.tiles[w.index].material = w.material;
				}
			}
		}
		f.cells[c] = cell;
		layouts[c] = *l;
	}
	const Coord first = sp.cells.front();
	const Edge in = opposite(sp.gate);
	const std::vector<Coord> start = opening_tiles(first, layouts[first].sockets[static_cast<size_t>(in)], in);
	const std::vector<Coord> door = opening_tiles(site.door, layouts[site.door].sockets[static_cast<size_t>(site.door_side)], site.door_side);
	if (start.empty()) {
		return fail(Check::SPINE_REACH, middle_of(first), "the spine's first cell is shut to its gate");
	}
	if (door.empty()) {
		return fail(Check::SPINE_REACH, middle_of(site.door), "the target's door is shut");
	}
	const std::set<Coord> reached = f.flood(start);
	for (const Coord &t : door) {
		if (reached.count(t) != 0) {
			return {};
		}
	}
	// The walk's nearest tile to the door.
	Coord best = start.front();
	int64_t best_d = INT64_MAX;
	for (const Coord &t : reached) {
		const int64_t d = std::abs(t.x - door.front().x) + std::abs(t.y - door.front().y);
		if (d < best_d) {
			best = t;
			best_d = d;
		}
	}
	return fail(Check::SPINE_REACH, best, "the walk from the gate stops " + std::to_string(best_d) + " tiles short of the door");
}

SpineCheck validate_spines(RunPlan &plan, uint64_t seed, const std::vector<Edge> &gates, const std::vector<int64_t> &ring_bounds, int32_t max_replans,
		const std::function<Verdict(size_t)> &walk, const std::function<void()> &rebuild) {
	const size_t n = plan.spines.size();
	SpineCheck out;
	out.verdicts.assign(n, Verdict{});
	out.replans.assign(n, 0);
	std::vector<bool> given_up(n, false);
	std::set<Coord> blocked;
	for (const PlannedSite &site : plan.sites) {
		blocked.insert(site.cells.begin(), site.cells.end());
	}
	for (;;) {
		bool moved_any = false;
		for (size_t i = 0; i < n; i++) {
			out.verdicts[i] = walk(i);
			if (out.verdicts[i].ok() || given_up[i]) {
				continue;
			}
			Spine &sp = plan.spines[i];
			if (sp.site < 0 || static_cast<size_t>(sp.site) >= plan.sites.size()) {
				given_up[i] = true;
				continue;
			}
			const PlannedSite &site = plan.sites[static_cast<size_t>(sp.site)];
			bool moved = false;
			while (!moved && out.replans[i] < max_replans) {
				out.replans[i]++;
				out.total++;
				const std::optional<Spine> next = route_spine(seed, sp.site, site, gates, blocked, ring_bounds, sp.replan + 1);
				if (!next) {
					break;
				}
				moved = next->cells != sp.cells || next->gate != sp.gate;
				sp = *next;
			}
			given_up[i] = !moved;
			moved_any = moved_any || moved;
		}
		if (!moved_any) {
			return out;
		}
		rebuild();
		out.rebuilds++;
	}
}

void ValidatorCounters::count_layout(Coord cell, const std::string &biome, const std::optional<Layout> &final_layout, const std::vector<LayoutTry> &tried) {
	if (final_layout && final_layout->base_camp) {
		return; // GEN-02's cell, never validated
	}
	std::lock_guard<std::mutex> lock(mutex_);
	if (!laid_.insert(cell).second) {
		return;
	}
	add("cells");
	add("cells." + biome);
	if (!final_layout) {
		add("no_layout");
		note("cell (" + std::to_string(cell.x) + ", " + std::to_string(cell.y) + "): no template and no fallback");
		return;
	}
	if (final_layout->reroll > 0) {
		add("rerolled");
		add("rerolled." + biome);
		add("rerolls", final_layout->reroll);
	}
	if (final_layout->fallback) {
		add("fallbacks");
		add("fallbacks." + biome);
	}
	for (const LayoutTry &t : tried) {
		const std::string n = std::to_string(t.verdict.number());
		add("failed." + n);
		add("failed." + n + "." + biome);
		add("failed." + n + "." + t.template_id);
		note("cell (" + std::to_string(cell.x) + ", " + std::to_string(cell.y) + ") reroll " + std::to_string(t.reroll) + " " + t.template_id + ": " + describe(t.verdict));
	}
	if (!tried.empty() && tried.back().reroll == final_layout->reroll) {
		add("shipped_invalid");
	}
}

void ValidatorCounters::count_placement(Coord cell, const PlacedCell &placed) {
	if (cell == Coord{0, 0}) {
		return; // base camp places nothing
	}
	std::lock_guard<std::mutex> lock(mutex_);
	if (!placed_.insert(cell).second) {
		return;
	}
	add("placed");
	if (placed.retry > 0) {
		add("retried");
		add("retries", placed.retry);
	}
	if (placed.strict) {
		add("strict");
		add("dropped", placed.dropped);
	}
	for (const Verdict &v : placed.failures) {
		add("placement_failed." + std::to_string(v.number()));
		note("cell (" + std::to_string(cell.x) + ", " + std::to_string(cell.y) + ") placement: " + describe(v));
	}
}

void ValidatorCounters::count_spine(int32_t replans, const Verdict &final_verdict) {
	std::lock_guard<std::mutex> lock(mutex_);
	add("spines");
	add("spine_replans", replans);
	if (!final_verdict.ok()) {
		add("spines_unreached");
		note("spine: " + describe(final_verdict));
	}
}

void ValidatorCounters::count_gates(const Verdict &v) {
	std::lock_guard<std::mutex> lock(mutex_);
	if (!v.ok()) {
		add("gates_failed");
		note("gates: " + describe(v));
	}
}

void ValidatorCounters::count(const std::string &key, const std::string &text) {
	std::lock_guard<std::mutex> lock(mutex_);
	add(key);
	if (!text.empty()) {
		note(text);
	}
}

std::map<std::string, int64_t> ValidatorCounters::totals() const {
	std::lock_guard<std::mutex> lock(mutex_);
	return n_;
}

std::vector<std::string> ValidatorCounters::notes() const {
	std::lock_guard<std::mutex> lock(mutex_);
	return notes_;
}

void ValidatorCounters::clear() {
	std::lock_guard<std::mutex> lock(mutex_);
	laid_.clear();
	placed_.clear();
	n_.clear();
	notes_.clear();
}

void ValidatorCounters::note(const std::string &text) {
	if (notes_.size() < 64) {
		notes_.push_back(text);
	}
}

DerivedWorld::DerivedWorld(const RunHeader &header, const Deriver &deriver, const CellClassifier &base, const MainRoads *roads,
		const SpineSockets *spines, const PointsOfInterest *pois, const PoiContentsParams *contents, std::vector<int64_t> bounds)
	: header_(header), deriver_(deriver), base_(base), roads_(roads), spines_(spines), pois_(pois), contents_(contents), bounds_(std::move(bounds)) {}

CellFacts DerivedWorld::facts(Coord cell) const {
	CellFacts f;
	f.base_camp = cell == Coord{0, 0};
	f.ring = ring_of_cell(cell, bounds_);
	f.biome = base_.classify(cell).biome;
	if (pois_ != nullptr) {
		const PoiRef ref = pois_->at(cell);
		if (ref && ref->shape != nullptr && !ref->biome.empty()) {
			f.biome = ref->biome;
		}
	}
	f.main_road = roads_ != nullptr && roads_->is_main_road_cell(cell);
	f.spine = spines_ != nullptr && spines_->is_spine_cell(cell);
	return f;
}

PoiRef DerivedWorld::poi_at(Coord cell) const {
	return pois_ != nullptr ? pois_->at(cell) : PoiRef{};
}

std::vector<Content> DerivedWorld::contents(const Poi &poi) const {
	return pois_ != nullptr && contents_ != nullptr ? poi_contents(header_, *contents_, poi, pois_->is_canary(poi.id)) : std::vector<Content>{};
}

std::shared_ptr<const RegionLayout> DerivedWorld::region(Coord region) const {
	return pois_ != nullptr ? pois_->region(region) : nullptr;
}

} // namespace lb::core::gen

// GEN-14: one run's checks and the metrics they use (harness.h).

#include "harness/harness.h"

#include "core/gen/sockets.h"
#include "core/rng/hash.h"
#include "core/rng/rng.h"
#include "core/world/coords.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <deque>

namespace lb::harness {

namespace {

using lb::core::world::CELL_TILES;

constexpr const char *TOOLS[] = {"spanner", "hammer", "crowbar", "wire_cutters"};

uint64_t fold(uint64_t h, uint64_t v) {
	return lb::core::mix64(h ^ (v + 0x9E3779B97F4A7C15ULL + (h << 6) + (h >> 2)));
}

Coord shaft() {
	return lb::core::world::tile_of({0, 0}, {CELL_TILES / 2, CELL_TILES / 2});
}

Coord middle_of(Coord cell) {
	return lb::core::world::tile_of(cell, {CELL_TILES / 2, CELL_TILES / 2});
}

double distance(Coord a, Coord b) {
	const double dx = static_cast<double>(a.x - b.x);
	const double dy = static_cast<double>(a.y - b.y);
	return std::sqrt(dx * dx + dy * dy);
}

// Keeps a failure, at most Params::failures_kept_per_check of each check, counting them all.
void note(RunResult &r, const Params &p, Failure f) {
	int64_t &n = r.failure_counts[f.check];
	n++;
	if (n <= p.failures_kept_per_check) {
		f.seed = r.seed;
		f.list = r.list;
		r.failures.push_back(std::move(f));
	}
}

Failure verdict_failure(const char *check, Coord cell, const gen::Verdict &v) {
	Failure f;
	f.check = check;
	f.cell = cell;
	f.rule = v.number();
	f.tile = v.tile;
	f.detail = gen::describe(v);
	return f;
}

Failure plain_failure(const char *check, Coord cell, std::string detail) {
	Failure f;
	f.check = check;
	f.cell = cell;
	f.tile = middle_of(cell);
	f.detail = std::move(detail);
	return f;
}

std::string cell_text(Coord c) {
	return "(" + std::to_string(c.x) + ", " + std::to_string(c.y) + ")";
}

// Final layouts over a set of cells (collapses standing, doors open), walked with distances.
struct Floor {
	std::map<Coord, lb::core::world::Cell> cells;
	bool walkable(Coord t) const {
		const auto it = cells.find(lb::core::world::cell_of(t));
		if (it == cells.end()) {
			return false;
		}
		const Coord l = lb::core::world::local_of(t);
		return gen::walk_passable(it->second.tiles[static_cast<size_t>(lb::core::world::Cell::index_of(l.x, l.y))].material);
	}
	// The shortest 4-connected road from any of `from` to any of `to`.
	Road shortest(const std::vector<Coord> &from, const std::vector<Coord> &to) const {
		Road out;
		const std::set<Coord> goal(to.begin(), to.end());
		std::map<Coord, std::pair<int64_t, Coord>> seen; // tile -> (steps, the start it came from)
		std::deque<Coord> q;
		for (const Coord &t : from) {
			if (walkable(t) && seen.emplace(t, std::make_pair(int64_t{0}, t)).second) {
				q.push_back(t);
			}
		}
		while (!q.empty()) {
			const Coord t = q.front();
			q.pop_front();
			const auto at = seen.at(t);
			if (goal.count(t) != 0) {
				out.tiles = at.first;
				out.from = at.second;
				out.to = t;
				return out;
			}
			const Coord next[4] = {{t.x, t.y - 1}, {t.x + 1, t.y}, {t.x, t.y + 1}, {t.x - 1, t.y}};
			for (const Coord &n : next) {
				if (walkable(n) && seen.find(n) == seen.end()) {
					seen.emplace(n, std::make_pair(at.first + 1, at.second));
					q.push_back(n);
				}
			}
		}
		return out;
	}
};

std::vector<Coord> door_tiles(const gen::PlacementWorld &world, const gen::PlannedSite &site) {
	const std::optional<gen::Layout> l = world.layout(site.door);
	if (!l) {
		return {};
	}
	return gen::socket_opening_tiles(site.door, l->sockets[static_cast<size_t>(site.door_side)], site.door_side);
}

std::string biome_of(const Run &run, Coord c) {
	const gen::CellClass cls = run.cell_class(c);
	return cls.biome.empty() ? std::string("none") : cls.biome;
}

int64_t ratio_ppm(const Road &r) {
	return static_cast<int64_t>(std::llround(static_cast<double>(r.tiles) / std::max(1.0, r.straight()) * 1000000.0));
}

std::string ratio_text(int64_t ppm) {
	const int64_t hundredths = (ppm + 5000) / 10000;
	return std::to_string(hundredths / 100) + "." + std::to_string(100 + hundredths % 100).substr(1);
}

} // namespace

double Road::straight() const {
	return distance(from, to);
}

std::string Failure::repro() const {
	std::string out = "tools/seed_harness/run.sh --repro " + std::to_string(seed) + " " + list_name(list) + " " + check;
	if (!(cell.x == 0 && cell.y == 0) || check == "base_camp") {
		out += " " + std::to_string(cell.x) + "," + std::to_string(cell.y);
	}
	return out;
}

const char *list_name(int32_t list) {
	switch (list) {
		case 0:
			return "short";
		case 2:
			return "full";
		default:
			return "standard";
	}
}

std::vector<Coord> nearest_cells(int32_t n) {
	std::vector<Coord> out;
	if (n <= 0) {
		return out;
	}
	for (int64_t r = static_cast<int64_t>(std::ceil(std::sqrt(static_cast<double>(n) / 3.0))) + 2;; r += 4) {
		std::vector<std::tuple<int64_t, int64_t, int64_t>> all;
		for (int64_t y = -r; y <= r; y++) {
			for (int64_t x = -r; x <= r; x++) {
				if (x != 0 || y != 0) {
					all.emplace_back(x * x + y * y, y, x);
				}
			}
		}
		std::sort(all.begin(), all.end());
		// Every cell outside the square lies beyond r: the n-th must lie within it.
		if (all.size() >= static_cast<size_t>(n) && std::get<0>(all[static_cast<size_t>(n) - 1]) < r * r) {
			for (int32_t i = 0; i < n; i++) {
				out.push_back({std::get<2>(all[static_cast<size_t>(i)]), std::get<1>(all[static_cast<size_t>(i)])});
			}
			return out;
		}
	}
}

std::vector<Coord> shuffled(std::vector<Coord> cells, uint64_t seed, int32_t k) {
	lb::core::Rng rng(lb::core::mix64(seed ^ lb::core::mix64(0x47454E3134000000ULL + static_cast<uint64_t>(k))));
	rng.shuffle(cells);
	return cells;
}

uint64_t cell_digest(const std::optional<gen::Layout> &layout, const gen::PlacedCell &placed) {
	uint64_t h = 0x4C42484152ULL; // "LBHAR"
	if (!layout) {
		return fold(h, 0xFFFFFFFFULL);
	}
	h = fold(h, gen::layout_digest(*layout));
	h = fold(h, static_cast<uint64_t>(static_cast<int64_t>(layout->reroll)));
	h = fold(h, (layout->fallback ? 1u : 0u) | (layout->base_camp ? 2u : 0u));
	h = fold(h, gen::placement_digest(placed.list));
	h = fold(h, static_cast<uint64_t>(static_cast<int64_t>(placed.retry)));
	h = fold(h, (placed.strict ? 1u : 0u));
	h = fold(h, static_cast<uint64_t>(static_cast<int64_t>(placed.dropped)));
	for (const gen::Verdict &v : placed.failures) {
		h = fold(h, static_cast<uint64_t>(v.number()));
		h = fold(h, static_cast<uint64_t>(v.tile.x));
		h = fold(h, static_cast<uint64_t>(v.tile.y));
	}
	return h;
}

SocketGraph socket_graph(const Run &run) {
	SocketGraph g;
	g.sockets = [&run](Coord c) { return run.sockets(c); };
	g.ring = [&run](Coord c) { return run.world().facts(c).ring; };
	g.footprint = [&run](Coord c) {
		const gen::PoiRef ref = run.world().poi_at(c);
		return ref ? ref->cells() : std::vector<Coord>{};
	};
	return g;
}

int64_t ring_reach(const std::vector<int64_t> &ring_bounds, int64_t max_ring) {
	const int64_t edge = max_ring >= 0 && static_cast<size_t>(max_ring) < ring_bounds.size() ? ring_bounds[static_cast<size_t>(max_ring)] : 400;
	return edge / CELL_TILES + 2;
}

Joined joined_cells(const SocketGraph &g, int64_t max_ring, int64_t reach) {
	Joined out;
	std::set<Coord> rings;
	for (int64_t y = -reach; y <= reach; y++) {
		for (int64_t x = -reach; x <= reach; x++) {
			const Coord c{x, y};
			if (g.ring(c) <= max_ring) {
				rings.insert(c);
			}
		}
	}
	std::set<Coord> seen{{0, 0}};
	std::deque<Coord> q{{0, 0}};
	auto visit = [&](Coord n) {
		if (rings.count(n) != 0 && seen.insert(n).second) {
			q.push_back(n);
		}
	};
	while (!q.empty()) {
		const Coord c = q.front();
		q.pop_front();
		const gen::CellSockets s = g.sockets(c);
		for (int e = 0; e < 4; e++) {
			if (s[static_cast<size_t>(e)].open) {
				visit(gen::neighbour(c, static_cast<gen::Edge>(e)));
			}
		}
		// A point of interest's footprint is one piece of floor.
		for (const Coord &f : g.footprint(c)) {
			visit(f);
		}
	}
	for (const Coord &c : rings) {
		if (c.x == 0 && c.y == 0) {
			continue;
		}
		out.cells++;
		out.joined += seen.count(c) != 0 ? 1 : 0;
	}
	return out;
}

Road spine_road(const gen::PlacementWorld &world, const gen::RunPlan &plan, size_t spine) {
	Road out;
	if (spine >= plan.spines.size()) {
		return out;
	}
	const gen::Spine &sp = plan.spines[spine];
	if (sp.site < 0 || static_cast<size_t>(sp.site) >= plan.sites.size() || sp.cells.empty()) {
		return out;
	}
	const gen::PlannedSite &site = plan.sites[static_cast<size_t>(sp.site)];
	Floor f;
	std::vector<Coord> cells = sp.cells;
	cells.push_back(site.door);
	for (const Coord &c : cells) {
		const std::optional<gen::Layout> l = world.layout(c);
		if (!l || l->base_camp) {
			return out;
		}
		f.cells[c] = l->cell;
	}
	const Coord first = sp.cells.front();
	const gen::Edge in = gen::opposite(sp.gate);
	const std::optional<gen::Layout> first_layout = world.layout(first);
	const std::vector<Coord> start = gen::socket_opening_tiles(first, first_layout->sockets[static_cast<size_t>(in)], in);
	return f.shortest(start, door_tiles(world, site));
}

Road home_road(const gen::PlacementWorld &world, const gen::PlannedSite &site, int64_t max_explored) {
	Road out;
	const std::vector<Coord> door = door_tiles(world, site);
	if (door.empty()) {
		return out;
	}
	const int32_t max_cells = static_cast<int32_t>(std::max(std::llabs(site.door.x), std::llabs(site.door.y)) + 2);
	const gen::RouteHome r = gen::route_home(world, door[door.size() / 2], max_cells, max_explored);
	if (!r.found || r.tiles.empty()) {
		return out;
	}
	out.tiles = static_cast<int64_t>(r.tiles.size()) - 1;
	out.from = r.tiles.back();
	out.to = r.tiles.front();
	return out;
}

std::vector<Coord> explored_cells(const gen::RunPlan &plan, const gen::PlacementWorld &world, int32_t radius, int64_t max_ring) {
	std::set<Coord> out;
	std::set<Coord> spine;
	for (const gen::Spine &sp : plan.spines) {
		for (const Coord &c : sp.cells) {
			spine.insert(c);
			for (int64_t dy = -1; dy <= 1; dy++) {
				for (int64_t dx = -1; dx <= 1; dx++) {
					out.insert({c.x + dx, c.y + dy});
				}
			}
		}
	}
	for (const gen::PlannedSite &site : plan.sites) {
		out.insert(site.door);
		out.insert(site.cells.begin(), site.cells.end());
	}
	std::set<Coord> near;
	for (const Coord &c : spine) {
		for (int64_t dy = -radius; dy <= radius; dy++) {
			for (int64_t dx = -radius; dx <= radius; dx++) {
				near.insert({c.x + dx, c.y + dy});
			}
		}
	}
	for (const Coord &c : near) {
		if (out.count(c) == 0 && world.facts(c).ring <= max_ring) {
			out.insert(c);
		}
	}
	out.erase({0, 0});
	return std::vector<Coord>(out.begin(), out.end());
}

std::map<std::string, int64_t> count_finds(const gen::PlacementWorld &world, const gen::PlacementParams &pp, const gen::ValidatorParams &vp,
		const std::vector<Coord> &cells, int64_t cupboard_kits) {
	std::map<std::string, int64_t> out{{"lamps", 0}, {"kits", cupboard_kits}, {"flares_ring2", 0}};
	for (const char *tool : TOOLS) {
		out[std::string("tools_ring2.") + tool] = 0;
		out[std::string("tools_ring1.") + tool] = 0;
	}
	std::set<Coord> hoard;
	for (const gen::PlannedSite &site : world.header().plan.sites) {
		if (site.kind == gen::PoiKind::HOARD) {
			hoard.insert(site.cells.begin(), site.cells.end());
		}
	}
	for (const Coord &c : cells) {
		const gen::CellFacts facts = world.facts(c);
		if (facts.base_camp) {
			continue;
		}
		for (const gen::Placement &x : gen::place_validated(world, pp, vp, c).list) {
			if (x.kind != gen::PlacedKind::ITEM) {
				continue;
			}
			const int64_t n = std::max<int64_t>(1, x.count);
			if (x.thing == "gauze_lamp") {
				out["lamps"] += hoard.count(c) != 0 ? 0 : n;
			} else if (x.thing == "healing_kit") {
				out["kits"] += n;
			} else if (x.thing == "flare") {
				out["flares_ring2"] += facts.ring <= 2 ? n : 0;
			} else {
				for (const char *tool : TOOLS) {
					if (x.thing == tool) {
						out[std::string("tools_ring2.") + tool] += facts.ring <= 2 ? n : 0;
						out[std::string("tools_ring1.") + tool] += facts.ring <= 1 ? n : 0;
					}
				}
			}
		}
	}
	out["explored_cells"] = static_cast<int64_t>(cells.size());
	return out;
}

RunResult check_run(const Run &run, const RunFactory &fresh, const Params &p) {
	RunResult r;
	const gen::RunHeader &h = run.header();
	const gen::RunPlan &plan = h.plan;
	const gen::PlacementWorld &world = run.world();
	const gen::PlacementParams &pp = run.placement_params();
	const gen::ValidatorParams &vp = run.validator_params();
	r.seed = h.seed;
	r.list = h.list_kind;
	// The plan (GEN-08).
	r.planned = plan.error.empty();
	if (!r.planned) {
		note(r, p, plain_failure("plan", {0, 0}, "the plan's retries ran out: " + plan.error));
	}
	// Spine reach: every spine with its cells' armed collapse points fallen.
	for (size_t i = 0; i < plan.spines.size(); i++) {
		r.spines++;
		const gen::Verdict v = gen::walk_spine(world, pp, vp, plan, i);
		if (v.ok()) {
			r.spines_reached++;
		} else {
			const gen::Spine &sp = plan.spines[i];
			const Coord cell = sp.site >= 0 && static_cast<size_t>(sp.site) < plan.sites.size() ? plan.sites[static_cast<size_t>(sp.site)].door
																								: lb::core::world::cell_of(v.tile);
			Failure f = verdict_failure("spine_reach", cell, v);
			f.detail = "spine " + std::to_string(i) + ": " + f.detail;
			note(r, p, std::move(f));
		}
	}
	// Nothing is placed in base camp (Gameplay §12.5; LFT-01's run-start check).
	const gen::PlacedCell camp = gen::place_validated(world, pp, vp, {0, 0});
	if (!camp.list.empty()) {
		note(r, p, plain_failure("base_camp", {0, 0}, std::to_string(camp.list.size()) + " placements in base camp, the first a " + camp.list.front().thing));
	}
	// Fairness: each spine's road, and the shortest road home only when the spine's looks long.
	for (size_t i = 0; i < plan.spines.size(); i++) {
		const gen::Spine &sp = plan.spines[i];
		if (sp.site < 0 || static_cast<size_t>(sp.site) >= plan.sites.size()) {
			continue;
		}
		const gen::PlannedSite &site = plan.sites[static_cast<size_t>(sp.site)];
		Road road = spine_road(world, plan, i);
		int64_t ppm = road.tiles >= 0 ? ratio_ppm(road) : -1;
		const int64_t limit = static_cast<int64_t>(std::llround(p.road_ratio_max * 1000000.0));
		if (ppm < 0 || ppm > limit) {
			const Road home = home_road(world, site, p.route_max_explored);
			if (home.tiles >= 0 && (ppm < 0 || ratio_ppm(home) < ppm)) {
				road = home;
				ppm = ratio_ppm(home);
			}
		}
		r.road_ratio_ppm.push_back(ppm);
		if (ppm < 0) {
			note(r, p, plain_failure("road_ratio", site.door, std::string("no road reaches the ") + gen::poi_kind_name(site.kind) + "'s door"));
		} else if (ppm > limit) {
			note(r, p,
					plain_failure("road_ratio", site.door,
							std::string("the ") + gen::poi_kind_name(site.kind) + "'s road is " + ratio_text(ppm) + " x the straight line (" +
									std::to_string(road.tiles) + " tiles over " + std::to_string(std::llround(road.straight())) + ")"));
		}
	}
	const Joined joined = joined_cells(socket_graph(run), p.joined_max_ring, ring_reach(world.ring_bounds(), p.joined_max_ring));
	r.joined_cells = joined.joined;
	r.ring_cells = joined.cells;
	// Banded sites: each kind's door from the shaft, and the hoard-lair bearing.
	std::optional<Coord> hoard;
	std::optional<Coord> lair;
	for (const gen::PlannedSite &site : plan.sites) {
		const Coord door = middle_of(site.door);
		r.sites.emplace_back(gen::poi_kind_name(site.kind), static_cast<int64_t>(std::llround(distance(shaft(), door))));
		if (site.kind == gen::PoiKind::HOARD && !hoard) {
			hoard = door;
		} else if (site.kind == gen::PoiKind::LAIR && !lair) {
			lair = door;
		}
	}
	if (hoard) {
		r.roosts = static_cast<int32_t>(gen::read_homes(h).roosts.size());
		r.roosts_min = static_cast<int32_t>(pp.roosts_min);
	}
	if (hoard && lair) {
		const Coord s = shaft();
		const double a = std::atan2(static_cast<double>(hoard->y - s.y), static_cast<double>(hoard->x - s.x));
		const double b = std::atan2(static_cast<double>(lair->y - s.y), static_cast<double>(lair->x - s.x));
		double d = std::fabs(a - b) * 180.0 / 3.14159265358979323846;
		if (d > 180.0) {
			d = 360.0 - d;
		}
		r.hoard_lair_bearing = static_cast<int64_t>(std::llround(d));
	}
	// Order-independence, and in the first order the validator, timing and the finds.
	const std::vector<Coord> cells = nearest_cells(p.order_cells);
	std::map<Coord, uint64_t> first;
	std::set<Coord> differing;
	for (int32_t k = 0; k < std::max(1, p.orders); k++) {
		const std::unique_ptr<Run> w = fresh();
		if (!w) {
			break;
		}
		const gen::PlacementWorld &ww = w->world();
		const gen::PlacementParams &wpp = w->placement_params();
		const gen::ValidatorParams &wvp = w->validator_params();
		std::map<Coord, uint64_t> digests;
		for (const Coord &c : shuffled(cells, r.seed, k)) {
			const auto t0 = std::chrono::steady_clock::now();
			const std::optional<gen::Layout> layout = ww.layout(c);
			const gen::PlacedCell placed = layout ? gen::place_validated(ww, wpp, wvp, c) : gen::PlacedCell{};
			const auto t1 = std::chrono::steady_clock::now();
			digests[c] = cell_digest(layout, placed);
			if (k != 0) {
				continue;
			}
			const std::string biome = biome_of(*w, c);
			r.cell_us[biome].push_back(std::chrono::duration_cast<std::chrono::microseconds>(t1 - t0).count());
			r.cells_by_biome[biome]++;
			r.cells_checked++;
			if (!layout) {
				r.cells_invalid++;
				note(r, p, plain_failure("validator", c, "no template or fallback fits cell " + cell_text(c) + " (" + biome + ")"));
				continue;
			}
			if (layout->fallback) {
				r.fallbacks_by_biome[biome]++;
			}
			if (layout->reroll > 0) {
				r.rerolled_by_biome[biome]++;
			}
			r.templates[layout->template_id.empty() ? std::string("(base camp)") : layout->template_id]++;
			if (layout->base_camp) {
				continue;
			}
			const gen::Verdict lv = gen::validate_layout(*layout, w->cell_class(c), wvp);
			const gen::Verdict pv = lv.ok() ? gen::validate_placement(gen::placement_context(ww, wpp, wvp, c), placed.list) : gen::Verdict{};
			if (!lv.ok() || !pv.ok()) {
				r.cells_invalid++;
				Failure f = verdict_failure("validator", c, lv.ok() ? pv : lv);
				f.detail = (lv.ok() ? "placement " : "layout ") + layout->template_id + ": " + f.detail;
				note(r, p, std::move(f));
			}
		}
		if (k == 0) {
			first = digests;
			r.order_cells = static_cast<int32_t>(cells.size());
			r.finds = count_finds(ww, wpp, wvp, explored_cells(plan, ww, p.explore_radius, p.explore_max_ring), p.cupboard_kits);
			r.counters = w->counter_totals();
			continue;
		}
		for (const Coord &c : cells) {
			if (digests[c] != first[c] && differing.insert(c).second) {
				note(r, p, plain_failure("order", c, "cell " + cell_text(c) + " differs between the first order and order " + std::to_string(k)));
			}
		}
	}
	r.order_differing = static_cast<int32_t>(differing.size());
	return r;
}

} // namespace lb::harness

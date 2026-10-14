#include "core/sound/road_graph.h"

#include "core/generated/hash_domains.h"
#include "core/rng/rng.h"

#include <algorithm>
#include <cmath>
#include <limits>
#include <queue>
#include <set>

namespace lb::core::sound {

using lb::core::world::CELL_AREA;
using lb::core::world::CELL_TILES;
using lb::core::world::Cell;
using lb::core::world::cell_of;
using lb::core::world::local_of;

namespace {

constexpr double INF = std::numeric_limits<double>::infinity();
constexpr double DIAGONAL = 1.4142135623730951;

const Coord ORTHO[4] = {{1, 0}, {-1, 0}, {0, 1}, {0, -1}};
const Coord ALL8[8] = {{1, 0}, {-1, 0}, {0, 1}, {0, -1}, {1, 1}, {1, -1}, {-1, 1}, {-1, -1}};

} // namespace

void RoadGraph::bump() {
	epoch_++;
	cache_.clear();
}

std::optional<uint32_t> RoadGraph::zone_of(Coord tile) const {
	std::optional<lb::core::world::Tile> t = mine_.tile_at(tile);
	if (!t || t->zone == 0) {
		return std::nullopt;
	}
	auto it = zone_by_key_.find({cell_of(tile), t->zone});
	if (it == zone_by_key_.end()) {
		return std::nullopt;
	}
	const Zone &z = zones_[it->second];
	const Coord l = local_of(tile);
	if (z.index[static_cast<size_t>(Cell::index_of(l.x, l.y))] < 0) {
		return std::nullopt; // fallen or otherwise not walkable now
	}
	return it->second;
}

std::optional<uint32_t> RoadGraph::portal_of(Coord tile) const {
	auto it = portal_by_tile_.find(tile);
	if (it == portal_by_tile_.end()) {
		return std::nullopt;
	}
	return it->second;
}

bool RoadGraph::stitch(Coord cell, const CellBlock &block) {
	const Cell *c = mine_.cell(cell);
	if (c == nullptr || !validate_block(*c, block).empty()) {
		return false;
	}
	if (is_stitched(cell)) {
		unload(cell);
	}
	blocks_[cell] = block;
	const Coord base{cell.x * CELL_TILES, cell.y * CELL_TILES};
	// Zones: the walkable tiles carrying each declared id.
	for (const ZoneDecl &decl : block.zones) {
		Zone z;
		z.live = true;
		z.cell = cell;
		z.id = decl.id;
		z.kind = decl.kind;
		z.index.fill(-1);
		for (int64_t i = 0; i < CELL_AREA; i++) {
			const lb::core::world::Tile &t = c->tiles[static_cast<size_t>(i)];
			const Coord g{base.x + i % CELL_TILES, base.y + i / CELL_TILES};
			if (t.zone == decl.id && mine_.is_walkable(g)) {
				z.index[static_cast<size_t>(i)] = static_cast<int16_t>(z.tiles.size());
				z.tiles.push_back(g);
			}
		}
		const uint32_t index = static_cast<uint32_t>(zones_.size());
		zones_.push_back(std::move(z));
		zone_by_key_[{cell, decl.id}] = index;
		cell_zones_[cell].push_back(index);
	}
	// Portals: their tiles, the two zones, and the open state of their barrier.
	for (const PortalDecl &decl : block.portals) {
		Portal p;
		p.live = true;
		p.cell = cell;
		p.id = decl.id;
		p.kind = decl.kind;
		p.barrier = decl.barrier;
		p.zone = {zone_by_key_[{cell, decl.zone_a}], zone_by_key_[{cell, decl.zone_b}]};
		for (uint16_t i : decl.tiles) {
			p.tiles.push_back({base.x + i % CELL_TILES, base.y + i / CELL_TILES});
		}
		p.centre = p.tiles[p.tiles.size() / 2];
		p.open = true;
		for (const lb::core::world::Barrier &b : c->barriers) {
			if (b.id == decl.barrier) {
				p.open = b.open;
			}
		}
		for (int s = 0; s < 2; s++) {
			const Zone &z = zones_[p.zone[s]];
			for (const Coord &pt : p.tiles) {
				for (const Coord &d : ORTHO) {
					const Coord n{pt.x + d.x, pt.y + d.y};
					if (cell_of(n) == cell) {
						const Coord l = local_of(n);
						if (z.index[static_cast<size_t>(Cell::index_of(l.x, l.y))] >= 0 &&
								std::find(p.side[s].begin(), p.side[s].end(), n) == p.side[s].end()) {
							p.side[s].push_back(n);
						}
					}
				}
			}
		}
		const uint32_t index = static_cast<uint32_t>(portals_.size());
		for (const Coord &t : p.tiles) {
			portal_by_tile_[t] = index;
		}
		zones_[p.zone[0]].portals.push_back(index);
		zones_[p.zone[1]].portals.push_back(index);
		portals_.push_back(std::move(p));
		cell_portals_[cell].push_back(index);
	}
	for (const Coord &d : ORTHO) {
		const Coord n{cell.x + d.x, cell.y + d.y};
		if (is_stitched(n)) {
			link_edges(cell, n);
		}
	}
	for (uint32_t z : cell_zones_[cell]) {
		for (uint32_t p : zones_[z].portals) {
			build_field(z, p);
		}
		build_pp(z);
	}
	bump();
	return true;
}

void RoadGraph::link_edges(Coord a, Coord b) {
	// One portal per pair of walkable zone tiles facing each other across the shared edge, so
	// crossing costs exactly its one tile wherever it happens (NET-08's audit found a single wide
	// edge portal letting sound run along the edge for free: 6 tiles for an 11-tile walk).
	const bool horizontal = a.y == b.y;
	std::set<uint32_t> touched;
	for (int64_t k = 0; k < CELL_TILES; k++) {
		Coord ta, tb;
		if (horizontal) {
			const int64_t xa = a.x < b.x ? a.x * CELL_TILES + CELL_TILES - 1 : a.x * CELL_TILES;
			ta = {xa, a.y * CELL_TILES + k};
			tb = {a.x < b.x ? xa + 1 : xa - 1, ta.y};
		} else {
			const int64_t ya = a.y < b.y ? a.y * CELL_TILES + CELL_TILES - 1 : a.y * CELL_TILES;
			ta = {a.x * CELL_TILES + k, ya};
			tb = {ta.x, a.y < b.y ? ya + 1 : ya - 1};
		}
		std::optional<uint32_t> za = zone_of(ta);
		std::optional<uint32_t> zb = zone_of(tb);
		if (!za || !zb) {
			continue;
		}
		Portal p;
		p.live = true;
		p.cell = a < b ? a : b;
		p.kind = PortalKind::EDGE;
		p.zone = {*za, *zb};
		p.side = {std::vector<Coord>{ta}, std::vector<Coord>{tb}};
		p.cross_air = 1.0;
		p.open = true;
		p.centre = ta;
		const uint32_t index = static_cast<uint32_t>(portals_.size());
		zones_[p.zone[0]].portals.push_back(index);
		zones_[p.zone[1]].portals.push_back(index);
		portals_.push_back(std::move(p));
		cell_portals_[a].push_back(index);
		cell_portals_[b].push_back(index);
		// The neighbour's zone gains a portal: its field now, its portal-to-portal costs below.
		build_field(*zb, index);
		touched.insert(*zb);
	}
	for (uint32_t z : touched) {
		build_pp(z);
	}
}

void RoadGraph::build_field(uint32_t zone_index, uint32_t portal_index) {
	Zone &z = zones_[zone_index];
	const Portal &p = portals_[portal_index];
	const int s = p.zone[0] == zone_index ? 0 : 1;
	std::vector<double> dist(z.tiles.size(), INF);
	using Node = std::pair<double, int64_t>;
	std::priority_queue<Node, std::vector<Node>, std::greater<Node>> open;
	for (const Coord &t : p.side[s]) {
		const Coord l = local_of(t);
		const int16_t i = z.index[static_cast<size_t>(Cell::index_of(l.x, l.y))];
		if (i >= 0 && dist[static_cast<size_t>(i)] > 0.0) {
			dist[static_cast<size_t>(i)] = 0.0;
			open.emplace(0.0, i);
		}
	}
	auto index_of = [&](Coord t) -> int64_t {
		if (cell_of(t) != z.cell) {
			return -1;
		}
		const Coord l = local_of(t);
		return z.index[static_cast<size_t>(Cell::index_of(l.x, l.y))];
	};
	while (!open.empty()) {
		auto [d, i] = open.top();
		open.pop();
		if (d > dist[static_cast<size_t>(i)]) {
			continue;
		}
		const Coord here = z.tiles[static_cast<size_t>(i)];
		for (const Coord &step : ALL8) {
			const int64_t ni = index_of({here.x + step.x, here.y + step.y});
			if (ni < 0) {
				continue;
			}
			const bool diagonal = step.x != 0 && step.y != 0;
			if (diagonal && (index_of({here.x + step.x, here.y}) < 0 || index_of({here.x, here.y + step.y}) < 0)) {
				continue;
			}
			const double nd = d + (diagonal ? DIAGONAL : 1.0);
			if (nd < dist[static_cast<size_t>(ni)]) {
				dist[static_cast<size_t>(ni)] = nd;
				open.emplace(nd, ni);
			}
		}
	}
	z.field[portal_index] = std::move(dist);
}

void RoadGraph::build_pp(uint32_t zone_index) {
	Zone &z = zones_[zone_index];
	z.pp.clear();
	for (uint32_t p : z.portals) {
		const std::vector<double> &field = z.field[p];
		for (uint32_t q : z.portals) {
			if (p == q) {
				continue;
			}
			const Portal &qp = portals_[q];
			const int s = qp.zone[0] == zone_index ? 0 : 1;
			double best = INF;
			for (const Coord &t : qp.side[s]) {
				const Coord l = local_of(t);
				const int16_t i = z.index[static_cast<size_t>(Cell::index_of(l.x, l.y))];
				if (i >= 0) {
					best = std::min(best, field[static_cast<size_t>(i)]);
				}
			}
			z.pp[{p, q}] = best;
		}
	}
}

bool RoadGraph::unload(Coord cell) {
	auto block = blocks_.find(cell);
	if (block == blocks_.end()) {
		return false;
	}
	std::vector<uint32_t> dead_portals = cell_portals_[cell];
	for (uint32_t p : dead_portals) {
		Portal &portal = portals_[p];
		if (!portal.live) {
			continue;
		}
		portal.live = false;
		for (const Coord &t : portal.tiles) {
			portal_by_tile_.erase(t);
		}
		for (uint32_t z : portal.zone) {
			Zone &zone = zones_[z];
			zone.portals.erase(std::remove(zone.portals.begin(), zone.portals.end(), p), zone.portals.end());
			zone.field.erase(p);
		}
		if (portal.kind == PortalKind::EDGE) {
			const Coord other = portal.cell == cell ? Coord{} : portal.cell;
			(void)other;
		}
	}
	for (uint32_t z : cell_zones_[cell]) {
		zones_[z].live = false;
		zone_by_key_.erase({cell, zones_[z].id});
	}
	// Neighbours lose their edge links to this cell.
	for (const Coord &d : ORTHO) {
		const Coord n{cell.x + d.x, cell.y + d.y};
		auto it = cell_portals_.find(n);
		if (it == cell_portals_.end()) {
			continue;
		}
		std::vector<uint32_t> kept;
		for (uint32_t p : it->second) {
			if (portals_[p].live) {
				kept.push_back(p);
			}
		}
		it->second = kept;
		for (uint32_t z : cell_zones_[n]) {
			build_pp(z);
		}
	}
	cell_zones_.erase(cell);
	cell_portals_.erase(cell);
	blocks_.erase(block);
	bump();
	return true;
}

void RoadGraph::on_tiles_changed(Coord cell) {
	auto it = blocks_.find(cell);
	if (it == blocks_.end()) {
		return;
	}
	const CellBlock block = it->second;
	unload(cell);
	stitch(cell, block);
}

void RoadGraph::set_listener(const Listener &listener) {
	listeners_[listener.id] = listener;
}

void RoadGraph::remove_listener(uint32_t id) {
	listeners_.erase(id);
}

bool RoadGraph::total_less(const Entry &a, const Entry &b) const {
	const double ta = total(a);
	const double tb = total(b);
	if (ta != tb) {
		return ta < tb;
	}
	if (a.air != b.air) {
		return a.air < b.air;
	}
	return a.last < b.last;
}

void RoadGraph::search(std::vector<std::pair<uint32_t, Entry>> starts, Mode mode, double cap, SearchResult &out) const {
	// Dijkstra over portal sides. Node = portal * 2 + side; ordered by total cost, then node.
	using QNode = std::tuple<double, uint32_t>;
	std::priority_queue<QNode, std::vector<QNode>, std::greater<QNode>> open;
	out.nodes.assign(portals_.size() * 2, Entry{});
	out.has.assign(portals_.size() * 2, 0);
	auto offer = [&](uint32_t node, const Entry &e) {
		if (e.air > cap) {
			return;
		}
		if (!out.has[node] || total_less(e, out.nodes[node])) {
			out.nodes[node] = e;
			out.has[node] = 1;
			open.emplace(total(e), node);
		}
	};
	for (auto &s : starts) {
		offer(s.first, s.second);
	}
	while (!open.empty()) {
		auto [cost, node] = open.top();
		open.pop();
		const Entry here = out.nodes[node];
		if (cost > total(here)) {
			continue;
		}
		const uint32_t p = node / 2;
		const int side = static_cast<int>(node % 2);
		const Portal &portal = portals_[p];
		std::vector<std::pair<uint32_t, Entry>> next;
		// Cross the portal.
		if (portal.open || mode == Mode::AIR) {
			Entry e = here;
			e.air += portal.cross_air;
			if (!portal.open) {
				e.closed++;
			}
			e.last = p;
			next.emplace_back(p * 2 + (1 - side), e);
		}
		// Move through the zone to its other portals.
		const Zone &z = zones_[portal.zone[side]];
		for (uint32_t q : z.portals) {
			if (q == p) {
				continue;
			}
			auto pp = z.pp.find({p, q});
			if (pp == z.pp.end() || pp->second == INF) {
				continue;
			}
			Entry e = here;
			e.air += pp->second;
			const Portal &qp = portals_[q];
			next.emplace_back(q * 2 + (qp.zone[0] == portal.zone[side] ? 0 : 1), e);
		}
		for (auto &n : next) {
			offer(n.first, n.second);
		}
	}
}

const RoadGraph::Sparse &RoadGraph::cached(uint32_t node, Mode mode) {
	const auto key = std::make_tuple(node, static_cast<int>(mode), 0);
	auto it = cache_.find(key);
	if (it != cache_.end()) {
		return it->second;
	}
	SearchResult result;
	search({{node, Entry{}}}, mode, params.search_cap_air, result);
	Sparse sparse;
	for (uint32_t n = 0; n < result.has.size(); n++) {
		if (result.has[n]) {
			sparse.emplace_back(n, result.nodes[n]);
		}
	}
	return cache_.emplace(key, std::move(sparse)).first->second;
}

std::vector<double> RoadGraph::zone_distances(uint32_t zone_index, Coord from, double cap) const {
	const Zone &z = zones_[zone_index];
	std::vector<double> dist(z.tiles.size(), INF);
	auto index_of = [&](Coord t) -> int64_t {
		if (cell_of(t) != z.cell) {
			return -1;
		}
		const Coord l = local_of(t);
		return z.index[static_cast<size_t>(Cell::index_of(l.x, l.y))];
	};
	const int64_t start = index_of(from);
	if (start < 0) {
		return dist;
	}
	using Node = std::pair<double, int64_t>;
	std::priority_queue<Node, std::vector<Node>, std::greater<Node>> open;
	dist[static_cast<size_t>(start)] = 0.0;
	open.emplace(0.0, start);
	while (!open.empty()) {
		auto [d, i] = open.top();
		open.pop();
		if (d > dist[static_cast<size_t>(i)]) {
			continue;
		}
		const Coord here = z.tiles[static_cast<size_t>(i)];
		for (const Coord &step : ALL8) {
			const int64_t ni = index_of({here.x + step.x, here.y + step.y});
			if (ni < 0) {
				continue;
			}
			const bool diagonal = step.x != 0 && step.y != 0;
			if (diagonal && (index_of({here.x + step.x, here.y}) < 0 || index_of({here.x, here.y + step.y}) < 0)) {
				continue;
			}
			const double nd = d + (diagonal ? DIAGONAL : 1.0);
			if (nd <= cap && nd < dist[static_cast<size_t>(ni)]) {
				dist[static_cast<size_t>(ni)] = nd;
				open.emplace(nd, ni);
			}
		}
	}
	return dist;
}

RoadGraph::Start RoadGraph::starts_for(Coord origin, int64_t origin_index) const {
	Start start;
	if (std::optional<uint32_t> p = portal_of(origin)) {
		for (int s = 0; s < 2; s++) {
			Entry e;
			e.origin = origin_index;
			start.nodes.emplace_back(*p * 2 + static_cast<uint32_t>(s), e);
		}
		return start;
	}
	start.zone = zone_of(origin);
	if (!start.zone) {
		return start;
	}
	const Zone &z = zones_[*start.zone];
	const Coord l = local_of(origin);
	const int16_t i = z.index[static_cast<size_t>(Cell::index_of(l.x, l.y))];
	for (uint32_t p : z.portals) {
		auto f = z.field.find(p);
		if (f == z.field.end() || f->second[static_cast<size_t>(i)] == INF) {
			continue;
		}
		Entry e;
		e.air = f->second[static_cast<size_t>(i)];
		e.origin = origin_index;
		const Portal &portal = portals_[p];
		start.nodes.emplace_back(p * 2 + (portal.zone[0] == *start.zone ? 0 : 1), e);
	}
	return start;
}

std::optional<Delivery> RoadGraph::resolve(const Listener &l, const std::vector<Coord> &origins, const std::vector<Start> &starts,
		const SearchResult &result, Direct &direct, double cap, double level, uint64_t jitter_key) const {
	std::optional<Entry> best;
	auto consider = [&](const Entry &e) {
		if (!best || total_less(e, *best)) {
			best = e;
		}
	};
	if (std::optional<uint32_t> lp = portal_of(l.tile)) {
		for (int s = 0; s < 2; s++) {
			if (const Entry *e = result.get(*lp * 2 + static_cast<uint32_t>(s))) {
				consider(*e);
			}
		}
		for (size_t k = 0; k < origins.size(); k++) {
			if (origins[k] == l.tile) {
				Entry e;
				e.origin = static_cast<int64_t>(k);
				consider(e);
			}
		}
	} else if (std::optional<uint32_t> lz = zone_of(l.tile)) {
		const Zone &z = zones_[*lz];
		const Coord local = local_of(l.tile);
		const int16_t li = z.index[static_cast<size_t>(Cell::index_of(local.x, local.y))];
		// The same zone as an origin: the direct route.
		for (size_t k = 0; k < origins.size(); k++) {
			if (starts[k].zone && *starts[k].zone == *lz) {
				if (!direct[k]) {
					direct[k] = zone_distances(*lz, origins[k], cap);
				}
				const double d = (*direct[k])[static_cast<size_t>(li)];
				if (d != INF) {
					Entry e;
					e.air = d;
					e.origin = static_cast<int64_t>(k);
					consider(e);
				}
			}
		}
		// Through each portal of the listener's zone.
		for (uint32_t p : z.portals) {
			const Portal &portal = portals_[p];
			const Entry *reached = result.get(p * 2 + (portal.zone[0] == *lz ? 0 : 1));
			auto f = z.field.find(p);
			if (reached == nullptr || f == z.field.end() || f->second[static_cast<size_t>(li)] == INF) {
				continue;
			}
			Entry e = *reached;
			e.air += f->second[static_cast<size_t>(li)];
			consider(e);
		}
	} else {
		return std::nullopt;
	}
	if (!best || best->air > cap || !audible(level, best->closed, params.closed_cost, best->air, l.threshold, l.multiplier)) {
		return std::nullopt;
	}
	Delivery d;
	d.listener = l.id;
	d.path_tiles = best->air;
	d.closed_portals = best->closed;
	d.remaining_np = level - best->air - static_cast<double>(best->closed) * params.closed_cost;
	d.true_source = origins[static_cast<size_t>(best->origin)];
	if (best->last >= 0) {
		const Portal &via = portals_[static_cast<size_t>(best->last)];
		d.apparent_tile = via.centre;
		d.via = via.id == 0 ? -1 : via.id;
	} else {
		d.apparent_tile = d.true_source;
	}
	apply_jitter(d, jitter_key);
	return d;
}

void RoadGraph::apply_jitter(Delivery &d, uint64_t event_key) const {
	const int64_t limit = static_cast<int64_t>(std::floor(d.path_tiles * params.jitter_per_tile * 1000.0));
	const int64_t keys[2] = {static_cast<int64_t>(event_key), static_cast<int64_t>(d.listener)};
	lb::core::Rng rng(lb::core::hash_u64(params.run_seed, lb::core::hash_domain::SOUND_JITTER, keys, 2));
	const int64_t jx = limit > 0 ? *rng.range(-limit, limit) : 0;
	const int64_t jy = limit > 0 ? *rng.range(-limit, limit) : 0;
	d.apparent_x = static_cast<double>(d.apparent_tile.x) + 0.5 + static_cast<double>(jx) / 1000.0;
	d.apparent_y = static_cast<double>(d.apparent_tile.y) + 0.5 + static_cast<double>(jy) / 1000.0;
}

std::vector<Delivery> RoadGraph::propagate(uint64_t event_id, const std::vector<Coord> &origins, double level, Mode mode) {
	std::vector<Delivery> out;
	if (origins.empty() || listeners_.empty()) {
		return out;
	}
	// Follow the event only as far as any registered listener could hear it.
	double reach = -1.0;
	for (const auto &entry : listeners_) {
		reach = std::max(reach, (level - entry.second.threshold) * entry.second.multiplier);
	}
	if (reach < 0.0) {
		return out;
	}
	const double cap = std::min(params.search_cap_air, reach);
	std::vector<Start> starts;
	SearchResult combined;
	combined.nodes.assign(portals_.size() * 2, Entry{});
	combined.has.assign(portals_.size() * 2, 0);
	for (size_t k = 0; k < origins.size(); k++) {
		starts.push_back(starts_for(origins[k], static_cast<int64_t>(k)));
		for (const auto &start : starts.back().nodes) {
			if (start.second.air > cap) {
				continue;
			}
			for (const auto &entry : cached(start.first, mode)) {
				Entry e = entry.second;
				e.air += start.second.air;
				e.origin = start.second.origin;
				if (e.air > cap) {
					continue;
				}
				if (!combined.has[entry.first] || total_less(e, combined.nodes[entry.first])) {
					combined.nodes[entry.first] = e;
					combined.has[entry.first] = 1;
				}
			}
		}
	}
	Direct direct(origins.size());
	for (const auto &entry : listeners_) {
		if (std::optional<Delivery> d = resolve(entry.second, origins, starts, combined, direct, cap, level, event_id)) {
			out.push_back(*d);
		}
	}
	return out;
}

std::optional<Delivery> RoadGraph::deliver(Coord source, double level, Coord listener_tile, Mode mode, double threshold,
		double multiplier, uint64_t key) const {
	const std::vector<Coord> origins = {source};
	const std::vector<Start> starts = {starts_for(source, 0)};
	const double cap = std::min(params.search_cap_air, std::max(0.0, (level - threshold) * multiplier));
	SearchResult result;
	search(starts[0].nodes, mode, cap, result);
	Listener l;
	l.id = 0;
	l.tile = listener_tile;
	l.threshold = threshold;
	l.multiplier = multiplier;
	Direct direct(origins.size());
	return resolve(l, origins, starts, result, direct, cap, level, key);
}

std::optional<double> RoadGraph::path_cost(Coord a, Coord b, Mode mode, double max) const {
	std::optional<Delivery> d = deliver(a, max, b, mode);
	if (!d) {
		return std::nullopt;
	}
	return d->path_tiles + static_cast<double>(d->closed_portals) * params.closed_cost;
}

std::optional<Coord> RoadGraph::nearest_open_tile(Coord rock_tile, int64_t max_radius) const {
	std::optional<Coord> best;
	int64_t best_d2 = 0;
	for (int64_t y = rock_tile.y - max_radius; y <= rock_tile.y + max_radius; y++) {
		for (int64_t x = rock_tile.x - max_radius; x <= rock_tile.x + max_radius; x++) {
			const Coord t{x, y};
			if (!zone_of(t) && !portal_of(t)) {
				continue;
			}
			const int64_t d2 = (x - rock_tile.x) * (x - rock_tile.x) + (y - rock_tile.y) * (y - rock_tile.y);
			if (best && d2 >= best_d2) {
				continue; // row-major scan keeps the lowest (y, x) on ties
			}
			if (rock_line(mine_, rock_tile, t).brick) {
				continue;
			}
			best = t;
			best_d2 = d2;
		}
	}
	return best;
}

uint64_t RoadGraph::tables_digest() const {
	// Keyed by stable identities (cell, zone id; cell, portal id or edge zone pair), so a
	// reloaded cell compares equal to a fresh build whatever its internal indices.
	std::vector<int64_t> keys;
	auto zone_key = [&](uint32_t z) { return std::make_tuple(zones_[z].cell.y, zones_[z].cell.x, zones_[z].id); };
	auto portal_key = [&](uint32_t p) {
		const Portal &x = portals_[p];
		auto a = zone_key(x.zone[0]);
		auto b = zone_key(x.zone[1]);
		return std::make_tuple(x.cell.y, x.cell.x, x.id, std::min(a, b), std::max(a, b));
	};
	std::vector<uint32_t> live_zones;
	for (uint32_t z = 0; z < zones_.size(); z++) {
		if (zones_[z].live) {
			live_zones.push_back(z);
		}
	}
	std::sort(live_zones.begin(), live_zones.end(), [&](uint32_t a, uint32_t b) { return zone_key(a) < zone_key(b); });
	for (uint32_t z : live_zones) {
		const Zone &zone = zones_[z];
		keys.push_back(zone.cell.x);
		keys.push_back(zone.cell.y);
		keys.push_back(zone.id);
		keys.push_back(static_cast<int64_t>(zone.tiles.size()));
		std::vector<uint32_t> ps = zone.portals;
		std::sort(ps.begin(), ps.end(), [&](uint32_t a, uint32_t b) { return portal_key(a) < portal_key(b); });
		for (uint32_t p : ps) {
			const Portal &portal = portals_[p];
			keys.push_back(static_cast<int64_t>(portal.kind));
			keys.push_back(portal.id);
			keys.push_back(portal.open ? 1 : 0);
			for (double v : zone.field.at(p)) {
				keys.push_back(v == INF ? -1 : std::llround(v * 1000.0));
			}
		}
	}
	return lb::core::hash_u64(0, lb::core::hash_domain::SOUND_JITTER, keys.data(), keys.size());
}

} // namespace lb::core::sound

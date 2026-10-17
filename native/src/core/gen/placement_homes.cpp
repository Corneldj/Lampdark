// GEN-10's run-start homes pass (Gameplay §8.1, §7.2, §6.6, §4.4, §10.10, §12.4): the Moth's
// roosts and its start, the near-gate phones, the electric lamp's cell and the canary region,
// pure in the header's seed and plan, written into the header's homes so a resume keeps them.

#include "core/gen/biomes.h"
#include "core/gen/placement.h"
#include "core/generated/hash_domains.h"
#include "core/rng/rng.h"
#include "core/world/materials.h"

#include <algorithm>
#include <deque>
#include <set>

namespace lb::core::gen {

using lb::core::world::Anchor;
using lb::core::world::AnchorType;
using lb::core::world::Coord;

namespace hd = lb::core::hash_domain;

namespace {

int64_t sq(int64_t v) { return v * v; }

int64_t dist2(Coord a, Coord b) { return sq(a.x - b.x) + sq(a.y - b.y); }

uint64_t homes_hash(uint64_t seed, int64_t what, int64_t index = 0) {
	const int64_t keys[2] = {what, index};
	return hash_u64(seed, hd::GEN_PLACE_HOMES, keys, 2);
}

void put_i64(std::vector<uint8_t> &b, int64_t v) {
	for (int i = 0; i < 8; i++) {
		b.push_back(static_cast<uint8_t>((static_cast<uint64_t>(v) >> (8 * i)) & 0xFFu));
	}
}

void put_i32(std::vector<uint8_t> &b, int32_t v) {
	for (int i = 0; i < 4; i++) {
		b.push_back(static_cast<uint8_t>((static_cast<uint32_t>(v) >> (8 * i)) & 0xFFu));
	}
}

bool get_i64(const std::vector<uint8_t> &b, size_t &at, int64_t &out) {
	if (at + 8 > b.size()) {
		return false;
	}
	uint64_t v = 0;
	for (int i = 0; i < 8; i++) {
		v |= static_cast<uint64_t>(b[at + static_cast<size_t>(i)]) << (8 * i);
	}
	at += 8;
	out = static_cast<int64_t>(v);
	return true;
}

bool get_i32(const std::vector<uint8_t> &b, size_t &at, int32_t &out) {
	if (at + 4 > b.size()) {
		return false;
	}
	uint32_t v = 0;
	for (int i = 0; i < 4; i++) {
		v |= static_cast<uint32_t>(b[at + static_cast<size_t>(i)]) << (8 * i);
	}
	at += 4;
	out = static_cast<int32_t>(v);
	return true;
}

bool one_lamp(const RunHeader &h) { return h.hard_variant == "one_lamp"; }
bool dead_lines(const RunHeader &h) { return h.hard_variant == "dead_lines"; }

// The plan's hoard: the centre tile of its footprint.
std::optional<Coord> hoard_of(const RunHeader &h) {
	for (const PlannedSite &s : h.plan.sites) {
		if (s.kind != PoiKind::HOARD || s.cells.empty()) {
			continue;
		}
		Coord lo = s.cells[0];
		Coord hi = s.cells[0];
		for (const Coord &c : s.cells) {
			lo = {std::min(lo.x, c.x), std::min(lo.y, c.y)};
			hi = {std::max(hi.x, c.x), std::max(hi.y, c.y)};
		}
		const int64_t n = lb::core::world::CELL_TILES;
		return Coord{lb::core::world::floor_div(lo.x * n + (hi.x + 1) * n, 2), lb::core::world::floor_div(lo.y * n + (hi.y + 1) * n, 2)};
	}
	return std::nullopt;
}

bool is_floor_at(const Layout &l, Coord local) {
	if (local.x < 0 || local.y < 0 || local.x >= lb::core::world::CELL_TILES || local.y >= lb::core::world::CELL_TILES) {
		return false;
	}
	return l.cell.tiles[static_cast<size_t>(lb::core::world::Cell::index_of(local.x, local.y))].material ==
			static_cast<uint8_t>(lb::core::world::TileMaterial::FLOOR);
}

bool is_rock_at(const Layout &l, Coord local) {
	if (local.x < 0 || local.y < 0 || local.x >= lb::core::world::CELL_TILES || local.y >= lb::core::world::CELL_TILES) {
		return false;
	}
	const uint8_t m = l.cell.tiles[static_cast<size_t>(lb::core::world::Cell::index_of(local.x, local.y))].material;
	return m == static_cast<uint8_t>(lb::core::world::TileMaterial::ROCK) || m == static_cast<uint8_t>(lb::core::world::TileMaterial::COAL);
}

// A near-gate phone on the road out of gate `g`: a floor tile against rock, 11-40 tiles by path
// (4-connected, through the gate cell and the next one out) from base camp's opening.
std::optional<Coord> gate_phone(const PlacementWorld &world, const PlacementParams &p, Edge g, Rng &r) {
	const RunHeader &h = world.header();
	const std::optional<Socket> gate = h.forced.query(edge_of({0, 0}, g));
	if (!gate || !gate->open) {
		return std::nullopt;
	}
	const Coord gc = neighbour({0, 0}, g);
	const Coord next = neighbour(gc, g);
	std::map<Coord, Layout> cells;
	for (const Coord &c : {gc, next}) {
		const std::optional<Layout> l = world.layout(c);
		if (l && !l->base_camp) {
			cells.emplace(c, *l);
		}
	}
	if (!cells.count(gc)) {
		return std::nullopt;
	}
	auto floor = [&](Coord t) {
		const auto it = cells.find(lb::core::world::cell_of(t));
		return it != cells.end() && is_floor_at(it->second, lb::core::world::local_of(t));
	};
	auto rock = [&](Coord t) {
		const auto it = cells.find(lb::core::world::cell_of(t));
		return it != cells.end() && is_rock_at(it->second, lb::core::world::local_of(t));
	};
	// Base camp's opening, seen from the gate cell: its edge facing base camp.
	const int64_t last = lb::core::world::CELL_TILES - 1;
	const int32_t first = opening_first(gate->offset, gate->width);
	std::map<Coord, int64_t> dist;
	std::deque<Coord> queue;
	for (int32_t i = 0; i < gate->width; i++) {
		Coord local;
		switch (g) {
			case Edge::NORTH:
				local = {first + i, last};
				break;
			case Edge::SOUTH:
				local = {first + i, 0};
				break;
			case Edge::EAST:
				local = {0, first + i};
				break;
			default:
				local = {last, first + i};
				break;
		}
		const Coord t = lb::core::world::tile_of(gc, local);
		if (floor(t) && !dist.count(t)) {
			dist[t] = 0;
			queue.push_back(t);
		}
	}
	while (!queue.empty()) {
		const Coord t = queue.front();
		queue.pop_front();
		const int64_t d = dist[t];
		if (d >= p.phones_near_gates_max_path) {
			continue;
		}
		for (const Coord step : {Coord{1, 0}, Coord{-1, 0}, Coord{0, 1}, Coord{0, -1}}) {
			const Coord n{t.x + step.x, t.y + step.y};
			if (floor(n) && !dist.count(n)) {
				dist[n] = d + 1;
				queue.push_back(n);
			}
		}
	}
	std::vector<Coord> sites;
	for (const auto &[t, d] : dist) {
		if (d < p.phones_near_gates_min_path || d > p.phones_near_gates_max_path) {
			continue;
		}
		if (rock({t.x + 1, t.y}) || rock({t.x - 1, t.y}) || rock({t.x, t.y + 1}) || rock({t.x, t.y - 1})) {
			sites.push_back(t);
		}
	}
	if (sites.empty()) {
		return std::nullopt;
	}
	return sites[static_cast<size_t>(*r.range(0, static_cast<int64_t>(sites.size()) - 1))];
}

} // namespace

Homes make_homes(const PlacementWorld &world, const PlacementParams &p) {
	Homes out;
	const RunHeader &h = world.header();
	const std::vector<int64_t> &bounds = world.ring_bounds();
	out.hoard = hoard_of(h);
	// The roosts: chambers tagged high within 60 tiles of the hoard (centre to centre, Proposed),
	// none in the hoard itself or base camp; a staged run 1's at least so far from the shaft.
	if (out.hoard) {
		std::set<Coord> hoard_cells;
		for (const PlannedSite &s : h.plan.sites) {
			if (s.kind == PoiKind::HOARD) {
				hoard_cells.insert(s.cells.begin(), s.cells.end());
			}
		}
		const Coord hc = lb::core::world::cell_of(*out.hoard);
		const int64_t reach = p.roost_max_from_hoard / lb::core::world::CELL_TILES + 2;
		const Coord hoard_x2{2 * out.hoard->x + 1, 2 * out.hoard->y + 1};
		const Coord shaft_x2{lb::core::world::SHAFT_CENTRE_X2, lb::core::world::SHAFT_CENTRE_Y2};
		const int64_t roost_min = staged_value(h, p.staged_roost_min_from_shaft, p.roost_min_from_shaft);
		struct Candidate {
			uint64_t key;
			TileBox box;
		};
		std::vector<Candidate> found;
		for (int64_t dy = -reach; dy <= reach; dy++) {
			for (int64_t dx = -reach; dx <= reach; dx++) {
				const Coord c{hc.x + dx, hc.y + dy};
				if (c == Coord{0, 0} || hoard_cells.count(c)) {
					continue;
				}
				const std::optional<Layout> l = world.layout(c);
				if (!l || l->base_camp) {
					continue;
				}
				for (size_t i = 0; i < l->cell.anchors.size(); i++) {
					const Anchor &a = l->cell.anchors[i];
					if (a.type != AnchorType::CHAMBER || std::find(a.tags.begin(), a.tags.end(), "high") == a.tags.end()) {
						continue;
					}
					const Coord t = lb::core::world::tile_of(c, {a.x, a.y});
					const TileBox box{t.x, t.y, a.w, a.h};
					const Coord centre_x2{2 * box.x + box.w, 2 * box.y + box.h};
					if (dist2(centre_x2, hoard_x2) > sq(2 * p.roost_max_from_hoard)) {
						continue;
					}
					if (roost_min > 0 && dist2(centre_x2, shaft_x2) < sq(2 * roost_min)) {
						continue;
					}
					const int64_t keys[3] = {c.x, c.y, static_cast<int64_t>(i)};
					found.push_back({hash_u64(h.seed, hd::GEN_PLACE_HOMES, keys, 3), box});
				}
			}
		}
		std::sort(found.begin(), found.end(), [](const Candidate &a, const Candidate &b) {
			return a.key != b.key ? a.key < b.key : std::tie(a.box.y, a.box.x) < std::tie(b.box.y, b.box.x);
		});
		Rng r(homes_hash(h.seed, 1));
		const int64_t want = *r.range(std::min(p.roosts_min, p.roosts_max), std::max(p.roosts_min, p.roosts_max));
		out.roosts_short = static_cast<int64_t>(found.size()) < p.roosts_min;
		for (int64_t i = 0; i < want && i < static_cast<int64_t>(found.size()); i++) {
			out.roosts.push_back(found[static_cast<size_t>(i)].box);
		}
		// The Moth's start: one of the roosts or the hoard (-1), drawn.
		out.start_roost = static_cast<int32_t>(*r.range(-1, static_cast<int64_t>(out.roosts.size()) - 1));
	}
	// The near-gate phones: on two of base camp's gate roads, drawn.
	if (!dead_lines(h) && p.phones_near_gates > 0) {
		std::vector<Edge> gates;
		for (int e = 0; e < 4; e++) {
			const std::optional<Socket> s = h.forced.query(edge_of({0, 0}, static_cast<Edge>(e)));
			if (s && s->open) {
				gates.push_back(static_cast<Edge>(e));
			}
		}
		Rng r(homes_hash(h.seed, 2));
		r.shuffle(gates);
		for (size_t k = 0; k < gates.size() && static_cast<int64_t>(out.gate_phones.size()) < p.phones_near_gates; k++) {
			Rng site(homes_hash(h.seed, 3, static_cast<int64_t>(gates[k])));
			if (const std::optional<Coord> t = gate_phone(world, p, gates[k], site)) {
				out.gate_phones.push_back(*t);
			}
		}
	}
	// The electric hand lamp: 0-1 a run, in ring 2 or the next (Proposed), at a drawn cell.
	if (!one_lamp(h) && p.electric_lamp_max > 0 && static_cast<int64_t>(homes_hash(h.seed, 4) % 1000000u) < p.electric_lamp_ppm &&
			!bounds.empty()) {
		const int64_t lo = p.electric_lamp_min_ring;
		const int64_t hi = lo + 1;
		const int64_t edge = static_cast<int64_t>(bounds.size()) > hi ? bounds[static_cast<size_t>(hi)] : bounds.back() + 200;
		const int64_t r_cells = edge / lb::core::world::CELL_TILES + 1;
		Rng r(homes_hash(h.seed, 5));
		for (int attempt = 0; attempt < 512; attempt++) {
			const Coord c{*r.range(-r_cells, r_cells), *r.range(-r_cells, r_cells)};
			const int64_t ring = ring_of_cell(c, bounds);
			if (c != Coord{0, 0} && ring >= lo && ring <= hi) {
				out.electric_lamp = c;
				break;
			}
		}
	}
	// The canary: one region whose centre lies in rings 1-3 and holds a first-aid station (GEN-09:
	// the first one there keeps it).
	if (p.canary_max > 0 && bounds.size() >= 3) {
		const int64_t span = lb::core::world::REGION_CELLS * lb::core::world::CELL_TILES;
		const int64_t reach = bounds[std::min<size_t>(3, bounds.size() - 1)] / span + 1;
		std::vector<std::pair<uint64_t, Coord>> found;
		for (int64_t ry = -reach; ry <= reach; ry++) {
			for (int64_t rx = -reach; rx <= reach; rx++) {
				const Coord region{rx, ry};
				const Coord centre{rx * lb::core::world::REGION_CELLS + lb::core::world::REGION_CELLS / 2,
						ry * lb::core::world::REGION_CELLS + lb::core::world::REGION_CELLS / 2};
				const int64_t ring = ring_of_cell(centre, bounds);
				if (ring < 1 || ring > 3) {
					continue;
				}
				const std::shared_ptr<const RegionLayout> layout = world.region(region);
				if (!layout) {
					continue;
				}
				bool station = false;
				for (const Poi &poi : layout->pois) {
					station = station || poi.kind == PoiKind::FIRST_AID_STATION;
				}
				if (station) {
					const int64_t keys[2] = {rx, ry};
					found.push_back({hash_u64(h.seed, hd::GEN_PLACE_HOMES, keys, 2), region});
				}
			}
		}
		if (!found.empty()) {
			std::sort(found.begin(), found.end(), [](const auto &a, const auto &b) { return a.first != b.first ? a.first < b.first : a.second < b.second; });
			out.canary = found[0].second;
		}
	}
	return out;
}

void write_homes(const Homes &x, RunHeader &h) {
	std::vector<uint8_t> roosts;
	roosts.push_back(static_cast<uint8_t>(std::min<size_t>(x.roosts.size(), 255)));
	for (size_t i = 0; i < x.roosts.size() && i < 255; i++) {
		put_i64(roosts, x.roosts[i].x);
		put_i64(roosts, x.roosts[i].y);
		put_i32(roosts, x.roosts[i].w);
		put_i32(roosts, x.roosts[i].h);
	}
	h.homes["roosts"] = roosts;
	std::vector<uint8_t> start;
	put_i32(start, x.start_roost);
	h.homes["start_roost"] = start;
	std::vector<uint8_t> phones;
	phones.push_back(static_cast<uint8_t>(std::min<size_t>(x.gate_phones.size(), 255)));
	for (size_t i = 0; i < x.gate_phones.size() && i < 255; i++) {
		put_i64(phones, x.gate_phones[i].x);
		put_i64(phones, x.gate_phones[i].y);
	}
	h.homes["gate_phones"] = phones;
	h.homes.erase("electric_lamp");
	if (x.electric_lamp) {
		std::vector<uint8_t> lamp;
		put_i64(lamp, x.electric_lamp->x);
		put_i64(lamp, x.electric_lamp->y);
		h.homes["electric_lamp"] = lamp;
	}
	h.homes.erase("canary");
	if (x.canary) {
		h.homes["canary"] = canary_home(*x.canary);
	}
}

Homes read_homes(const RunHeader &h) {
	Homes x;
	x.hoard = hoard_of(h);
	if (const auto it = h.homes.find("roosts"); it != h.homes.end() && !it->second.empty()) {
		const std::vector<uint8_t> &b = it->second;
		size_t at = 1;
		for (uint8_t i = 0; i < b[0]; i++) {
			TileBox box;
			if (!get_i64(b, at, box.x) || !get_i64(b, at, box.y) || !get_i32(b, at, box.w) || !get_i32(b, at, box.h)) {
				break;
			}
			x.roosts.push_back(box);
		}
	}
	if (const auto it = h.homes.find("start_roost"); it != h.homes.end()) {
		size_t at = 0;
		get_i32(it->second, at, x.start_roost);
	}
	if (const auto it = h.homes.find("gate_phones"); it != h.homes.end() && !it->second.empty()) {
		const std::vector<uint8_t> &b = it->second;
		size_t at = 1;
		for (uint8_t i = 0; i < b[0]; i++) {
			Coord t;
			if (!get_i64(b, at, t.x) || !get_i64(b, at, t.y)) {
				break;
			}
			x.gate_phones.push_back(t);
		}
	}
	if (const auto it = h.homes.find("electric_lamp"); it != h.homes.end()) {
		size_t at = 0;
		Coord c;
		if (get_i64(it->second, at, c.x) && get_i64(it->second, at, c.y)) {
			x.electric_lamp = c;
		}
	}
	x.canary = canary_region(h);
	return x;
}

} // namespace lb::core::gen

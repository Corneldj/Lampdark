#include "core/gen/poi.h"

#include "core/gen/biomes.h"
#include "core/generated/hash_domains.h"
#include "core/rng/hash.h"

#include <algorithm>
#include <cmath>

namespace lb::core::gen {

using lb::core::world::AnchorType;
using lb::core::world::CELL_TILES;
using lb::core::world::Coord;
using lb::core::world::REGION_CELLS;
using lb::core::world::region_of_cell;

namespace {

constexpr size_t KINDS = static_cast<size_t>(PoiKind::COUNT);

// gen.poi_region's slot key: the drawn ones count from 0; the region's own rolls and the planned
// sites' template choices take these.
constexpr int64_t SLOT_TWO = -1;
constexpr int64_t SLOT_LAMP_CABIN = -2;
constexpr int64_t SLOT_FIRST_AID = -3;
constexpr int64_t SLOT_SPECIALS_ORDER = -4;
constexpr int64_t SLOT_PLANNED = -100; // minus the site's index

// Kinds drawn by ring weight: not the two with their own rates, never the plan's own.
bool drawable(PoiKind k) {
	return k != PoiKind::LAMP_CABIN && k != PoiKind::FIRST_AID_STATION && k != PoiKind::SUBSTATION && k != PoiKind::HOARD &&
			k != PoiKind::LAIR;
}

// A template by its weight among the distinct templates of `shapes` (nullptr for none).
const Template *pick_template(Rng &r, const std::vector<const PoiShape *> &shapes) {
	std::vector<const Template *> bases;
	for (const PoiShape *s : shapes) {
		if (std::find(bases.begin(), bases.end(), s->base) == bases.end()) {
			bases.push_back(s->base);
		}
	}
	if (bases.empty()) {
		return nullptr;
	}
	std::vector<int64_t> weights;
	for (const Template *t : bases) {
		weights.push_back(std::max<int64_t>(0, std::llround(t->weight * 1000.0)));
	}
	const std::optional<size_t> b = r.pick_weighted(weights.data(), weights.size());
	return bases[b ? *b : 0];
}

// A template by its weight, then one of its shapes in `shapes` evenly.
const PoiShape *pick_shape(Rng &r, const std::vector<const PoiShape *> &shapes) {
	const Template *base = pick_template(r, shapes);
	std::vector<const PoiShape *> of;
	for (const PoiShape *s : shapes) {
		if (s->base == base) {
			of.push_back(s);
		}
	}
	return of.empty() ? nullptr : of[static_cast<size_t>(*r.range(0, static_cast<int64_t>(of.size()) - 1))];
}

} // namespace

PoiParams::PoiParams() {
	rings.fill({1, 3});
	for (PoiKind k : {PoiKind::LAMP_CABIN, PoiKind::FITTERS_SHOP, PoiKind::FUEL_STORE, PoiKind::ELECTRICIANS_CABIN,
				 PoiKind::HAULAGE_ENGINE_HOUSE, PoiKind::STABLES}) {
		rings[static_cast<size_t>(k)] = {1, 2};
	}
	rings[static_cast<size_t>(PoiKind::DEEP_WORKSHOP)] = {2, 3};
	rings[static_cast<size_t>(PoiKind::POWDER_MAGAZINE)] = {2, 3};
	rings[static_cast<size_t>(PoiKind::CAPPED_SHAFT)] = {2, 4};
	// Equal among the drawn kinds in every ring; each kind's rings decide where it may lie.
	std::array<double, KINDS> equal{};
	for (size_t k = 0; k < KINDS; k++) {
		equal[k] = drawable(static_cast<PoiKind>(k)) ? 1.0 : 0.0;
	}
	weights.assign(5, equal);
}

std::vector<Coord> Poi::cells() const {
	std::vector<Coord> out;
	for (int64_t y = 0; y < h; y++) {
		for (int64_t x = 0; x < w; x++) {
			out.push_back(Coord{origin.x + x, origin.y + y});
		}
	}
	return out;
}

std::vector<TileRect> Poi::slots() const {
	std::vector<TileRect> out;
	if (shape == nullptr) {
		return out;
	}
	for (TileRect r : shape->slots) {
		r.x += origin.x * CELL_TILES;
		r.y += origin.y * CELL_TILES;
		out.push_back(r);
	}
	return out;
}

PoiShapes::PoiShapes(const TemplateSet &set, const std::vector<int32_t> &offsets) {
	for (const Template &t : set.templates()) {
		const std::optional<PoiKind> kind = t.kind == TemplateKind::POI ? poi_kind_from(t.poi_kind) : std::nullopt;
		if (!kind) {
			continue;
		}
		for (int32_t o = 0; o < 8; o++) {
			auto shape = std::make_unique<PoiShape>();
			shape->base = &t;
			shape->orientation = o;
			shape->oriented = orient(t, o);
			// Its doors must land on socket offsets; another stub that does not is never opened, and
			// fills as a blind heading.
			bool doors = false;
			bool legal = true;
			for (const Stub &s : shape->oriented.stubs) {
				if (s.door) {
					doors = true;
					legal = legal && std::find(offsets.begin(), offsets.end(), s.offset) != offsets.end();
				}
			}
			if (!doors || !legal) {
				continue;
			}
			for (const lb::core::world::Cell &c : t.cells) {
				for (const lb::core::world::Anchor &a : c.anchors) {
					if (a.type != AnchorType::POI_SLOT) {
						continue;
					}
					const int64_t gx = c.coord.x * CELL_TILES + a.x;
					const int64_t gy = c.coord.y * CELL_TILES + a.y;
					const Coord p = oriented_tile(gx, gy, t.footprint_w, t.footprint_h, o);
					const Coord q = oriented_tile(gx + a.w - 1, gy + a.h - 1, t.footprint_w, t.footprint_h, o);
					TileRect r;
					r.x = std::min(p.x, q.x);
					r.y = std::min(p.y, q.y);
					r.w = static_cast<int32_t>(std::max(p.x, q.x) - r.x + 1);
					r.h = static_cast<int32_t>(std::max(p.y, q.y) - r.y + 1);
					shape->slots.push_back(r);
				}
			}
			by_kind_[static_cast<size_t>(*kind)].push_back(shape.get());
			shapes_.push_back(std::move(shape));
		}
	}
}

PointsOfInterest::PointsOfInterest(const RunHeader &header, const TemplateSet &templates, PoiParams params, PoiWorld world,
		size_t capacity)
	: PointsOfInterest(header, std::make_shared<const PoiShapes>(templates, header.sockets.offsets), std::move(params), std::move(world),
			  capacity) {}

PointsOfInterest::PointsOfInterest(const RunHeader &header, std::shared_ptr<const PoiShapes> shapes, PoiParams params, PoiWorld world,
		size_t capacity)
	: header_(header), shapes_(std::move(shapes)), params_(std::move(params)), world_(std::move(world)), capacity_(capacity) {
	spine_cells_ = spine_cells(header_.plan);
	for (size_t i = 0; i < header_.plan.sites.size(); i++) {
		const PlannedSite &s = header_.plan.sites[i];
		planned_cells_.insert(s.cells.begin(), s.cells.end());
		planned_approaches_.insert(s.approach());
		planned_by_region_[region_of_cell(s.door)].push_back(static_cast<int32_t>(i));
	}
}

int64_t PointsOfInterest::ring_of(Coord c) const {
	return ring_of_cell(c, params_.ring_bounds);
}

struct PointsOfInterest::Cells {
	Coord region;
	std::array<int64_t, REGION_CELLS * REGION_CELLS> ring{};
	std::array<bool, REGION_CELLS * REGION_CELLS> road{};
	std::array<bool, REGION_CELLS * REGION_CELLS> fixed{};
	Coord at(size_t i) const {
		return Coord{region.x * REGION_CELLS + static_cast<int64_t>(i) % REGION_CELLS, region.y * REGION_CELLS + static_cast<int64_t>(i) / REGION_CELLS};
	}
	// The index of a cell of the region (callers check region_of_cell first).
	size_t of(Coord c) const {
		return static_cast<size_t>((c.y - region.y * REGION_CELLS) * REGION_CELLS + (c.x - region.x * REGION_CELLS));
	}
};

// Base camp, a main road, a spine, a planned site or its door's approach, or beside an old fall.
bool PointsOfInterest::fixed_block(Coord c) const {
	if ((c.x == 0 && c.y == 0) || spine_cells_.count(c) != 0 || planned_cells_.count(c) != 0 || planned_approaches_.count(c) != 0) {
		return true;
	}
	if (world_.is_main_road_cell && world_.is_main_road_cell(c)) {
		return true;
	}
	// An old fall's exits open onto the cells beside it: no point of interest there shuts one.
	if (world_.is_old_fall) {
		for (int e = 0; e < 4; e++) {
			if (world_.is_old_fall(neighbour(c, static_cast<Edge>(e)))) {
				return true;
			}
		}
	}
	return false;
}

Poi PointsOfInterest::planned_poi(int32_t site, Coord region, int32_t index) const {
	const PlannedSite &s = header_.plan.sites[static_cast<size_t>(site)];
	Poi p;
	p.id = PoiId{region, index};
	p.kind = s.kind;
	p.planned = site;
	p.door = s.door;
	p.door_side = s.door_side;
	p.attempt = s.attempt;
	Coord lo = s.door;
	Coord hi = s.door;
	for (const Coord &c : s.cells) {
		lo = Coord{std::min(lo.x, c.x), std::min(lo.y, c.y)};
		hi = Coord{std::max(hi.x, c.x), std::max(hi.y, c.y)};
	}
	p.origin = lo;
	p.w = static_cast<int32_t>(hi.x - lo.x + 1);
	p.h = static_cast<int32_t>(hi.y - lo.y + 1);
	// A template and orientation of its footprint whose door stub lies on its door cell and side.
	std::vector<const PoiShape *> fits;
	for (const PoiShape *shape : shapes_->of(s.kind)) {
		if (shape->oriented.footprint_w != p.w || shape->oriented.footprint_h != p.h) {
			continue;
		}
		for (const Stub &d : shape->oriented.stubs) {
			if (d.door && d.edge == s.door_side && Coord{lo.x + d.cell.x, lo.y + d.cell.y} == s.door) {
				fits.push_back(shape);
				break;
			}
		}
	}
	if (!fits.empty()) {
		const int64_t keys[3] = {region.x, region.y, SLOT_PLANNED - site};
		Rng r(sub_seed(header_.seed, hash_domain::GEN_POI_REGION, keys, 3, 0));
		p.shape = pick_shape(r, fits);
		p.biome = s.kind == PoiKind::LAIR ? params_.lair_biome : p.shape->base->biome;
	}
	return p;
}

std::optional<Poi> PointsOfInterest::drawn_poi(Rng &r, const Cells &cells, std::optional<PoiKind> special, const std::set<Coord> &taken,
		const std::set<Coord> &approaches) const {
	const Coord region = cells.region;
	auto blocked = [&](size_t i) {
		const Coord c = cells.at(i);
		return cells.fixed[i] || taken.count(c) != 0 || approaches.count(c) != 0;
	};
	auto weight = [&](PoiKind k, int64_t ring) -> int64_t {
		const auto [lo, hi] = params_.rings[static_cast<size_t>(k)];
		if (!drawable(k) || ring < lo || ring > hi || shapes_->of(k).empty() || params_.weights.empty()) {
			return 0;
		}
		const size_t row = std::min(static_cast<size_t>(std::max<int64_t>(ring, 0)), params_.weights.size() - 1);
		return std::max<int64_t>(0, std::llround(params_.weights[row][static_cast<size_t>(k)] * 1000.0));
	};
	auto in_rings = [&](PoiKind k, int64_t ring) {
		const auto [lo, hi] = params_.rings[static_cast<size_t>(k)];
		return ring >= lo && ring <= hi;
	};
	// Its door cell: hashed among the region's cells that may hold one for this slot.
	std::vector<size_t> doors;
	for (size_t i = 0; i < cells.ring.size(); i++) {
		const int64_t ring = cells.ring[i];
		if (ring < params_.min_ring || blocked(i)) {
			continue;
		}
		bool any = false;
		if (special) {
			any = in_rings(*special, ring) && !shapes_->of(*special).empty();
		} else {
			for (size_t k = 0; k < KINDS && !any; k++) {
				any = weight(static_cast<PoiKind>(k), ring) > 0;
			}
		}
		if (any) {
			doors.push_back(i);
		}
	}
	if (doors.empty()) {
		return std::nullopt;
	}
	const size_t door_at = doors[static_cast<size_t>(*r.range(0, static_cast<int64_t>(doors.size()) - 1))];
	const Coord door = cells.at(door_at);
	const int64_t ring = cells.ring[door_at];
	PoiKind kind = PoiKind::STORES;
	if (special) {
		kind = *special;
	} else {
		std::array<int64_t, KINDS> w{};
		for (size_t k = 0; k < KINDS; k++) {
			w[k] = weight(static_cast<PoiKind>(k), ring);
		}
		const std::optional<size_t> k = r.pick_weighted(w.data(), w.size());
		if (!k) {
			return std::nullopt;
		}
		kind = static_cast<PoiKind>(*k);
	}
	// The template by its weight; then, of its orientations and doors, one that fits with its door
	// on this cell.
	const std::vector<const PoiShape *> &of = shapes_->of(kind);
	const Template *base = pick_template(r, of);
	auto fits = [&](const Poi &p) {
		for (const Coord &c : p.cells()) {
			if (region_of_cell(c) != region || cells.ring[cells.of(c)] < params_.min_ring || blocked(cells.of(c))) {
				return false;
			}
		}
		// Its door opens onto a cell of its own region (so no other region's point of interest
		// can stand there) that is no main road (whose templates have no side door).
		const Coord a = p.approach();
		return region_of_cell(a) == region && !(a.x == 0 && a.y == 0) && !p.contains(a) && taken.count(a) == 0 &&
				planned_cells_.count(a) == 0 && !cells.road[cells.of(a)];
	};
	std::vector<Poi> options;
	for (const PoiShape *shape : of) {
		if (shape->base != base) {
			continue;
		}
		for (const Stub &d : shape->oriented.stubs) {
			if (!d.door) {
				continue;
			}
			Poi p;
			p.kind = kind;
			p.shape = shape;
			p.w = shape->oriented.footprint_w;
			p.h = shape->oriented.footprint_h;
			p.origin = Coord{door.x - d.cell.x, door.y - d.cell.y};
			p.door = door;
			p.door_side = d.edge;
			p.biome = shape->base->biome;
			if (fits(p)) {
				options.push_back(std::move(p));
			}
		}
	}
	if (options.empty()) {
		return std::nullopt;
	}
	return options[static_cast<size_t>(*r.range(0, static_cast<int64_t>(options.size()) - 1))];
}

RegionLayout PointsOfInterest::derive(Coord region) const {
	RegionLayout out;
	out.region = region;
	std::set<Coord> taken;
	std::set<Coord> approaches;
	auto keep = [&](Poi p) {
		for (const Coord &c : p.cells()) {
			taken.insert(c);
		}
		approaches.insert(p.approach());
		out.pois.push_back(std::move(p));
	};
	int32_t planned = 0;
	const auto it = planned_by_region_.find(region);
	if (it != planned_by_region_.end()) {
		for (int32_t site : it->second) {
			keep(planned_poi(site, region, static_cast<int32_t>(out.pois.size())));
			planned++;
		}
	}
	Cells cells;
	cells.region = region;
	for (size_t i = 0; i < cells.ring.size(); i++) {
		const Coord c = cells.at(i);
		cells.ring[i] = ring_of(c);
		cells.road[i] = world_.is_main_road_cell && world_.is_main_road_cell(c);
		cells.fixed[i] = fixed_block(c);
	}
	auto roll = [&](int64_t slot, uint32_t ppm) {
		const int64_t keys[3] = {region.x, region.y, slot};
		return sub_seed(header_.seed, hash_domain::GEN_POI_REGION, keys, 3, 0) % 1000000u < ppm;
	};
	// A lamp cabin or first-aid station by its rate, where the region has an open cell in its rings.
	auto reaches = [&](PoiKind k) {
		const auto [lo, hi] = params_.rings[static_cast<size_t>(k)];
		for (size_t i = 0; i < cells.ring.size(); i++) {
			if (!cells.fixed[i] && cells.ring[i] >= std::max(lo, params_.min_ring) && cells.ring[i] <= hi) {
				return true;
			}
		}
		return false;
	};
	std::vector<PoiKind> specials;
	if (roll(SLOT_LAMP_CABIN, params_.lamp_cabin_ppm) && reaches(PoiKind::LAMP_CABIN)) {
		specials.push_back(PoiKind::LAMP_CABIN);
	}
	if (roll(SLOT_FIRST_AID, params_.first_aid_ppm) && reaches(PoiKind::FIRST_AID_STATION)) {
		specials.push_back(PoiKind::FIRST_AID_STATION);
	}
	// Both: either may take the one place a planned site leaves.
	if (specials.size() == 2 && roll(SLOT_SPECIALS_ORDER, 500000)) {
		std::swap(specials[0], specials[1]);
	}
	const int32_t lo = params_.per_region_min;
	const int32_t hi = std::max(lo, params_.per_region_max);
	int32_t n = std::min(hi, lo + (roll(SLOT_TWO, params_.two_ppm) ? 1 : 0));
	n = std::max(n, std::min(hi, planned + static_cast<int32_t>(specials.size())));
	n = std::max(n, planned);
	out.wanted = n;
	for (int32_t slot = 0; planned + slot < n; slot++) {
		const std::optional<PoiKind> special =
				slot < static_cast<int32_t>(specials.size()) ? std::optional<PoiKind>(specials[static_cast<size_t>(slot)]) : std::nullopt;
		for (int32_t attempt = 0; attempt < params_.fit_tries; attempt++) {
			const int64_t keys[3] = {region.x, region.y, slot};
			Rng r(sub_seed(header_.seed, hash_domain::GEN_POI_REGION, keys, 3, attempt));
			std::optional<Poi> p = drawn_poi(r, cells, special, taken, approaches);
			if (p) {
				p->id = PoiId{region, static_cast<int32_t>(out.pois.size())};
				p->attempt = attempt;
				keep(std::move(*p));
				break;
			}
		}
	}
	return out;
}

std::shared_ptr<const RegionLayout> PointsOfInterest::region(Coord region) const {
	{
		std::lock_guard<std::mutex> lock(mutex_);
		if (caching_) {
			const auto it = cached_.find(region);
			if (it != cached_.end()) {
				order_.splice(order_.begin(), order_, it->second);
				return it->second->second;
			}
		}
	}
	auto layout = std::make_shared<const RegionLayout>(derive(region));
	std::lock_guard<std::mutex> lock(mutex_);
	if (!caching_ || capacity_ == 0) {
		return layout;
	}
	const auto it = cached_.find(region);
	if (it != cached_.end()) {
		return it->second->second; // another thread derived it meanwhile: the same layout
	}
	order_.emplace_front(region, layout);
	cached_[region] = order_.begin();
	if (order_.size() > capacity_) {
		cached_.erase(order_.back().first);
		order_.pop_back();
	}
	return layout;
}

PoiRef PointsOfInterest::at(Coord cell) const {
	PoiRef ref;
	ref.layout = region(region_of_cell(cell));
	for (const Poi &p : ref.layout->pois) {
		if (p.contains(cell)) {
			ref.poi = &p;
			break;
		}
	}
	return ref;
}

PoiRef PointsOfInterest::find(const PoiId &id) const {
	PoiRef ref;
	ref.layout = region(id.region);
	if (id.index >= 0 && static_cast<size_t>(id.index) < ref.layout->pois.size()) {
		ref.poi = &ref.layout->pois[static_cast<size_t>(id.index)];
	}
	return ref;
}

bool PointsOfInterest::is_canary(const PoiId &id) const {
	const std::optional<Coord> region = canary_region(header_);
	if (params_.canary_max < 1 || !region || !(*region == id.region)) {
		return false;
	}
	for (const Poi &p : this->region(id.region)->pois) {
		if (p.kind == PoiKind::FIRST_AID_STATION) {
			return p.id == id;
		}
	}
	return false;
}

void PointsOfInterest::set_caching(bool on) {
	std::lock_guard<std::mutex> lock(mutex_);
	caching_ = on;
	if (!on) {
		order_.clear();
		cached_.clear();
	}
}

std::optional<Socket> PoiSockets::query(const EdgeKey &edge) const {
	const Coord a{edge.x, edge.y};
	const Coord b = edge.axis == Axis::EAST ? Coord{edge.x + 1, edge.y} : Coord{edge.x, edge.y + 1};
	const Edge a_side = edge.axis == Axis::EAST ? Edge::EAST : Edge::SOUTH;
	// Only a templated point of interest has a say.
	auto templated = [&](Coord c) {
		PoiRef r = pois_.at(c);
		if (r && r->shape == nullptr) {
			r.poi = nullptr;
		}
		return r;
	};
	const PoiRef pa = templated(a);
	const PoiRef pb = templated(b);
	if (!pa && !pb) {
		return std::nullopt;
	}
	Socket s;
	s.forced = true;
	if (pa && pb && pa->id == pb->id) {
		return s; // inside one point of interest: no socket, its own floor joins its cells
	}
	// A side's stubs on the edge; one turned off the socket offsets is never opened.
	auto stubs_on = [&](const PoiRef &p, Coord cell, Edge side) {
		std::vector<const Stub *> out;
		if (p) {
			const Coord local{cell.x - p->origin.x, cell.y - p->origin.y};
			for (const Stub &st : p->shape->oriented.stubs) {
				const bool on = std::find(params_.offsets.begin(), params_.offsets.end(), st.offset) != params_.offsets.end();
				if (st.cell == local && st.edge == side && on) {
					out.push_back(&st);
				}
			}
		}
		return out;
	};
	const std::vector<const Stub *> sa = stubs_on(pa, a, a_side);
	const std::vector<const Stub *> sb = stubs_on(pb, b, opposite(a_side));
	const int64_t keys[3] = {edge.x, edge.y, static_cast<int64_t>(edge.axis)};
	auto width_for = [&](int32_t max_width) {
		const std::vector<int32_t> shared = shared_widths(cells_.classify(a).widths, cells_.classify(b).widths, params_);
		std::vector<int32_t> w;
		for (int32_t x : shared) {
			if (x <= max_width) {
				w.push_back(x);
			}
		}
		if (w.empty()) {
			w.push_back(std::min(max_width, shared.empty() ? max_width : shared.front()));
		}
		return w[hash_u64(seed_, hash_domain::GEN_SOCKET_WIDTH, keys, 3) % w.size()];
	};
	for (const std::vector<const Stub *> *side : {&sa, &sb}) {
		for (const Stub *st : *side) {
			if (st->door) {
				s.open = true;
				s.offset = st->offset;
				s.width = width_for(st->max_width);
				return s;
			}
		}
	}
	// Other stubs roll open like any edge: at one side's stub, or between two points of interest at
	// an offset both have; never toward a main road.
	std::vector<std::pair<int32_t, int32_t>> options;
	if (pa && pb) {
		for (const Stub *x : sa) {
			for (const Stub *y : sb) {
				if (x->offset == y->offset) {
					options.push_back({x->offset, std::min(x->max_width, y->max_width)});
				}
			}
		}
	} else {
		for (const Stub *x : pa ? sa : sb) {
			options.push_back({x->offset, x->max_width});
		}
		const Coord other = pa ? b : a;
		if (is_main_road_cell_ && is_main_road_cell_(other)) {
			options.clear();
		}
	}
	if (options.empty() || hash_u64(seed_, hash_domain::GEN_SOCKET_OPEN, keys, 3) % 1000000u >= params_.open_ppm) {
		return s;
	}
	const auto &[offset, max_width] = options[hash_u64(seed_, hash_domain::GEN_SOCKET_OFFSET, keys, 3) % options.size()];
	s.open = true;
	s.offset = offset;
	s.width = width_for(max_width);
	return s;
}

CellClass PoiCells::classify(Coord cell) const {
	CellClass c = base_.classify(cell);
	const PoiRef ref = pois_.at(cell);
	if (!ref || ref->shape == nullptr) {
		return c;
	}
	c.kind = TemplateKind::POI;
	c.templated = true;
	if (!ref->biome.empty()) {
		c.biome = ref->biome;
		if (widths_for_) {
			c.widths = widths_for_(c.biome);
		}
	}
	c.shape.clear();
	c.old_fall = false;
	c.transpose = false;
	c.dress.clear();
	c.poi_template = &ref->shape->oriented;
	c.poi_cell = Coord{cell.x - ref->origin.x, cell.y - ref->origin.y};
	return c;
}

namespace {

const char *const TOOLS[] = {"spanner", "hammer", "crowbar", "wire_cutters"};

class Contents {
public:
	Contents(const RunHeader &h, const PoiContentsParams &p, const Poi &poi, bool canary)
		: h_(h), p_(p), poi_(poi), canary_(canary), table_(p.tables[static_cast<size_t>(poi.kind)]) {
		one_lamp_ = h.hard_variant == "one_lamp";
		dead_lines_ = h.hard_variant == "dead_lines";
		dry_ = std::find(h.draw.begin(), h.draw.end(), "dry_stores") != h.draw.end();
		if (poi.planned >= 0 && static_cast<size_t>(poi.planned) < h.plan.sites.size()) {
			holds_ = h.plan.sites[static_cast<size_t>(poi.planned)].holds;
		}
	}

	std::vector<Content> run() {
		switch (poi_.kind) {
			case PoiKind::LAMP_CABIN: {
				Rng r0 = rng(0);
				lamps(0, between(r0, "gauze_lamps", 2, 4), r0, dry_);
				Rng r1 = rng(1);
				add(1, "oil_flask", between(r1, "oil_flasks", 1, 2));
				add(2, "paraffin_can", planned("paraffin_can", num("paraffin_cans", 1)));
				rest(3);
				phone();
				break;
			}
			case PoiKind::FITTERS_SHOP: {
				// The toolbox: the plan's tools where it fixed them, else 1-2 hashed among the four.
				bool any = false;
				for (const char *tool : TOOLS) {
					const int64_t n = planned(tool, 0);
					add(0, tool, n);
					any = any || n > 0;
				}
				if (!any) {
					Rng r0 = rng(0);
					tools(0, between(r0, "tools", 1, 2), r0);
				}
				rest(1);
				phone();
				break;
			}
			case PoiKind::STORES: {
				Rng r0 = rng(0);
				add(0, "fuse", planned("fuse", between(r0, "fuses", 1, 3)));
				Rng r1 = rng(1);
				add(1, "candle", between(r1, "candles", 1, 3));
				add(2, "paraffin_can", planned("paraffin_can", num("paraffin_cans", 1)));
				Rng r3 = rng(3);
				if (r3.chance_ppm(std::llround(num("tool_probability", 0.3) * 1000000.0))) {
					tools(3, 1, r3);
				}
				rest(4);
				break;
			}
			case PoiKind::FUEL_STORE: {
				Rng r0 = rng(0);
				const int64_t n = planned("paraffin_can", *r0.range(p_.fuel_cans_min, std::max(p_.fuel_cans_min, p_.fuel_cans_max)));
				add(0, "paraffin_can", n, dry_ ? static_cast<int32_t>(std::llround(1000.0 * p_.dry_stores_factor)) : -1);
				rest(1);
				break;
			}
			case PoiKind::ELECTRICIANS_CABIN: {
				Rng r0 = rng(0);
				add(0, "fuse", planned("fuse", between(r0, "fuses", 2, 3)));
				add(1, "wire_cutters", planned("wire_cutters", num("wire_cutters", 1)));
				rest(2);
				break;
			}
			case PoiKind::SUBSTATION:
				// Its fuse board, trip lever and main switch are its template's fixtures (LFT-05).
				add(0, "fuse", planned("fuse", num("spare_fuses", 1)));
				rest(1);
				phone();
				break;
			case PoiKind::HAULAGE_ENGINE_HOUSE:
				add(0, "hammer", planned("hammer", num("hammers", 1)));
				add(1, "tub", num("tubs", 1));
				rest(2);
				break;
			case PoiKind::DEEP_WORKSHOP:
				add(0, "spanner", planned("spanner", num("spanners", 1)));
				rest(1);
				break;
			case PoiKind::FIRST_AID_STATION: {
				Rng r0 = rng(0);
				add(0, "healing_kit", between(r0, "healing_kits", 1, 2));
				add(1, "stretcher", num("stretchers", 1));
				Rng r2 = rng(2);
				add(2, "flare", between(r2, "flares", 1, 2));
				if (canary_) {
					add(3, "canary", 1);
				}
				rest(4);
				phone();
				break;
			}
			case PoiKind::POWDER_MAGAZINE: {
				Rng r0 = rng(0);
				add(0, "flare", between(r0, "flares", 2, 3));
				rest(1);
				break;
			}
			case PoiKind::REFUGE: {
				Rng r0 = rng(0);
				remains(0, between(r0, "remains", 2, 4), r0, true);
				rest(1);
				break;
			}
			case PoiKind::STABLES:
			case PoiKind::CAPPED_SHAFT:
				add(0, "lore", num("lore", 1));
				rest(1);
				break;
			case PoiKind::HOARD: {
				add(0, "coats", 1);
				Rng r1 = rng(1);
				lamps(1, between(r1, "gauze_lamps", 2, 4), r1, false);
				rest(2);
				break;
			}
			case PoiKind::LAIR: {
				Rng r0 = rng(0);
				remains(0, between(r0, "remains", 2, 4), r0, false);
				Rng r1 = rng(1);
				lamps(1, between(r1, "gauze_lamps", 3, 6), r1, false);
				add(2, "brass_checks", 1);
				Rng r3 = rng(3);
				tools(3, between(r3, "tools", 1, 2), r3);
				Rng r4 = rng(4);
				add(4, "healing_kit", between(r4, "healing_kits", 1, 2));
				rest(5);
				break;
			}
			default:
				rest(0);
				break;
		}
		return out_;
	}

private:
	const RunHeader &h_;
	const PoiContentsParams &p_;
	const Poi &poi_;
	bool canary_ = false;
	const std::map<std::string, double> &table_;
	bool one_lamp_ = false;
	bool dead_lines_ = false;
	bool dry_ = false;
	std::vector<Holding> holds_;
	std::vector<Content> out_;

	Rng rng(int32_t line) const {
		const int64_t keys[4] = {poi_.id.region.x, poi_.id.region.y, poi_.id.index, line};
		return Rng(sub_seed(h_.seed, hash_domain::GEN_POI_CONTENTS, keys, 4, 0));
	}

	double num(const std::string &key, double fallback) const {
		const auto it = table_.find(key);
		return it != table_.end() ? it->second : fallback;
	}

	// `<name>_min` to `<name>_max` of the kind's table (the design's values where missing).
	int64_t between(Rng &r, const std::string &name, int64_t lo, int64_t hi) const {
		const int64_t a = std::llround(num(name + "_min", static_cast<double>(lo)));
		const int64_t b = std::llround(num(name + "_max", static_cast<double>(hi)));
		return *r.range(a, std::max(a, b));
	}

	// The plan's count of `item` here, taken off the plan's list (its line is this one); else `n`.
	int64_t planned(const std::string &item, double n) {
		for (auto it = holds_.begin(); it != holds_.end(); ++it) {
			if (it->item == item) {
				const int64_t count = it->count;
				holds_.erase(it);
				return count;
			}
		}
		return std::llround(n);
	}

	void add(int32_t line, const std::string &thing, int64_t n, int32_t oil = -1) {
		for (int64_t i = 0; i < n; i++) {
			Content c;
			c.line = line;
			c.thing = thing;
			c.oil_milli = oil;
			out_.push_back(c);
		}
	}

	// Found lamps (§4.4): unlit, 25-75% oil (halved in a lamp cabin under Dry Stores), 0-3 notches;
	// none under One Lamp.
	void lamps(int32_t line, int64_t n, Rng &r, bool halved, int32_t with = -1) {
		for (int64_t i = 0; i < n; i++) {
			int64_t oil = *r.range(std::llround(p_.found_oil_min * 1000.0), std::llround(p_.found_oil_max * 1000.0));
			if (halved) {
				oil = std::llround(static_cast<double>(oil) * p_.dry_stores_factor);
			}
			const int64_t notches = *r.range(p_.found_notches_min, std::max(p_.found_notches_min, p_.found_notches_max));
			if (one_lamp_) {
				continue;
			}
			Content c;
			c.line = line;
			c.thing = "gauze_lamp";
			c.oil_milli = static_cast<int32_t>(oil);
			c.notches = static_cast<int32_t>(notches);
			c.with = with;
			out_.push_back(c);
		}
	}

	// `n` of the four tools, no two alike, hashed.
	void tools(int32_t line, int64_t n, Rng &r) {
		std::vector<std::string> all(std::begin(TOOLS), std::end(TOOLS));
		r.shuffle(all);
		for (int64_t i = 0; i < std::min<int64_t>(n, static_cast<int64_t>(all.size())); i++) {
			add(line, all[static_cast<size_t>(i)], 1);
		}
	}

	// The men in-bye: each remains, and with `carried` what it held (§12.5's rolls in their order,
	// at most mine.remains_items_max: never a lamp under One Lamp).
	void remains(int32_t line, int64_t n, Rng &r, bool carried) {
		for (int64_t i = 0; i < n; i++) {
			const int32_t at = static_cast<int32_t>(out_.size());
			add(line, "remains", 1);
			if (!carried) {
				continue;
			}
			int64_t held = 0;
			for (const auto &[name, chance] : p_.remains_chances) {
				if (!r.chance_ppm(std::llround(chance * 1000000.0)) || held >= p_.remains_items_max) {
					continue;
				}
				if (name == "lamp") {
					if (!one_lamp_) {
						lamps(line, 1, r, false, at);
						held++;
					}
					continue;
				}
				Content c;
				c.line = line;
				c.thing = name == "kit" ? "healing_kit" : (name == "tool" ? TOOLS[*r.range(0, 3)] : name);
				c.with = at;
				out_.push_back(c);
				held++;
			}
		}
	}

	// The plan's holdings no line of the kind took (its drawn parts): a line each.
	void rest(int32_t from) {
		for (const Holding &hold : holds_) {
			add(from++, hold.item, hold.count);
		}
		holds_.clear();
	}

	void phone() {
		if (!dead_lines_) {
			add(-1, "phone", std::llround(num("pit_phones", 1)));
		}
	}
};

} // namespace

std::vector<Content> poi_contents(const RunHeader &header, const PoiContentsParams &params, const Poi &poi, bool canary) {
	return Contents(header, params, poi, canary).run();
}

std::vector<uint8_t> canary_home(Coord region) {
	std::vector<uint8_t> out;
	for (int64_t v : {region.x, region.y}) {
		const uint64_t u = static_cast<uint64_t>(v);
		for (int i = 0; i < 8; i++) {
			out.push_back(static_cast<uint8_t>((u >> (8 * i)) & 0xFFu));
		}
	}
	return out;
}

std::optional<Coord> canary_region(const RunHeader &header) {
	const auto it = header.homes.find("canary");
	if (it == header.homes.end() || it->second.size() != 16) {
		return std::nullopt;
	}
	int64_t v[2] = {0, 0};
	for (int k = 0; k < 2; k++) {
		uint64_t u = 0;
		for (int i = 0; i < 8; i++) {
			u |= static_cast<uint64_t>(it->second[static_cast<size_t>(k * 8 + i)]) << (8 * i);
		}
		v[k] = static_cast<int64_t>(u);
	}
	return Coord{v[0], v[1]};
}

} // namespace lb::core::gen

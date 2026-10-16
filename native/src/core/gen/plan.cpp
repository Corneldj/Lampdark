#include "core/gen/plan.h"

#include "core/gen/biomes.h"
#include "core/generated/hash_domains.h"
#include "core/rng/rng.h"
#include "core/vision/det_trig.h"

#include <algorithm>
#include <cmath>
#include <map>

namespace lb::core::gen {

using lb::core::world::Coord;
using lb::core::world::floor_div;
using lb::core::world::region_of_cell;
using lb::core::world::SHAFT_CENTRE_X2;
using lb::core::world::SHAFT_CENTRE_Y2;

PlanParams::PlanParams() {
	footprint.fill({1, 1});
	footprint[static_cast<size_t>(PoiKind::SUBSTATION)] = {2, 1};
	footprint[static_cast<size_t>(PoiKind::HAULAGE_ENGINE_HOUSE)] = {2, 1};
	footprint[static_cast<size_t>(PoiKind::STABLES)] = {2, 1};
	footprint[static_cast<size_t>(PoiKind::LAIR)] = {2, 2};
	rings.fill({1, 3});
	for (PoiKind k : {PoiKind::LAMP_CABIN, PoiKind::FITTERS_SHOP, PoiKind::FUEL_STORE, PoiKind::ELECTRICIANS_CABIN,
				 PoiKind::HAULAGE_ENGINE_HOUSE, PoiKind::STABLES}) {
		rings[static_cast<size_t>(k)] = {1, 2};
	}
	rings[static_cast<size_t>(PoiKind::DEEP_WORKSHOP)] = {2, 3};
	rings[static_cast<size_t>(PoiKind::POWDER_MAGAZINE)] = {2, 3};
	rings[static_cast<size_t>(PoiKind::CAPPED_SHAFT)] = {2, 4};
}

namespace {

// gen.plan's first key: what is being placed (its second, which one; its attempt, the retry).
enum Need : int64_t {
	NEED_SUBSTATION = 1,
	NEED_POWER = 2,
	NEED_HOARD = 3,
	NEED_LAIR = 4,
	NEED_PART = 5,
	NEED_TOOL = 6,
	NEED_FUEL = 7,
	NEED_SPARE = 8,
	NEED_REVOLVER = 9,
	NEED_FUEL_SPLIT = 10,
};

// A band: tiles from the shaft (to the door edge's middle), or rings (at the door cell).
struct Band {
	bool tiles = false;
	int64_t lo = 0;
	int64_t hi = 0;
};

struct Ask {
	PoiKind kind = PoiKind::STORES;
	std::string need;
	int64_t need_id = 0;
	int64_t index = 0;
	Band band;
	std::vector<Holding> holds;
	bool spine = true;
};

// The drawn jobs' parts: the item, the job's full quantity and the kind that guarantees it.
struct Part {
	const char *job;
	const char *item;
	int32_t count;
	PoiKind kind;
};

const Part PARTS[] = {
		{"power", "fuse", 3, PoiKind::ELECTRICIANS_CABIN}, // guaranteed by the substation's 1 and the cabin's 2
		{"magneto", "magneto", 1, PoiKind::FITTERS_SHOP},
		{"drive_belt", "drive_belt", 1, PoiKind::HAULAGE_ENGINE_HOUSE},
		{"brake_shoes", "brake_shoe", 2, PoiKind::STORES},
		{"drum_gear", "drum_gear", 1, PoiKind::DEEP_WORKSHOP},
		{"rope_clamps", "rope_clamp", 4, PoiKind::STORES},
};

int64_t abs64(int64_t v) {
	return v < 0 ? -v : v;
}

class Planner {
public:
	Planner(const RunHeader &header, const PlanParams &params, const PlanWorld &world)
		: h_(header), p_(params), w_(world), list_(std::clamp<int32_t>(header.list_kind, 0, 2)) {}

	RunPlan run() {
		ask_core();
		if (plan_.error.empty()) {
			ask_parts();
		}
		if (plan_.error.empty()) {
			ask_tools();
		}
		if (plan_.error.empty()) {
			ask_fuel();
		}
		if (plan_.error.empty()) {
			ask_spares();
		}
		if (plan_.error.empty()) {
			arm();
		}
		return plan_;
	}

private:
	const RunHeader &h_;
	const PlanParams &p_;
	const PlanWorld &w_;
	int32_t list_;
	RunPlan plan_;
	std::set<Coord> footprints_;
	std::set<Coord> approaches_;
	std::set<Coord> spines_;
	std::map<Coord, int32_t> regions_;
	std::optional<std::pair<int64_t, int64_t>> hoard_;

	std::pair<int64_t, int64_t> kind_rings(PoiKind k) const { return p_.rings[static_cast<size_t>(k)]; }

	// A ring band clipped to a kind's rings (an empty one is a tuning error).
	Band rings_for(PoiKind k, int64_t lo, int64_t hi) const {
		const auto [klo, khi] = kind_rings(k);
		return {false, std::max(lo, klo), std::min(hi, khi)};
	}

	Band tiles_for(const std::pair<int64_t, int64_t> &b) const { return {true, b.first, b.second}; }

	int64_t ring_of(Coord c) const { return ring_of_cell(c, p_.ring_bounds); }

	// The first tile of a ring (ring 0 starts at the shaft).
	int64_t ring_start(int64_t ring) const {
		if (ring <= 0) {
			return 0;
		}
		const size_t i = static_cast<size_t>(ring - 1);
		return i < p_.ring_bounds.size() ? p_.ring_bounds[i] : p_.ring_bounds.back() + 300;
	}

	void ask_core() {
		Ask sub{PoiKind::SUBSTATION, "substation", NEED_SUBSTATION, 0, tiles_for(p_.substation[list_]), {{"fuse", 1}}, true};
		Ask cabin{PoiKind::ELECTRICIANS_CABIN, "power", NEED_POWER, 0, {}, {{"fuse", 2}, {"wire_cutters", 1}}, true};
		const auto parts = p_.parts_rings[list_];
		cabin.band = rings_for(PoiKind::ELECTRICIANS_CABIN, std::max(parts.first, p_.tools_ring), std::min(parts.second, p_.tools_ring));
		Ask hoard{PoiKind::HOARD, "hoard", NEED_HOARD, 0, tiles_for(p_.hoard[list_]), {}, true};
		Ask lair{PoiKind::LAIR, "lair", NEED_LAIR, 0, tiles_for(p_.lair[list_]), {}, true};
		for (const Ask &a : {sub, cabin, hoard}) {
			if (!place(a)) {
				return;
			}
		}
		hoard_ = door_point2(plan_.sites.back());
		place(lair);
	}

	void ask_parts() {
		const auto parts = p_.parts_rings[list_];
		for (size_t i = 1; i < sizeof(PARTS) / sizeof(PARTS[0]); i++) {
			const Part &part = PARTS[i];
			if (!h_.has_job(part.job)) {
				continue;
			}
			const bool gear = std::string(part.job) == "drum_gear";
			const Band band = gear ? rings_for(part.kind, p_.drum_gear_ring, p_.drum_gear_ring)
								   : rings_for(part.kind, parts.first, parts.second);
			if (join(part.kind, band, {{part.item, part.count}})) {
				continue;
			}
			place({part.kind, part.job, NEED_PART, static_cast<int64_t>(i), band, {{part.item, part.count}}, true});
			if (!plan_.error.empty()) {
				return;
			}
		}
	}

	void ask_tools() {
		const Band shop = rings_for(PoiKind::FITTERS_SHOP, p_.tools_ring, p_.tools_ring);
		const std::vector<Holding> toolbox{{"spanner", 1}, {"crowbar", 1}};
		if (!join(PoiKind::FITTERS_SHOP, shop, toolbox) && !place({PoiKind::FITTERS_SHOP, "tools", NEED_TOOL, 0, shop, toolbox, true})) {
			return;
		}
		const Band house = rings_for(PoiKind::HAULAGE_ENGINE_HOUSE, p_.tools_ring, p_.tools_ring);
		if (!join(PoiKind::HAULAGE_ENGINE_HOUSE, house, {{"hammer", 1}})) {
			place({PoiKind::HAULAGE_ENGINE_HOUSE, "tools", NEED_TOOL, 1, house, {{"hammer", 1}}, true});
		}
	}

	// Twice the list's cans in fuel stores of mine.fuel_store_cans_min to _max, within ring 2.
	void ask_fuel() {
		const int64_t keys[2] = {NEED_FUEL_SPLIT, 0};
		Rng r(sub_seed(h_.seed, hash_domain::GEN_PLAN, keys, 2, 0));
		int64_t left = p_.paraffin_factor * h_.cans;
		const Band band = rings_for(PoiKind::FUEL_STORE, 1, p_.paraffin_max_ring);
		int64_t index = 0;
		while (left > 0) {
			std::vector<int64_t> sizes;
			for (int64_t n = p_.fuel_cans_min; n <= std::min(p_.fuel_cans_max, left); n++) {
				if (left - n == 0 || left - n >= p_.fuel_cans_min) {
					sizes.push_back(n);
				}
			}
			const int64_t n = sizes.empty() ? left : sizes[static_cast<size_t>(*r.range(0, static_cast<int64_t>(sizes.size()) - 1))];
			if (!place({PoiKind::FUEL_STORE, "fuel", NEED_FUEL, index, band, {{"paraffin_can", static_cast<int32_t>(n)}}, true})) {
				return;
			}
			left -= n;
			index++;
		}
	}

	// Each drawn part (Power always) rolls mine.part_spare_probability for a spare: a second site
	// of its kind in its band, the job's full quantity, no spine.
	void ask_spares() {
		const auto parts = p_.parts_rings[list_];
		for (size_t i = 0; i < sizeof(PARTS) / sizeof(PARTS[0]); i++) {
			const Part &part = PARTS[i];
			if (i > 0 && !h_.has_job(part.job)) {
				continue;
			}
			const int64_t keys[2] = {NEED_SPARE, static_cast<int64_t>(i)};
			Rng r(sub_seed(h_.seed, hash_domain::GEN_PLAN, keys, 2, 0));
			if (!r.chance_ppm(p_.spare_ppm)) {
				continue;
			}
			const bool gear = std::string(part.job) == "drum_gear";
			const Band band = gear ? rings_for(part.kind, p_.drum_gear_ring, p_.drum_gear_ring)
								   : rings_for(part.kind, parts.first, parts.second);
			if (!place({part.kind, std::string("spare:") + part.job, NEED_SPARE, static_cast<int64_t>(i), band,
						{{part.item, part.count}}, false})) {
				return;
			}
		}
	}

	// The revolver (mine.revolver_probability) and its boxes (mine.ammo_boxes_min to _max), each on
	// its own spine cell in the parts' rings.
	void arm() {
		const auto rings = p_.parts_rings[list_];
		std::vector<Coord> cells;
		for (const Coord &c : spines_) {
			const int64_t ring = ring_of(c);
			if (ring >= rings.first && ring <= rings.second) {
				cells.push_back(c);
			}
		}
		const int64_t keys[2] = {NEED_REVOLVER, 0};
		Rng r(sub_seed(h_.seed, hash_domain::GEN_PLAN, keys, 2, 0));
		plan_.revolver = r.chance_ppm(p_.revolver_ppm);
		const int64_t boxes = *r.range(p_.boxes_min, std::max(p_.boxes_min, p_.boxes_max));
		auto take = [&]() -> std::optional<Coord> {
			if (cells.empty()) {
				return std::nullopt;
			}
			const size_t at = static_cast<size_t>(*r.range(0, static_cast<int64_t>(cells.size()) - 1));
			const Coord c = cells[at];
			cells.erase(cells.begin() + static_cast<std::ptrdiff_t>(at));
			return c;
		};
		if (plan_.revolver) {
			const std::optional<Coord> c = take();
			if (c) {
				plan_.revolver_cell = *c;
			} else {
				plan_.revolver = false;
			}
		}
		for (int64_t b = 0; b < boxes; b++) {
			const std::optional<Coord> c = take();
			if (c) {
				plan_.box_cells.push_back(*c);
			}
		}
	}

	// A planned site of `kind` (with a spine) whose door ring lies in `band` takes `holds`: one
	// point of interest serves every need whose band it lies in.
	bool join(PoiKind kind, const Band &band, const std::vector<Holding> &holds) {
		for (PlannedSite &s : plan_.sites) {
			if (s.kind != kind || !s.spine) {
				continue;
			}
			const int64_t ring = ring_of(s.door);
			if (ring >= band.lo && ring <= band.hi) {
				for (const Holding &hold : holds) {
					s.add(hold.item, hold.count);
				}
				return true;
			}
		}
		return false;
	}

	// Places `ask` on its first fitting try, with its spine; false (and the plan's error) if none.
	bool place(const Ask &ask) {
		if (!ask.band.tiles && ask.band.lo > ask.band.hi) {
			plan_.error = "no rings for " + ask.need;
			return false;
		}
		for (int32_t attempt = 0; attempt <= p_.max_retries; attempt++) {
			const int64_t keys[2] = {ask.need_id, ask.index};
			Rng r(sub_seed(h_.seed, hash_domain::GEN_PLAN, keys, 2, attempt));
			PlannedSite s = candidate(r, ask);
			if (!fits(s, ask)) {
				continue;
			}
			std::optional<Spine> spine;
			if (ask.spine) {
				std::set<Coord> blocked = footprints_;
				blocked.insert(s.cells.begin(), s.cells.end());
				spine = route_spine(h_.seed, static_cast<int32_t>(plan_.sites.size()), s, w_.gates, blocked, p_.ring_bounds, 0);
				if (!spine) {
					continue;
				}
			}
			s.attempt = attempt;
			footprints_.insert(s.cells.begin(), s.cells.end());
			approaches_.insert(s.approach());
			regions_[region_of_cell(s.door)]++;
			if (spine) {
				spines_.insert(spine->cells.begin(), spine->cells.end());
				plan_.spines.push_back(*spine);
			}
			plan_.sites.push_back(s);
			return true;
		}
		plan_.error = "no site for " + ask.need + " in " + std::to_string(p_.max_retries + 1) + " tries";
		return false;
	}

	PlannedSite candidate(Rng &r, const Ask &ask) const {
		PlannedSite s;
		s.kind = ask.kind;
		s.need = ask.need;
		s.holds = ask.holds;
		s.spine = ask.spine;
		const uint32_t bearing = static_cast<uint32_t>(*r.range(0, 65535));
		const int64_t lo = ask.band.tiles ? ask.band.lo : ring_start(ask.band.lo);
		const int64_t hi = ask.band.tiles ? ask.band.hi : ring_start(ask.band.hi + 1) - 1;
		const int64_t d = *r.range(lo, std::max(lo, hi));
		const lb::core::vision::Vec2 u = lb::core::vision::unit_at_facing(bearing);
		const double px = static_cast<double>(SHAFT_CENTRE_X2) / 2.0 + static_cast<double>(d) * u.x;
		const double py = static_cast<double>(SHAFT_CENTRE_Y2) / 2.0 + static_cast<double>(d) * u.y;
		const Coord tile{static_cast<int64_t>(std::floor(px)), static_cast<int64_t>(std::floor(py))};
		s.door = lb::core::world::cell_of(tile);
		const int64_t cx = s.door.x;
		const int64_t cy = s.door.y;
		const bool tie = r.chance_ppm(500000);
		const Edge x_side = cx > 0 ? Edge::WEST : Edge::EAST;
		const Edge y_side = cy > 0 ? Edge::NORTH : Edge::SOUTH;
		if (abs64(cx) > abs64(cy)) {
			s.door_side = x_side;
		} else if (abs64(cy) > abs64(cx)) {
			s.door_side = y_side;
		} else {
			s.door_side = tie ? x_side : y_side;
		}
		auto [fw, fh] = p_.footprint[static_cast<size_t>(ask.kind)];
		if (fw != fh && r.chance_ppm(500000)) {
			std::swap(fw, fh);
		}
		const int64_t sx = cx > 0 ? 1 : (cx < 0 ? -1 : (r.chance_ppm(500000) ? 1 : -1));
		const int64_t sy = cy > 0 ? 1 : (cy < 0 ? -1 : (r.chance_ppm(500000) ? 1 : -1));
		for (int64_t j = 0; j < fh; j++) {
			for (int64_t i = 0; i < fw; i++) {
				s.cells.push_back({s.door.x + i * sx, s.door.y + j * sy});
			}
		}
		return s;
	}

	bool fits(const PlannedSite &s, const Ask &ask) const {
		const int64_t door_ring = ring_of(s.door);
		if (ask.band.tiles) {
			const auto [klo, khi] = kind_rings(ask.kind);
			if (door_ring < klo || door_ring > khi) {
				return false;
			}
			const auto [dx2, dy2] = door_point2(s);
			const int64_t d2 = dx2 * dx2 + dy2 * dy2;
			if (d2 < 4 * ask.band.lo * ask.band.lo || d2 > 4 * ask.band.hi * ask.band.hi) {
				return false;
			}
		} else if (door_ring < ask.band.lo || door_ring > ask.band.hi) {
			return false;
		}
		const Coord region = region_of_cell(s.door);
		for (const Coord &c : s.cells) {
			const int64_t ring = ring_of(c);
			if (ring < 1 || ring >= DEEP_RING || region_of_cell(c) != region) {
				return false;
			}
			if ((w_.is_main_road_cell && w_.is_main_road_cell(c)) || footprints_.count(c) != 0 || approaches_.count(c) != 0 || spines_.count(c) != 0) {
				return false;
			}
		}
		const Coord approach = s.approach();
		if ((approach.x == 0 && approach.y == 0) || footprints_.count(approach) != 0) {
			return false;
		}
		const auto at = regions_.find(region);
		if (at != regions_.end() && at->second >= p_.max_per_region) {
			return false;
		}
		if (ask.need_id == NEED_LAIR && hoard_ && !far_enough(*hoard_, door_point2(s))) {
			return false;
		}
		return true;
	}

	// Whether two bearings from the shaft lie at least mine.lair_min_bearing_from_hoard_deg apart.
	bool far_enough(const std::pair<int64_t, int64_t> &a, const std::pair<int64_t, int64_t> &b) const {
		const double c = lb::core::vision::cos_deg(p_.lair_min_bearing_deg);
		const double dot = static_cast<double>(a.first * b.first + a.second * b.second);
		const double na = static_cast<double>(a.first * a.first + a.second * a.second);
		const double nb = static_cast<double>(b.first * b.first + b.second * b.second);
		// angle >= min  <=>  dot <= c |a| |b|, squared on whichever side keeps both positive.
		if (c >= 0.0) {
			return dot <= 0.0 || dot * dot <= c * c * na * nb;
		}
		return dot < 0.0 && dot * dot >= c * c * na * nb;
	}
};

} // namespace

RunPlan make_plan(const RunHeader &header, const PlanParams &params, const PlanWorld &world) {
	return Planner(header, params, world).run();
}

std::set<Coord> spine_cells(const RunPlan &plan) {
	std::set<Coord> out;
	for (const Spine &s : plan.spines) {
		out.insert(s.cells.begin(), s.cells.end());
	}
	return out;
}

} // namespace lb::core::gen

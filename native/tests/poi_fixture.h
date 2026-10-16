#pragma once
// GEN-09's fixtures: a point-of-interest template for every kind, in GEN-08's footprints (the lair
// 2x2; the substation, haulage engine house and stables 2x1; the rest one cell): a 2-wide door road
// at 10 from the north edge of its north-west cell (so it turns all eight ways) into a room across
// the footprint, and (but for the lair, whose one stub is its door) a 2-wide stub east at 10 on its
// north-east cell. A 2x1 kind has a second template with its door on its short west side, so a
// planned site finds one whichever side its door must face. Each has a poi_slot per contents line
// and a phone where its kind has one. The set holds them with GEN-05's grid templates (every socket
// covered) and fallback; a run joins GEN-08's plan, base camp's gates and the main roads of its seed.

#include "core/gen/poi.h"
#include "layout_fixture.h"
#include "plan_fixture.h"

#include <doctest.h>

#include <map>
#include <memory>

namespace poi_fixture {

using namespace lb::core::gen;
using lb::core::world::Anchor;
using lb::core::world::AnchorType;
using lb::core::world::CELL_TILES;
using lb::core::world::Coord;

// Contents lines per kind (data/world/poi_kinds.json's) and whether it has a phone.
inline int32_t lines_of(PoiKind k) {
	switch (k) {
		case PoiKind::LAMP_CABIN: return 3;
		case PoiKind::FITTERS_SHOP: return 3;
		case PoiKind::STORES: return 6;
		case PoiKind::FUEL_STORE: return 1;
		case PoiKind::ELECTRICIANS_CABIN: return 2;
		case PoiKind::SUBSTATION: return 1;
		case PoiKind::HAULAGE_ENGINE_HOUSE: return 3;
		case PoiKind::DEEP_WORKSHOP: return 2;
		case PoiKind::FIRST_AID_STATION: return 4;
		case PoiKind::POWDER_MAGAZINE: return 1;
		case PoiKind::REFUGE: return 1;
		case PoiKind::STABLES: return 1;
		case PoiKind::CAPPED_SHAFT: return 1;
		case PoiKind::HOARD: return 2;
		case PoiKind::LAIR: return 5;
		default: return 0;
	}
}

inline bool phone_of(PoiKind k) {
	return k == PoiKind::LAMP_CABIN || k == PoiKind::FITTERS_SHOP || k == PoiKind::SUBSTATION || k == PoiKind::FIRST_AID_STATION;
}

inline std::pair<int32_t, int32_t> footprint_of(PoiKind k) {
	return PlanParams().footprint[static_cast<size_t>(k)];
}

// A footprint's tiles as rows of '#' and '.', sliced into cells.
struct Paint {
	int32_t fw = 1;
	int32_t fh = 1;
	std::vector<std::string> grid;
	Paint(int32_t w, int32_t h) : fw(w), fh(h), grid(static_cast<size_t>(h * CELL_TILES), std::string(static_cast<size_t>(w * CELL_TILES), '#')) {}
	void floor(int32_t x, int32_t y, int32_t w, int32_t h) {
		for (int32_t j = 0; j < h; j++) {
			for (int32_t i = 0; i < w; i++) {
				grid[static_cast<size_t>(y + j)][static_cast<size_t>(x + i)] = '.';
			}
		}
	}
	std::vector<std::string> rows_of(Coord c) const {
		std::vector<std::string> out;
		for (int64_t r = 0; r < CELL_TILES; r++) {
			out.push_back(grid[static_cast<size_t>(c.y * CELL_TILES + r)].substr(static_cast<size_t>(c.x * CELL_TILES), CELL_TILES));
		}
		return out;
	}
};

inline Template poi_template(PoiKind kind, bool short_door = false, int32_t door_width = 2) {
	const auto [fw, fh] = footprint_of(kind);
	Paint paint(fw, fh);
	if (short_door) {
		paint.floor(0, 9, 6, door_width); // the door road at 10 from the west edge
	} else {
		paint.floor(9, 0, door_width, 5); // the door road at 10 from the north edge
	}
	const int32_t room_w = fw * CELL_TILES - 12;
	const int32_t room_h = fh == 1 ? 6 : 30;
	paint.floor(6, 5, room_w, room_h);
	const bool lair = kind == PoiKind::LAIR;
	if (!lair) {
		paint.floor(6 + room_w, 9, fw * CELL_TILES - 6 - room_w, 2); // 2 wide at 10, east
	}
	Template t;
	t.id = std::string("fixture_") + poi_kind_name(kind) + (short_door ? "_short" : "") + (door_width != 2 ? "_w" + std::to_string(door_width) : "");
	t.kind = TemplateKind::POI;
	t.biome = "seam";
	t.poi_kind = poi_kind_name(kind);
	t.footprint_w = fw;
	t.footprint_h = fh;
	for (int32_t cy = 0; cy < fh; cy++) {
		for (int32_t cx = 0; cx < fw; cx++) {
			auto cell = mine_fixture::cell_from(Coord{cx, cy}, paint.rows_of(Coord{cx, cy}));
			if (cx == 0 && cy == 0) {
				cell->anchors.push_back(template_fixture::anchor(AnchorType::CHAMBER, 6, 5, 8, 6));
				cell->anchors.push_back(template_fixture::anchor(AnchorType::TIMBER_HOOK, 10, 3));
				for (int32_t i = 0; i < lines_of(kind); i++) {
					cell->anchors.push_back(template_fixture::anchor(AnchorType::POI_SLOT, 7 + i, 7, 1, 1, poi_kind_name(kind)));
				}
				if (phone_of(kind)) {
					cell->anchors.push_back(template_fixture::anchor(AnchorType::WALL_FIXTURE, 5, 6, 1, 1, "phone"));
				}
			}
			lb::core::gen::cut_zones(*cell, template_fixture::room_kind(TemplateKind::POI), false);
			lb::core::gen::cut_collapses(*cell, template_fixture::room_kind(TemplateKind::POI), false);
			t.cells.push_back(*cell);
		}
	}
	t.stubs.push_back(template_fixture::stub(short_door ? Edge::WEST : Edge::NORTH, 10, door_width, 2, true, Coord{0, 0}));
	if (!lair) {
		t.stubs.push_back(template_fixture::stub(Edge::EAST, 10, 2, 2, false, Coord{fw - 1, 0}));
	}
	return t;
}

// GEN-05's set with a point-of-interest template for every kind (`without`: kinds left out).
inline std::shared_ptr<TemplateSet> template_set(const std::set<PoiKind> &without = {}) {
	std::vector<Template> list{layout_fixture::grid("seam_grid_a", 1.0), layout_fixture::grid("seam_grid_b", 3.0),
			template_fixture::make(template_fixture::fallback_spec())};
	for (size_t k = 0; k < static_cast<size_t>(PoiKind::COUNT); k++) {
		const PoiKind kind = static_cast<PoiKind>(k);
		if (without.count(kind) == 0) {
			list.push_back(poi_template(kind));
			if (footprint_of(kind).first != footprint_of(kind).second) {
				list.push_back(poi_template(kind, true));
			}
		}
	}
	auto set = std::make_shared<TemplateSet>();
	REQUIRE(set->load(encode_pack("poi_fixture", list)));
	return set;
}

inline const std::shared_ptr<TemplateSet> &shared_set() {
	static const std::shared_ptr<TemplateSet> set = template_set();
	return set;
}

// A set's shapes, made once (every orientation's zones cut again is the costly part).
inline std::shared_ptr<const PoiShapes> shapes_of(const std::shared_ptr<TemplateSet> &set) {
	static std::map<const TemplateSet *, std::pair<std::shared_ptr<TemplateSet>, std::shared_ptr<const PoiShapes>>> made;
	auto it = made.find(set.get());
	if (it == made.end()) {
		it = made.emplace(set.get(), std::make_pair(set, std::make_shared<const PoiShapes>(*set, std::vector<int32_t>{5, 10, 15}))).first;
	}
	return it->second.second;
}

// A run: GEN-08's plan for a seed and list, base camp's gates open at 10 (3 wide) but its blind
// side, the seed's main roads (no old fall on a spine), and its points of interest.
struct Run {
	RunHeader head;
	std::shared_ptr<TemplateSet> set;
	std::unique_ptr<MainRoads> roads;
	std::set<Coord> spines;
	std::unique_ptr<PointsOfInterest> pois;
	PoiParams params;

	PoiWorld world() const {
		PoiWorld w;
		const MainRoads *r = roads.get();
		w.is_main_road_cell = [r](Coord c) { return r->is_main_road_cell(c); };
		w.is_old_fall = [r](Coord c) { return r->old_fall(c); };
		return w;
	}
};

inline std::unique_ptr<Run> run(uint64_t seed, int32_t list, std::shared_ptr<TemplateSet> set = shared_set(), PoiParams params = PoiParams{}) {
	auto r = std::make_unique<Run>();
	r->head = plan_fixture::planned(seed, list);
	const int blind = plan_fixture::blind_of(seed);
	for (int e = 0; e < 4; e++) {
		Socket s;
		s.open = e != blind;
		s.offset = s.open ? 10 : 0;
		s.width = s.open ? 3 : 0;
		r->head.forced.set(edge_of({0, 0}, static_cast<Edge>(e)), s);
	}
	r->set = std::move(set);
	r->spines = spine_cells(r->head.plan);
	r->roads = std::make_unique<MainRoads>(seed, MainRoadParams{}, plan_fixture::bounds(), std::set<Coord>{});
	const std::set<Coord> *spines = &r->spines;
	r->roads->is_spine = [spines](Coord c) { return spines->count(c) != 0; };
	r->params = std::move(params);
	r->pois = std::make_unique<PointsOfInterest>(r->head, shapes_of(r->set), r->params, r->world());
	return r;
}

// The regions every test sweeps: 8 x 8 around the shaft, cells -20 to 19 (rings 0 to 2 whole, and
// ring 3 in part).
inline std::vector<Coord> regions() {
	std::vector<Coord> out;
	for (int64_t y = -4; y < 4; y++) {
		for (int64_t x = -4; x < 4; x++) {
			out.push_back(Coord{x, y});
		}
	}
	return out;
}

// Derive inputs over a run: points of interest over one seam biome, their sockets, the main roads'
// and the spines', in GEN-05's order.
struct Derive {
	UniformCells base{"seam", {1, 2, 3}};
	std::unique_ptr<MainRoadCells> road_cells;
	std::unique_ptr<PoiCells> cells;
	std::unique_ptr<PoiSockets> poi_sockets;
	std::unique_ptr<MainRoadSockets> road_sockets;
	std::unique_ptr<SpineSockets> spine_sockets;
	DeriveInputs in;
};

inline std::unique_ptr<Derive> derive_inputs(const Run &r) {
	auto d = std::make_unique<Derive>();
	d->road_cells = std::make_unique<MainRoadCells>(*r.roads, d->base);
	d->cells = std::make_unique<PoiCells>(*d->road_cells, *r.pois);
	const MainRoads *roads = r.roads.get();
	d->poi_sockets = std::make_unique<PoiSockets>(*r.pois, *d->cells, r.head.sockets, r.head.seed,
			[roads](Coord c) { return roads->is_main_road_cell(c); });
	d->road_sockets = std::make_unique<MainRoadSockets>(*r.roads, *d->cells, r.head.sockets);
	d->spine_sockets = std::make_unique<SpineSockets>(r.head.seed, r.head.plan, *d->cells, r.head.sockets);
	d->in.header = &r.head;
	d->in.templates = r.set.get();
	d->in.cells = d->cells.get();
	d->in.providers = {d->poi_sockets.get(), d->road_sockets.get(), d->spine_sockets.get()};
	return d;
}

} // namespace poi_fixture

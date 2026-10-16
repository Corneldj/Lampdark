#pragma once
// GEN-09: points of interest (Gameplay §12.4; §12.2, §12.3, §12.5, §8.1, §8.4, §13.6, §4.4, §A.11).
// Each 5x5-cell region (FND-07's region_of_cell) holds one or two, its planned ones (GEN-08)
// included: a lamp cabin and a first-aid station each by their own rate per region
// (mine.lamp_cabin_regions_per, mine.first_aid_regions_per), the rest drawn by ring weights
// (mine.poi_kind_weights_ring<n>) at a hashed door cell; the substation, hoard and lair come only
// from the plan. Each takes a template of its kind in one of its orientations (the turns and
// mirrors that keep its doors on socket offsets), its footprint wholly in the region, in rings 1
// and over and in its kind's rings at its door cell, clear of base camp, main roads, the cells
// beside an old fall, spines, other points of interest and their doors' approaches; a drawn one's
// door opens onto a cell of its own region that is no main road. A footprint that will not fit
// retries from the next sub-seed of gen.poi_region (mine.poi_fit_tries), then the region holds
// fewer. A planned site takes a template and orientation whose door stub lies on its door cell and
// planned side, facing its spine's last cell; where none fits it stays a planned site of biome
// cells whose door is its spine's (until GEN-16's templates).
//
// The layout is pure and cached per region. It backs poi_at, the forced sockets of GEN-05's rule 2
// (door stubs open; other stubs hashed like any edge, shut toward a main road; edges without a
// stub shut; an edge inside one point of interest no socket), the cell classifier (its template's
// biome, the lair's always Old Workings) and poi_contents, the pure list of what each holds for
// GEN-10 to spawn. Server-only: nothing marks a point of interest, and none reaches a client but as
// seen tiles and entities (NET-04).

#include "core/gen/plan.h"
#include "core/rng/rng.h"

#include <array>
#include <functional>
#include <list>
#include <map>
#include <memory>
#include <mutex>
#include <set>

namespace lb::core::gen {

// A point of interest's identity: its region and its place there (planned ones first, in plan
// order, then the drawn ones), stable across evictions and resumes, so GEN-13 can key its contents.
struct PoiId {
	lb::core::world::Coord region;
	int32_t index = 0;
	bool operator==(const PoiId &o) const { return region == o.region && index == o.index; }
	bool operator<(const PoiId &o) const { return std::tie(region.x, region.y, index) < std::tie(o.region.x, o.region.y, o.index); }
};

// A tile rectangle, footprint-global or world.
struct TileRect {
	int64_t x = 0;
	int64_t y = 0;
	int32_t w = 1;
	int32_t h = 1;
};

// A template of a point-of-interest kind in one orientation whose door stubs lie on socket offsets
// (a 2-wide door turns all eight ways; a 1- or 3-wide one only the four that keep its edge's
// direction). Its other stubs that turn off a socket offset are never opened.
struct PoiShape {
	const Template *base = nullptr;
	int32_t orientation = 0;
	Template oriented;
	// The base template's poi_slot anchors in its order (its cells in order, each cell's anchors in
	// order): the contents lines' slots, as footprint-global rectangles of the oriented template.
	std::vector<TileRect> slots;
};

struct Poi {
	PoiId id;
	PoiKind kind = PoiKind::STORES;
	int32_t planned = -1; // the plan's site index; -1 for one the region drew
	const PoiShape *shape = nullptr; // nullptr: a planned site no template fits
	lb::core::world::Coord origin; // the footprint's north-west cell
	int32_t w = 1;
	int32_t h = 1;
	lb::core::world::Coord door;
	Edge door_side = Edge::NORTH;
	std::string biome; // its template's (the lair's Old Workings); "" without a template
	int32_t attempt = 0;

	bool contains(lb::core::world::Coord c) const {
		return c.x >= origin.x && c.y >= origin.y && c.x < origin.x + w && c.y < origin.y + h;
	}
	lb::core::world::Coord approach() const { return neighbour(door, door_side); }
	std::vector<lb::core::world::Coord> cells() const;
	// Its contents lines' slots in world tiles (none without a template).
	std::vector<TileRect> slots() const;
};

struct RegionLayout {
	lb::core::world::Coord region;
	int32_t wanted = 0; // 1 or 2 by hash, raised for its lamp cabin and first-aid station, never below its planned ones
	std::vector<Poi> pois;
};

// The numbers the layout reads (mine.* tuning); the defaults are the design's starting values.
struct PoiParams {
	int32_t per_region_min = 1; // mine.poi_per_region_min
	int32_t per_region_max = 2; // mine.poi_per_region_max
	uint32_t two_ppm = 500000; // mine.poi_two_per_region_probability
	uint32_t lamp_cabin_ppm = 333333; // 1 / mine.lamp_cabin_regions_per
	uint32_t first_aid_ppm = 333333; // 1 / mine.first_aid_regions_per
	int32_t fit_tries = 20; // mine.poi_fit_tries
	int64_t min_ring = 1; // mine.poi_min_ring
	std::vector<int64_t> ring_bounds{80, 200, 400, 700};
	// By kind: the rings it lies in, judged at its door cell (mine.poi_ring_min / _max).
	std::array<std::pair<int64_t, int64_t>, static_cast<size_t>(PoiKind::COUNT)> rings;
	// The drawn kinds' weights by ring (mine.poi_kind_weights_ring<n>; index = ring, the last table
	// serving every ring past it). Lamp cabins and first-aid stations come by their own rates, and
	// the plan's own kinds are never drawn, whatever these say.
	std::vector<std::array<double, static_cast<size_t>(PoiKind::COUNT)>> weights;
	std::string lair_biome = "old_workings";
	// mine.canary_max_per_run: 0 for none; the one canary region makes one at most whatever it says.
	int32_t canary_max = 1;

	PoiParams();
};

// What the layout reads of the world besides the plan: GEN-07's main roads and their old falls.
struct PoiWorld {
	std::function<bool(lb::core::world::Coord)> is_main_road_cell;
	std::function<bool(lb::core::world::Coord)> is_old_fall;
};

// Every point-of-interest template of a set in each orientation that keeps its doors on socket
// offsets, by kind. Templates of no known kind are left out.
class PoiShapes {
public:
	PoiShapes(const TemplateSet &set, const std::vector<int32_t> &offsets);
	const std::vector<const PoiShape *> &of(PoiKind kind) const { return by_kind_[static_cast<size_t>(kind)]; }

private:
	std::vector<std::unique_ptr<PoiShape>> shapes_;
	std::array<std::vector<const PoiShape *>, static_cast<size_t>(PoiKind::COUNT)> by_kind_;
};

// A cached region layout and one of its points of interest.
struct PoiRef {
	std::shared_ptr<const RegionLayout> layout;
	const Poi *poi = nullptr;
	explicit operator bool() const { return poi != nullptr; }
	const Poi *operator->() const { return poi; }
	const Poi &operator*() const { return *poi; }
};

// The run's points of interest: region layouts, pure and LRU-cached (thread-safe, for GEN-11's
// workers). `header` and `templates` must outlive it.
class PointsOfInterest {
public:
	PointsOfInterest(const RunHeader &header, const TemplateSet &templates, PoiParams params, PoiWorld world,
			size_t capacity = 256);
	// The same over shapes already made from the run's template set and socket offsets.
	PointsOfInterest(const RunHeader &header, std::shared_ptr<const PoiShapes> shapes, PoiParams params, PoiWorld world,
			size_t capacity = 256);

	std::shared_ptr<const RegionLayout> region(lb::core::world::Coord region) const;
	// The point of interest a cell lies in.
	PoiRef at(lb::core::world::Coord cell) const;
	PoiRef find(const PoiId &id) const;
	// The pure layout, bypassing the cache.
	RegionLayout derive(lb::core::world::Coord region) const;
	// Whether `id` is the run's canary station: the first first-aid station in the canary region
	// GEN-10 names in the header's "canary" home (none without one).
	bool is_canary(const PoiId &id) const;

	const PoiShapes &shapes() const { return *shapes_; }
	const PoiParams &params() const { return params_; }
	const RunHeader &header() const { return header_; }
	void set_caching(bool on);

private:
	const RunHeader &header_;
	std::shared_ptr<const PoiShapes> shapes_;
	PoiParams params_;
	PoiWorld world_;
	std::set<lb::core::world::Coord> spine_cells_;
	std::set<lb::core::world::Coord> planned_cells_;
	std::set<lb::core::world::Coord> planned_approaches_;
	std::map<lb::core::world::Coord, std::vector<int32_t>> planned_by_region_;

	mutable std::mutex mutex_;
	size_t capacity_;
	bool caching_ = true;
	mutable std::list<std::pair<lb::core::world::Coord, std::shared_ptr<const RegionLayout>>> order_;
	mutable std::map<lb::core::world::Coord, decltype(order_)::iterator> cached_;

	// A region's cells: their rings, main roads, and what the region's own placements cannot change.
	struct Cells;
	int64_t ring_of(lb::core::world::Coord c) const;
	bool fixed_block(lb::core::world::Coord c) const;
	Poi planned_poi(int32_t site, lb::core::world::Coord region, int32_t index) const;
	std::optional<Poi> drawn_poi(Rng &r, const Cells &cells, std::optional<PoiKind> special,
			const std::set<lb::core::world::Coord> &taken, const std::set<lb::core::world::Coord> &approaches) const;
};

// GEN-05's rule 2, after base camp's own: a templated point of interest's outer edges. Its door
// stub's edge opens at the stub's offset (a width both cells allow, at most the stub's); another
// stub's edge rolls open like any edge (shut toward a main road); an edge without a stub is shut;
// an edge between two of its own cells is no socket (shut: its own floor joins them). Between two
// points of interest an edge opens only where both have a stub at one offset. A planned site
// without a template has no say: its door is its spine's.
class PoiSockets : public SocketProvider {
public:
	PoiSockets(const PointsOfInterest &pois, const CellClassifier &cells, SocketParams params, uint64_t seed,
			std::function<bool(lb::core::world::Coord)> is_main_road_cell)
		: pois_(pois), cells_(cells), params_(std::move(params)), seed_(seed), is_main_road_cell_(std::move(is_main_road_cell)) {}
	std::optional<Socket> query(const EdgeKey &edge) const override;

private:
	const PointsOfInterest &pois_;
	const CellClassifier &cells_;
	SocketParams params_;
	uint64_t seed_;
	std::function<bool(lb::core::world::Coord)> is_main_road_cell_;
};

// Points of interest over another classifier: a templated one's cells are kind poi, its biome and
// that biome's widths (`widths_for`; the base's without it), its oriented template and the cell's
// place in it.
class PoiCells : public CellClassifier {
public:
	PoiCells(const CellClassifier &base, const PointsOfInterest &pois,
			std::function<std::vector<int32_t>(const std::string &)> widths_for = nullptr)
		: base_(base), pois_(pois), widths_for_(std::move(widths_for)) {}
	CellClass classify(lb::core::world::Coord cell) const override;

private:
	const CellClassifier &base_;
	const PointsOfInterest &pois_;
	std::function<std::vector<int32_t>(const std::string &)> widths_for_;
};

// The numbers the contents read; the defaults are the design's starting values.
struct PoiContentsParams {
	// mine.poi_contents_<kind>: each kind's numbers by name ("gauze_lamps_min", "paraffin_cans");
	// a missing one takes the design's value.
	std::array<std::map<std::string, double>, static_cast<size_t>(PoiKind::COUNT)> tables;
	int64_t fuel_cans_min = 2; // mine.fuel_store_cans_min (a drawn fuel store; planned ones hold their plan's)
	int64_t fuel_cans_max = 4;
	double found_oil_min = 0.25; // lamp.found_oil_range
	double found_oil_max = 0.75;
	int64_t found_notches_min = 0; // lamp.found_notches_range
	int64_t found_notches_max = 3;
	// mine.remains_item_chances in their order (lamp, flare, kit, tool, note), and at most
	// mine.remains_items_max of them.
	std::vector<std::pair<std::string, double>> remains_chances{{"lamp", 0.25}, {"flare", 0.10}, {"kit", 0.05}, {"tool", 0.10}, {"note", 0.10}};
	int64_t remains_items_max = 2;
	double dry_stores_factor = 0.5; // hazards.dry_stores_factor
};

// One thing a point of interest holds.
struct Content {
	int32_t line = 0; // its contents line, and so its slot (the template's poi_slots in order); -1: the phone's wall fixture
	std::string thing; // an item kind ("gauze_lamp", "paraffin_can"...) or "phone", "remains", "coats", "lore", "brass_checks"
	int32_t oil_milli = -1; // a found lamp's oil or a can's paraffin, thousandths of full; -1 for full or none
	int32_t notches = -1; // a found lamp's notches
	int32_t with = -1; // carried by the remains at this index of the list
};

// What `poi` holds (Gameplay §12.4), its lines in order: its kind's contents table, the plan's
// quantities over it where the plan fixed them (its fuel, parts and tools), the plan's parts on
// lines of their own, and the run's modifiers: Dry Stores (the draw's "dry_stores") halves fuel
// stores' paraffin and lamp cabins' lamp oil, One Lamp (hard variant "one_lamp") takes every lamp,
// Dead Lines ("dead_lines") every phone. Found lamps are unlit with 25-75% oil and 0-3 notches.
// Hashed on gen.poi_contents by the point of interest and the line. `canary`: it holds the run's
// canary. Pure.
std::vector<Content> poi_contents(const RunHeader &header, const PoiContentsParams &params, const Poi &poi, bool canary);

// The header's "canary" home (GEN-10): the canary region's x and y as two little-endian i64.
std::vector<uint8_t> canary_home(lb::core::world::Coord region);
std::optional<lb::core::world::Coord> canary_region(const RunHeader &header);

} // namespace lb::core::gen

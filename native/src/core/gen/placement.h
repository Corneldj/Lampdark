#pragma once
// GEN-10: placement (Gameplay §12.5, §12.3, §12.7, §8.1, §7.2, §6.6, §4.4, §10.10, §13.6). What a
// cell holds as it generates is a pure function of the run header (seed, plan, homes, staging,
// hard variant, draw) and the pure layouts of the cell and its eight neighbours: GEN-09's contents,
// the plan's revolver and boxes and the landmark; phones; air doors; collapse arming; gas; traps;
// the men in-bye's remains; loose finds, coat heaps and Tapper-rich rock; then the exclusions.
// Each pass hashes its own domain (gen.place.<pass>) by the cell and the anchor, so nothing reads
// loaded state, time, threads or call order: a cell places the same however the mine is explored,
// after eviction and after a resume. Cross-cell rules (collapse spacing, the 7 tiles from phones
// and doors) see the neighbours' candidates from their pure layouts, and a candidate stands only
// if no conflicting one near it has a higher priority hash. The run-start homes pass (the roosts,
// the start roost, the near-gate phones, the electric lamp's cell, the canary region) is written
// into the header's homes. Server-only: no anchor or placement reaches a client except as the
// entities spawned from it, when seen (NET-08).

#include "core/gen/derive.h"
#include "core/gen/poi.h"

#include <functional>
#include <map>
#include <optional>
#include <string>
#include <vector>

namespace lb::core::gen {

// What a placement is. ITEM's `thing` is an item kind's name (MNR-04's ItemKinds, lowercase:
// "gauze_lamp", "paraffin_can", "revolver"...); PROP's is a prop GEN-09 names ("lore",
// "brass_checks"); LANDMARK's its kind. The areas (AIR_DOOR, FIREDAMP, BLACKDAMP, SUMP_MUD,
// RICH_ROCK) cover their tile rectangle; COLLAPSE names the alternate armed.
enum class PlacedKind : uint8_t {
	ITEM = 0,
	REMAINS,
	PHONE,
	AIR_DOOR,
	COLLAPSE,
	FIREDAMP,
	BLACKDAMP,
	MAN_TRAP,
	STAPLE_PIT,
	SUMP_MUD,
	COAT_HEAP,
	RICH_ROCK,
	LANDMARK,
	PROP,
	COUNT
};

const char *placed_kind_name(PlacedKind kind);

struct Placement {
	PlacedKind kind = PlacedKind::ITEM;
	std::string thing;
	// The pass that placed it: poi, plan, landmark, phone, home, door, collapse, gas, trap, remains,
	// loose, heap, rich_rock.
	std::string source;
	int32_t anchor = -1; // its anchor's index in the cell's layout; -1 for none
	lb::core::world::Coord tile; // world tile (an area's north-west tile)
	int32_t w = 1;
	int32_t h = 1;
	int32_t count = 1;
	int32_t oil_milli = -1; // a found lamp's oil or a can's paraffin in thousandths of full; -1: full or none
	int32_t notches = -1; // a found lamp's flint notches
	int32_t variant = -1; // LANDMARK: its entry in the run's palette
	uint32_t collapse = 0; // COLLAPSE: the alternate's id
	int32_t with = -1; // an item carried by the remains at this index of the list
	uint64_t id = 0; // GEN-13's key: a hash of the cell, the anchor, the kind and its ordinal there

	bool covers(lb::core::world::Coord t) const { return t.x >= tile.x && t.y >= tile.y && t.x < tile.x + w && t.y < tile.y + h; }
};

// What placement reads of a cell besides its layout.
struct CellFacts {
	bool base_camp = false;
	int64_t ring = 0; // the cell centre's ring (depth.ring_start_tiles)
	std::string biome; // GEN-06's biome; a main road's is the biome it dresses
	bool main_road = false;
	bool spine = false; // GEN-08: no gas, no armed collapse
};

// The pure world placement reads: the header, each cell's layout and class, GEN-09's points of
// interest. Implementations must answer the same for the same cell however they are called.
class PlacementWorld {
public:
	virtual ~PlacementWorld() = default;
	virtual const RunHeader &header() const = 0;
	// The cell's layout (reroll 0 until GEN-12's validator names another); nullopt for none.
	virtual std::optional<Layout> layout(lb::core::world::Coord cell) const = 0;
	virtual CellFacts facts(lb::core::world::Coord cell) const = 0;
	virtual const std::vector<int64_t> &ring_bounds() const = 0;
	// GEN-09: the point of interest a cell lies in (none without them), what it holds, a region.
	virtual PoiRef poi_at(lb::core::world::Coord) const { return {}; }
	virtual std::vector<Content> contents(const Poi &) const { return {}; }
	virtual std::shared_ptr<const RegionLayout> region(lb::core::world::Coord) const { return nullptr; }
};

// The numbers placement reads (mine.*, traps.*, lamp.*, revolver.* tuning; the staged-run values
// from modes.staging_*); the defaults are the design's starting values. Chances are ppm.
struct PlacementParams {
	// The men in-bye's remains and what they carried (in table order, the first two kept).
	int64_t remains_ppm = 166667; // 1 / mine.remains_cells_per
	int64_t remains_ring_min = 1; // mine.remains_rings
	int64_t remains_ring_max = 3;
	std::vector<std::pair<std::string, int64_t>> remains_items{{"lamp", 250000}, {"flare", 100000}, {"kit", 50000}, {"tool", 100000}, {"note", 100000}};
	int64_t remains_items_max = 2; // mine.remains_items_max
	int64_t found_oil_min_milli = 250; // lamp.found_oil_range
	int64_t found_oil_max_milli = 750;
	int64_t found_notches_min = 0; // lamp.found_notches_range
	int64_t found_notches_max = 3;
	// Loose finds.
	int64_t paraffin_ppm = 125000; // 1 / mine.paraffin_single_cells_per
	int64_t paraffin_ring_min = 1;
	int64_t paraffin_ring_max = 2;
	int64_t electric_lamp_ppm = 500000; // mine.electric_lamp_probability
	int64_t electric_lamp_max = 1; // mine.electric_lamp_per_run's top
	int64_t electric_lamp_min_ring = 2; // mine.electric_lamp_min_ring
	int64_t revolver_rounds = 6; // revolver.cylinder_rounds
	int64_t box_rounds = 6; // revolver.box_rounds
	// Phones (none under Dead Lines).
	int64_t phone_ring12_ppm = 166667; // 1 / mine.phone_cells_per_ring12
	int64_t phone_beyond_ppm = 100000; // 1 / mine.phone_cells_per_beyond
	int64_t phones_near_gates = 2; // mine.phones_near_gates
	int64_t phones_near_gates_min_path = 11; // past the arches (Proposed)
	int64_t phones_near_gates_max_path = 40; // mine.phones_near_gates_path_tiles
	// Air doors: on side passages off a main road.
	int64_t air_door_ppm = 333000; // mine.air_door_side_passage_probability
	// Collapse points: one alternate at most a cell.
	int64_t collapse_ppm = 500000; // 1 / mine.collapse_cells_per
	int64_t collapse_min_from_basecamp = 20; // mine.collapse_min_from_basecamp_tiles
	int64_t collapse_min_spacing = 12; // mine.collapse_min_spacing_tiles
	int64_t collapse_min_from_sites = 7; // mine.collapse_min_path_from_sites_tiles
	// Gas.
	int64_t firedamp_ring2_ppm = 250000; // 1 / mine.firedamp_cells_per_ring2
	int64_t firedamp_beyond_ppm = 500000; // 1 / mine.firedamp_cells_per_beyond
	int64_t firedamp_black_seam_ppm = 1000000; // 1 / mine.firedamp_cells_per_black_seam
	int64_t blackdamp_ppm = 333333; // 1 / mine.blackdamp_old_workings_cells_per
	// Traps (HAZ-01's lair approaches come through lair_traps).
	int64_t man_trap_ppm = 100000; // 1 / traps.man_trap_cells_per
	int64_t man_trap_min_ring = 2; // traps.man_trap_min_ring
	int64_t staple_pit_ppm = 166667; // 1 / mine.staple_pit_old_workings_cells_per
	int64_t staple_pit_min_ring = 2; // mine.staple_pit_min_ring
	int64_t sump_mud_ppm = 200000; // 1 / mine.sump_mud_low_road_cells_per
	int64_t sump_mud_min_ring = 1; // mine.sump_mud_min_ring
	// New Brigade staging (DIR-06's tables by stage, the header's staging "1"-"4"; "" unstaged):
	// no trap (sump mud included) below this ring, and the roosts at least this far from the shaft
	// (modes.staging_no_man_traps_rings_0_1, modes.staging_roost_min_tiles). A value set here
	// beats the table (tests).
	std::vector<int64_t> staged_traps_min_ring{2, 0, 0, 0};
	std::vector<int64_t> staged_roost_min_from_shaft{100, 0, 0, 0};
	int64_t traps_min_ring = 0;
	int64_t roost_min_from_shaft = 0;
	// The Moth's roosts and coat heaps (straight-line distances, Proposed).
	int64_t roosts_min = 2; // mine.roosts_min
	int64_t roosts_max = 4; // mine.roosts_max
	int64_t roost_max_from_hoard = 60; // mine.roost_max_from_hoard_tiles
	int64_t coat_heap_near_hoard = 80; // mine.coat_heap_near_hoard_tiles
	int64_t coat_heap_near_ppm = 500000; // mine.coat_heap_chamber_probability_near
	int64_t coat_heap_far_ppm = 50000; // mine.coat_heap_chamber_probability_far
	int64_t coat_heaps_min = 3; // mine.coat_heaps_per_chamber_min
	int64_t coat_heaps_max = 6; // mine.coat_heaps_per_chamber_max
	// Tapper-rich rock: masses a 5x5-cell region, in rock this thick.
	int64_t rich_rock_per_region = 2; // mine.rich_rock_per_region
	int64_t rich_rock_min_thickness = 4;
	// Landmarks: a 5x5 lattice of palette entries, never one twice within this many cells.
	int64_t landmark_no_repeat_cells = 2; // mine.landmark_no_repeat_cells
	int64_t landmark_palette = 25; // mine.landmark_palette_min
	// GEN-09's canary: mine.canary_max_per_run (0: no canary region named).
	int64_t canary_max = 1;
	// HAZ-01: the man-traps on the lair's approaches, for a cell (none until HAZ-01 registers it).
	std::function<std::vector<Placement>(const PlacementWorld &, lb::core::world::Coord)> lair_traps;
};

// The run-start homes (written to the header's homes, so a resume keeps them): the Moth's roosts
// (chamber rectangles in world tiles) and its start (an index into them, -1 for the hoard), the
// near-gate phones' tiles, the electric lamp's cell, and the canary region (GEN-09's format).
struct TileBox {
	int64_t x = 0;
	int64_t y = 0;
	int32_t w = 1;
	int32_t h = 1;
	bool operator==(const TileBox &o) const { return x == o.x && y == o.y && w == o.w && h == o.h; }
};

struct Homes {
	std::vector<TileBox> roosts;
	int32_t start_roost = -1;
	// The hoard's centre (world tiles), when the plan has one.
	std::optional<lb::core::world::Coord> hoard;
	std::vector<lb::core::world::Coord> gate_phones;
	std::optional<lb::core::world::Coord> electric_lamp; // its cell
	std::optional<lb::core::world::Coord> canary; // its region
	// Fewer roosts than mine.roosts_min found candidates (reported, never invented).
	bool roosts_short = false;
};

// The homes pass (after the plan, before any cell commits): pure in the header's seed and plan.
Homes make_homes(const PlacementWorld &world, const PlacementParams &params);
// Into the header's homes ("roosts", "start_roost", "gate_phones", "electric_lamp", "canary") and back.
void write_homes(const Homes &homes, RunHeader &header);
Homes read_homes(const RunHeader &header);

// A staged value for the header's stage: `plain` when set, else the table's entry ("1" is the
// first), 0 for an unstaged run.
int64_t staged_value(const RunHeader &header, const std::vector<int64_t> &table, int64_t plain);

// Everything placed in `cell`, in pass order (none for base camp or a cell with no layout).
std::vector<Placement> place_cell(const PlacementWorld &world, const PlacementParams &params, lb::core::world::Coord cell);
// A digest of a cell's placements (GEN-05's order tests).
uint64_t placement_digest(const std::vector<Placement> &list);

// The landmark palette entry of a cell: a lattice colouring of period 2n + 1 permuted per run, so
// no two cells within n (Chebyshev) share one, and entries recur farther off. The palette holds at
// least (2n + 1)^2 entries.
int32_t landmark_variant(uint64_t seed, lb::core::world::Coord cell, int64_t palette, int64_t no_repeat = 2);
// The cells of a 5x5-cell region that hold its Tapper-rich rock masses (the region's hash picks).
std::vector<lb::core::world::Coord> rich_rock_cells(uint64_t seed, lb::core::world::Coord region, int64_t per_region);
// A region's Tapper-rich rock masses: each picked cell's thickest rich_rock anchor (CRT-08).
std::vector<TileBox> rich_rock_masses(const PlacementWorld &world, const PlacementParams &params, lb::core::world::Coord region);

// Counts of what a set of cells holds, by kind and thing ("item:gauze_lamp", "remains",
// "phone"...): GEN-14's finds against the typical-run targets.
std::map<std::string, int64_t> find_counts(const std::vector<std::vector<Placement>> &cells);

} // namespace lb::core::gen

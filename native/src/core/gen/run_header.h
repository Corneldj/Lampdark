#pragma once
// GEN-08: the run header (Gameplay §12.3, §12.6; GDD §15.9). Everything that fixes a run's mine
// beyond its coordinates: the seed, the repair list (LFT-03), the draw (HAZ-07), staging (DIR-06),
// the hard variant (MOD-03), the generator, template and data versions, and the plan (its sites,
// spines, the revolver and its boxes) with the homes GEN-10 and HAZ-01 add. It serialises
// canonically (little-endian, fixed widths, maps in key order), so a save (NET-09) keeps it byte
// for byte and the same inputs give the same bytes on every platform. GEN-05's socket numbers,
// reroll limit and base camp's forced sockets ride beside it, set from tuning, and are not
// serialised. Server-only: no part of it reaches a client.

#include "core/gen/sockets.h"
#include "core/rng/hash.h"
#include "core/world/coords.h"

#include <map>
#include <optional>
#include <string>
#include <vector>

namespace lb::core::gen {

// The generator's version: bump it whenever the plan's or a layout's derivation changes, so a
// resumed save knows which generator made its mine.
constexpr uint32_t GENERATOR_VERSION = 1;

// Point-of-interest kinds (Gameplay §12.4), in the tuning tables' names (poi_kind_name).
enum class PoiKind : uint8_t {
	LAMP_CABIN = 0,
	FITTERS_SHOP,
	STORES,
	FUEL_STORE,
	ELECTRICIANS_CABIN,
	SUBSTATION,
	HAULAGE_ENGINE_HOUSE,
	DEEP_WORKSHOP,
	FIRST_AID_STATION,
	POWDER_MAGAZINE,
	REFUGE,
	STABLES,
	CAPPED_SHAFT,
	HOARD,
	LAIR,
	COUNT
};

const char *poi_kind_name(PoiKind kind);
std::optional<PoiKind> poi_kind_from(const std::string &name);

// What a planned site holds by plan (its kind's other contents are GEN-09's): an item kind's name,
// as RepairJobs' plates name them ("fuse", "magneto", "paraffin_can"), and how many.
struct Holding {
	std::string item;
	int32_t count = 0;
	bool operator==(const Holding &o) const { return item == o.item && count == o.count; }
};

// A planned point of interest: its kind, the need it was planned for ("power", "magneto",
// "tools", "fuel", "hoard", "spare:magneto"...), its footprint (the door cell first), the door's
// edge (facing its spine), what it holds, whether a spine runs to it and the attempt (sub-seed)
// that placed it.
struct PlannedSite {
	PoiKind kind = PoiKind::STORES;
	std::string need;
	lb::core::world::Coord door;
	Edge door_side = Edge::NORTH;
	std::vector<lb::core::world::Coord> cells;
	std::vector<Holding> holds;
	bool spine = true;
	int32_t attempt = 0;

	// The cell outside the door, where its spine ends.
	lb::core::world::Coord approach() const { return neighbour(door, door_side); }
	int32_t count_of(const std::string &item) const;
	void add(const std::string &item, int32_t count);
};

// A spine: from the cell beyond its gate, cell by cell, to the cell outside its site's door.
struct Spine {
	int32_t site = -1;
	Edge gate = Edge::NORTH;
	std::vector<lb::core::world::Coord> cells;
	int32_t replan = 0;
};

struct RunPlan {
	std::vector<PlannedSite> sites;
	std::vector<Spine> spines;
	bool revolver = false;
	lb::core::world::Coord revolver_cell;
	std::vector<lb::core::world::Coord> box_cells;
	// Empty unless planning failed (a need's retries ran out).
	std::string error;
};

struct RunHeader {
	uint64_t seed = 0;
	// GEN-05's numbers, from tuning: not serialised.
	SocketParams sockets;
	int32_t reroll_limit = 20; // mine.validator_max_rerolls
	FixedSockets forced;
	// The serialised header.
	int32_t list_kind = 1; // LFT-03's RepairList.Kind: 0 Short, 1 Standard, 2 Full
	std::vector<std::string> jobs; // the list's jobs, in the Company's order
	int32_t cans = 4;
	bool solo = false;
	std::vector<std::string> draw; // HAZ-07's run conditions
	std::string staging; // DIR-06
	std::string hard_variant; // MOD-03
	uint32_t generator_version = GENERATOR_VERSION;
	uint64_t hash_version = HASH_VERSION;
	std::string template_version; // the template pack's set version (GEN-04)
	std::string data_version; // the data bundle's tuning hash (FND-05)
	RunPlan plan;
	// GEN-10's and HAZ-01's sections, by name.
	std::map<std::string, std::vector<uint8_t>> homes;

	bool has_job(const std::string &job) const;
};

std::vector<uint8_t> serialise_header(const RunHeader &h);
// The serialised part of a header from its bytes; nullopt for bytes that are not exactly one
// header of this format.
std::optional<RunHeader> parse_header(const std::vector<uint8_t> &bytes);
// A digest of the serialised header (golden tests: the same on every platform).
uint64_t header_digest(const RunHeader &h);
uint64_t bytes_digest(const std::vector<uint8_t> &bytes);

} // namespace lb::core::gen

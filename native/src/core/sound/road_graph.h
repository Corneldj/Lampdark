#pragma once
// The Road Graph (SND-01, Gameplay §6.1, GDD §15.4): how sound moves through the mine.
// Zones are joined by portals; each zone keeps a distance field per adjacent portal, so an
// event costs a BFS in its own zone plus a small Dijkstra over portals. Cells stitch on load
// through implicit edge links. Server-only; tick thread only, except build work GEN-11 may do.
//
// Costs: 1 np per tile of air (octile, never cutting a wall corner). Portal tiles are free;
// crossing a closed portal costs closed_cost np in AIR mode and is impossible in VOICE mode.
// Edge links (between cells) cost 1 tile. Deliveries carry no entity ID; true_source is
// server-only and never goes into a client record (SND-03).

#include "core/sound/rock_line.h"
#include "core/sound/zone_block.h"
#include "core/world/mine_map.h"

#include <array>
#include <map>
#include <optional>
#include <tuple>
#include <vector>

namespace lb::core::sound {

enum class Mode : uint8_t { AIR, VOICE };

struct GraphParams {
	double closed_cost = 12.0;      // noise.closed_portal_cost
	double jitter_per_tile = 0.25;  // noise.jitter_per_path_tile
	double search_cap_air = 64.0;   // the furthest any search follows (57.6 tiles at most needed)
	uint64_t run_seed = 0;
};

struct Listener {
	uint32_t id = 0;
	Coord tile;
	double threshold = 0.0;  // np left needed: players 0, the Tapper 4
	double multiplier = 1.0; // the Tapper's ring multiplier (DIR-04)
};

struct Delivery {
	uint32_t listener = 0;
	double remaining_np = 0.0;
	double path_tiles = 0.0;
	int64_t closed_portals = 0;
	Coord apparent_tile;           // the last portal on the path, or the source
	double apparent_x = 0.0;       // with per-listener jitter, in tile units
	double apparent_y = 0.0;
	int64_t via = -1;              // the last portal's id within its cell, -1 for none
	Coord true_source;             // server-only
};

// A listener hears when (level - 12 x closed - threshold) x multiplier covers the air tiles.
inline bool audible(double level, int64_t closed, double closed_cost, double air, double threshold, double multiplier) {
	const double budget = (level - static_cast<double>(closed) * closed_cost - threshold) * multiplier;
	return budget >= 0.0 && air <= budget + 1e-9;
}

class RoadGraph {
public:
	explicit RoadGraph(const lb::core::world::MineMap &mine) : mine_(mine) {}

	GraphParams params;

	// Builds a cell's tables and links it to loaded neighbours. False if the block is invalid.
	bool stitch(Coord cell, const CellBlock &block);
	bool unload(Coord cell);
	// A barrier flip or collapse swap in this cell: rebuild it at once (reroutes this tick).
	void on_tiles_changed(Coord cell);
	bool is_stitched(Coord cell) const { return blocks_.count(cell) != 0; }
	uint64_t epoch() const { return epoch_; }

	void set_listener(const Listener &listener);
	void remove_listener(uint32_t id);

	// Every registered listener that hears an event at these origins (the cheapest origin
	// wins), sorted by listener id. Uses and fills the portal-path cache.
	std::vector<Delivery> propagate(uint64_t event_id, const std::vector<Coord> &origins, double level, Mode mode);

	// One delivery from a source outside the graph (CRT-10's illusions). Pure: touches no
	// listener, cache or epoch. key seeds the jitter.
	std::optional<Delivery> deliver(Coord source, double level, Coord listener_tile, Mode mode, double threshold = 0.0,
			double multiplier = 1.0, uint64_t key = 0) const;

	// Total cost in np (air + closed portals) from a to b, if within max.
	std::optional<double> path_cost(Coord a, Coord b, Mode mode, double max) const;

	// The open tile nearest a rock tile in a straight line, never through brick.
	std::optional<Coord> nearest_open_tile(Coord rock_tile, int64_t max_radius) const;

	// A canonical digest of every table (zones, portals, fields), for reload checks.
	uint64_t tables_digest() const;
	size_t cache_entries() const { return cache_.size(); }
	// Zone and portal slots held, live or free (GEN-11: an unloaded cell's slots are reused, so
	// they stay bounded by what is loaded at once however often cells come and go).
	size_t zone_slots() const { return zones_.size(); }
	size_t portal_slots() const { return portals_.size(); }

private:
	struct Zone {
		bool live = false;
		Coord cell;
		uint16_t id = 0;
		ZoneKind kind = ZoneKind::ROAD;
		std::vector<Coord> tiles;
		std::array<int16_t, lb::core::world::CELL_AREA> index{}; // local tile -> tiles index, -1 if not ours
		std::vector<uint32_t> portals;                  // adjacent portals (global indices)
		std::map<uint32_t, std::vector<double>> field;  // portal -> distance per zone tile
		std::map<std::pair<uint32_t, uint32_t>, double> pp;
	};
	struct Portal {
		bool live = false;
		Coord cell;               // edge links: the lower cell
		uint16_t id = 0;          // 0 for an edge link
		PortalKind kind = PortalKind::OPENING;
		uint32_t barrier = 0;
		std::vector<Coord> tiles;
		std::array<uint32_t, 2> zone{};
		std::array<std::vector<Coord>, 2> side; // the zone tiles a field starts from, per side
		double cross_air = 0.0;
		bool open = true;
		Coord centre;
	};
	struct Entry {
		double air = 0.0;
		int64_t closed = 0;
		int64_t last = -1;   // last portal crossed (global index), -1 for none
		int64_t origin = 0;  // which origin it came from
	};
	// Dense over every node (portal * 2 + side) for fast combining.
	struct SearchResult {
		std::vector<Entry> nodes;
		std::vector<uint8_t> has;
		const Entry *get(uint32_t node) const { return node < has.size() && has[node] ? &nodes[node] : nullptr; }
	};
	// A cached single-source search, sparse: the reached nodes only.
	using Sparse = std::vector<std::pair<uint32_t, Entry>>;

	const lb::core::world::MineMap &mine_;
	std::vector<Zone> zones_;
	std::vector<Portal> portals_;
	std::vector<uint32_t> free_zones_; // dead slots, reused by the next stitch
	std::vector<uint32_t> free_portals_;
	std::map<std::pair<Coord, uint16_t>, uint32_t> zone_by_key_;
	std::map<Coord, uint32_t> portal_by_tile_;
	std::map<Coord, CellBlock> blocks_;
	std::map<Coord, std::vector<uint32_t>> cell_zones_;
	std::map<Coord, std::vector<uint32_t>> cell_portals_; // own portals and edge links touching it
	std::map<uint32_t, Listener> listeners_;
	std::map<std::tuple<uint32_t, int, int>, Sparse> cache_;
	uint64_t epoch_ = 0;

	void bump();
	// A slot for a new zone or portal: a dead one if any, else a new one at the end.
	uint32_t zone_slot();
	uint32_t portal_slot();
	std::optional<uint32_t> zone_of(Coord tile) const;
	std::optional<uint32_t> portal_of(Coord tile) const;
	void build_field(uint32_t zone, uint32_t portal);
	void build_pp(uint32_t zone);
	void link_edges(Coord a, Coord b);
	std::vector<double> zone_distances(uint32_t zone, Coord from, double cap) const;
	bool total_less(const Entry &a, const Entry &b) const;
	double total(const Entry &e) const { return e.air + static_cast<double>(e.closed) * params.closed_cost; }
	void search(std::vector<std::pair<uint32_t, Entry>> starts, Mode mode, double cap, SearchResult &out) const;
	const Sparse &cached(uint32_t node, Mode mode);
	struct Start {
		std::vector<std::pair<uint32_t, Entry>> nodes;
		std::optional<uint32_t> zone;
	};
	Start starts_for(Coord origin, int64_t origin_index) const;
	// In-zone distances from each origin, computed at most once per event.
	using Direct = std::vector<std::optional<std::vector<double>>>;
	std::optional<Delivery> resolve(const Listener &l, const std::vector<Coord> &origins, const std::vector<Start> &starts,
			const SearchResult &result, Direct &direct, double cap, double level, uint64_t jitter_key) const;
	void apply_jitter(Delivery &d, uint64_t event_key) const;
};

} // namespace lb::core::sound

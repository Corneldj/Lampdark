#pragma once
// GEN-13's diff log store (Gameplay §12.6, GDD §15.9): what play changed in the mine, kept by
// cell, so a cell re-derived from the seed can have its changes replayed. A record is keyed by
// (cell, kind, key) and holds the tick it was written and an opaque payload (GDScript's canonical
// var_to_bytes); a write replaces the record of that key, so the store holds state, not history.
// Blood is kept packed: per cell, which of its 400 tiles are smeared and each one's direction
// (0-7), so a long drag costs bits, not records. Run-level sections (the map table, the Pocket
// Books) hold keyed payloads outside any cell.
//
// Everything iterates in a canonical order (cells row-major, then kind, then key bytes), so the
// serialised bytes and the digest are identical on every platform and in every insertion order.
// Not thread-safe: the simulation thread owns the store. Server-only: nothing here reaches a client.

#include "core/world/coords.h"

#include <array>
#include <cstdint>
#include <map>
#include <optional>
#include <string>
#include <tuple>
#include <vector>

namespace lb::core::world {

struct DiffRecord {
	int64_t tick = 0;
	std::vector<uint8_t> payload;
	bool operator==(const DiffRecord &o) const { return tick == o.tick && payload == o.payload; }
};

// One record's address within a cell: the owner's kind (GDScript's DiffLog.Kind) and key.
struct DiffAddress {
	uint8_t kind = 0;
	std::string key;
	bool operator<(const DiffAddress &o) const { return std::tie(kind, key) < std::tie(o.kind, o.key); }
	bool operator==(const DiffAddress &o) const { return kind == o.kind && key == o.key; }
};

class DiffStore {
public:
	static constexpr int64_t CELL_AREA = CELL_TILES * CELL_TILES;
	// A smeared tile's stored value: its direction + 1 (0 is clean).
	static constexpr uint8_t NO_BLOOD = 0;

	// Upserts the record at (cell, kind, key).
	void put(Coord cell, uint8_t kind, const std::string &key, int64_t tick, std::vector<uint8_t> payload);
	// Removes it; false if there was none.
	bool erase(Coord cell, uint8_t kind, const std::string &key);
	std::optional<DiffRecord> get(Coord cell, uint8_t kind, const std::string &key) const;
	// The cell's records in canonical order (kind, then key).
	std::vector<std::pair<DiffAddress, DiffRecord>> records(Coord cell) const;
	// Every cell holding a record or blood, row-major.
	std::vector<Coord> cells() const;
	size_t record_count() const;

	// Smears `tile` heading `direction` (0-7, taken mod 8); the latest smear wins.
	void mark_blood(Coord tile, int64_t direction);
	bool erase_blood(Coord tile);
	// The direction at `tile`, or -1 if clean.
	int64_t blood_at(Coord tile) const;
	// The cell's smeared tiles in row-major order: (tile, direction).
	std::vector<std::pair<Coord, int64_t>> blood(Coord cell) const;
	size_t blood_count() const;

	// Run-level sections.
	void section_put(const std::string &section, const std::string &key, std::vector<uint8_t> payload);
	bool section_erase(const std::string &section, const std::string &key);
	std::optional<std::vector<uint8_t>> section_get(const std::string &section, const std::string &key) const;
	std::vector<std::string> section_keys(const std::string &section) const;
	std::vector<std::string> sections() const;

	// Serialised sizes in bytes: the cells' part (records and blood), and one section.
	size_t cells_bytes() const;
	size_t section_bytes(const std::string &section) const;

	// The whole store, canonical and little-endian; deserialise() replaces the store, and on a
	// malformed buffer leaves it empty and returns false.
	std::vector<uint8_t> serialise() const;
	bool deserialise(const std::vector<uint8_t> &bytes);
	// FNV-1a 64 over serialise().
	uint64_t digest() const;

	void clear();
	bool operator==(const DiffStore &o) const;

private:
	struct Cell {
		std::map<DiffAddress, DiffRecord> records;
		// Per local tile (row-major): NO_BLOOD or direction + 1.
		std::array<uint8_t, CELL_AREA> blood{};
		uint32_t smeared = 0;
		bool empty() const { return records.empty() && smeared == 0; }
	};

	void prune(Coord cell);
	static size_t cell_bytes(const Cell &c);

	std::map<Coord, Cell> cells_;
	std::map<std::string, std::map<std::string, std::vector<uint8_t>>> sections_;
};

} // namespace lb::core::world

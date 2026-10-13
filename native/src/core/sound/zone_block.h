#pragma once
// The Road Graph block of a cell (SND-01, format v0): its zones and portals, stored inside
// GEN-01's cell data. Each walkable tile carries its zone id (GEN-01's packed u16); portal
// tiles carry zone 0 and belong to a portal instead.
//
// Binary layout, little-endian: u8 version; u16 zone count, then per zone u16 id, u8 kind;
// u16 portal count, then per portal u16 id, u8 kind, u16 zone_a, u16 zone_b, u32 barrier
// (GEN-01's barrier id for doors and gates, 0 for an opening), u16 tile count, u16 tiles.

#include "core/world/cell.h"

#include <cstdint>
#include <optional>
#include <string>
#include <vector>

namespace lb::core::sound {

enum class ZoneKind : uint8_t { ROAD, CHAMBER, POI, BASE_CAMP, COUNT };
enum class PortalKind : uint8_t { OPENING, AIR_DOOR, GATE, EDGE, COUNT };

struct ZoneDecl {
	uint16_t id = 0;
	ZoneKind kind = ZoneKind::ROAD;
};

struct PortalDecl {
	uint16_t id = 0;
	PortalKind kind = PortalKind::OPENING;
	uint16_t zone_a = 0;
	uint16_t zone_b = 0;
	uint32_t barrier = 0;
	std::vector<uint16_t> tiles; // local indices
};

struct CellBlock {
	std::vector<ZoneDecl> zones;
	std::vector<PortalDecl> portals;
};

constexpr uint8_t BLOCK_VERSION = 0;

std::vector<uint8_t> encode_block(const CellBlock &block);
std::optional<CellBlock> decode_block(const std::vector<uint8_t> &bytes);

// Problems with a cell's block: every walkable tile in exactly one declared zone or one
// portal; every portal joining two declared zones; barrier portals over that barrier's tiles.
std::vector<std::string> validate_block(const lb::core::world::Cell &cell, const CellBlock &block);

} // namespace lb::core::sound

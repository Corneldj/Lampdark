#pragma once
// GEN-05: the sockets on the edges between cells (Gameplay §12.3). Every edge has one key, so both
// neighbours ask the same question. A socket is shut, or an opening 1-3 tiles wide centred 5, 10
// or 15 tiles along the edge from its west or north end. Forced sockets (base camp, points of
// interest, main roads, spines) beat the hash, in that order. Server-only: no socket reaches a client.

#include "core/gen/template.h"
#include "core/world/coords.h"

#include <cstdint>
#include <map>
#include <optional>
#include <tuple>
#include <vector>

namespace lb::core::gen {

enum class Axis : uint8_t { EAST = 0,
	SOUTH = 1 };

// The edge between (x, y) and (x + 1, y) is (x, y, EAST); between (x, y) and (x, y + 1), (x, y, SOUTH).
struct EdgeKey {
	int64_t x = 0;
	int64_t y = 0;
	Axis axis = Axis::EAST;
	bool operator==(const EdgeKey &o) const { return x == o.x && y == o.y && axis == o.axis; }
	bool operator<(const EdgeKey &o) const { return std::tie(x, y, axis) < std::tie(o.x, o.y, o.axis); }
};

EdgeKey edge_of(lb::core::world::Coord cell, Edge side);
lb::core::world::Coord neighbour(lb::core::world::Coord cell, Edge side);
Edge opposite(Edge side);

struct Socket {
	bool open = false;
	int32_t offset = 0;
	int32_t width = 0;
	bool forced = false;
	bool operator==(const Socket &o) const { return open == o.open && offset == o.offset && width == o.width && forced == o.forced; }
};

// The first edge tile an opening covers, o - floor(w / 2): 1 wide covers o, 2 wide o - 1 and o,
// 3 wide o - 1 to o + 1 (Proposed for even widths).
constexpr int32_t opening_first(int32_t offset, int32_t width) {
	return offset - width / 2;
}

struct SocketParams {
	uint32_t open_ppm = 600000; // mine.edge_open_probability, in millionths
	std::vector<int32_t> offsets{5, 10, 15}; // mine.socket_offsets_tiles
	std::vector<int32_t> widths{1, 2, 3}; // mine.socket_widths_tiles
};

// A forced-socket rule: an answer for the edges it owns, nothing for the rest.
class SocketProvider {
public:
	virtual ~SocketProvider() = default;
	virtual std::optional<Socket> query(const EdgeKey &edge) const = 0;
};

// Sockets fixed up front, such as base camp's (GEN-02: its gates open, its blind side shut).
class FixedSockets : public SocketProvider {
public:
	void set(const EdgeKey &edge, Socket socket);
	std::optional<Socket> query(const EdgeKey &edge) const override;
	const std::map<EdgeKey, Socket> &all() const { return sockets_; }

private:
	std::map<EdgeKey, Socket> sockets_;
};

// Rule 5, the hash: the open roll, the offset and the width each on their own domain, so tuning
// the open probability never reshuffles offsets or widths. `widths` are those both cells allow.
Socket hashed_socket(uint64_t seed, const EdgeKey &edge, const SocketParams &p, const std::vector<int32_t> &widths);

// The widths both cells allow, ascending; the narrowest configured width when they share none
// (GEN-06 decides that case once biomes differ in width).
std::vector<int32_t> shared_widths(const std::vector<int32_t> &a, const std::vector<int32_t> &b, const SocketParams &p);

} // namespace lb::core::gen

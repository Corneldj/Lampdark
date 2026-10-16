#include "core/gen/sockets.h"

#include "core/generated/hash_domains.h"
#include "core/rng/hash.h"

#include <algorithm>

namespace lb::core::gen {

using lb::core::world::Coord;

EdgeKey edge_of(Coord cell, Edge side) {
	switch (side) {
		case Edge::NORTH: return EdgeKey{cell.x, cell.y - 1, Axis::SOUTH};
		case Edge::SOUTH: return EdgeKey{cell.x, cell.y, Axis::SOUTH};
		case Edge::WEST: return EdgeKey{cell.x - 1, cell.y, Axis::EAST};
		default: return EdgeKey{cell.x, cell.y, Axis::EAST};
	}
}

Coord neighbour(Coord cell, Edge side) {
	switch (side) {
		case Edge::NORTH: return Coord{cell.x, cell.y - 1};
		case Edge::SOUTH: return Coord{cell.x, cell.y + 1};
		case Edge::WEST: return Coord{cell.x - 1, cell.y};
		default: return Coord{cell.x + 1, cell.y};
	}
}

Edge opposite(Edge side) {
	return static_cast<Edge>((static_cast<uint8_t>(side) + 2) % 4);
}

void FixedSockets::set(const EdgeKey &edge, Socket socket) {
	socket.forced = true;
	sockets_[edge] = socket;
}

std::optional<Socket> FixedSockets::query(const EdgeKey &edge) const {
	auto it = sockets_.find(edge);
	if (it == sockets_.end()) {
		return std::nullopt;
	}
	return it->second;
}

Socket hashed_socket(uint64_t seed, const EdgeKey &edge, const SocketParams &p, const std::vector<int32_t> &widths) {
	const int64_t keys[3] = {edge.x, edge.y, static_cast<int64_t>(edge.axis)};
	Socket s;
	s.open = hash_u64(seed, hash_domain::GEN_SOCKET_OPEN, keys, 3) % 1000000u < p.open_ppm;
	if (!s.open) {
		return s;
	}
	if (p.offsets.empty() || widths.empty()) {
		s.open = false;
		return s;
	}
	s.offset = p.offsets[hash_u64(seed, hash_domain::GEN_SOCKET_OFFSET, keys, 3) % p.offsets.size()];
	s.width = widths[hash_u64(seed, hash_domain::GEN_SOCKET_WIDTH, keys, 3) % widths.size()];
	return s;
}

std::vector<int32_t> shared_widths(const std::vector<int32_t> &a, const std::vector<int32_t> &b, const SocketParams &p) {
	std::vector<int32_t> x = a;
	std::vector<int32_t> y = b;
	std::sort(x.begin(), x.end());
	std::sort(y.begin(), y.end());
	std::vector<int32_t> out;
	std::set_intersection(x.begin(), x.end(), y.begin(), y.end(), std::back_inserter(out));
	out.erase(std::unique(out.begin(), out.end()), out.end());
	if (out.empty() && !p.widths.empty()) {
		out.push_back(*std::min_element(p.widths.begin(), p.widths.end()));
	}
	return out;
}

} // namespace lb::core::gen

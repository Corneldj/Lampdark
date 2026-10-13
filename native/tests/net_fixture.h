#pragma once
// Helpers for NET-04's tests: desired views built by hand, and a client that decodes every
// frame it receives and acknowledges it.

#include "core/net/client_view.h"

#include <map>
#include <vector>

namespace net_fixture {

using namespace lb::core::net;
using lb::core::world::Coord;
namespace vision = lb::core::vision;

inline OwnBlock own_at(double x, double y) {
	OwnBlock o;
	o.x256 = static_cast<int32_t>(x * 256.0);
	o.y256 = static_cast<int32_t>(y * 256.0);
	return o;
}

inline Desired desired_at(double x, double y) {
	Desired d;
	d.own = own_at(x, y);
	d.frame.glow.assign(22, vision::GlowBucket{});
	return d;
}

inline void add_tile(Desired &d, Coord t, uint8_t light, uint8_t material = 0) {
	vision::FrameTile ft;
	ft.tile = t;
	ft.light = light;
	ft.colour = 1;
	d.frame.tiles.push_back(ft);
	d.geometry_now[t] = GeoView{material, 0};
}

inline void add_token(Desired &d, uint32_t entity, vision::SizeClass size, double x, double y) {
	vision::FrameToken t;
	t.size = size;
	t.x = x;
	t.y = y;
	t.entity = entity;
	d.frame.tokens.push_back(t);
}

inline void add_identity(Desired &d, uint32_t entity, uint8_t kind, double x, double y, uint16_t facing) {
	d.frame.identified.push_back(entity);
	d.identified_kind[entity] = kind;
	d.position[entity] = {x, y};
	d.facing[entity] = facing;
}

// A client: decodes frames against its own history and acknowledges what it decoded.
struct Client {
	std::map<uint32_t, ViewState> history;
	std::vector<uint32_t> received;
	std::vector<EventRec> events;
	int64_t held = 2;

	bool receive(const std::vector<uint8_t> &bytes) {
		Decoded d = decode_frame(bytes, history, held);
		if (!d.ok) {
			return false;
		}
		history[d.tick] = d.view;
		received.push_back(d.tick);
		for (const EventRec &e : d.events) {
			bool seen = false;
			for (const EventRec &old : events) {
				seen = seen || old.number == e.number;
			}
			if (!seen) {
				events.push_back(e);
			}
		}
		return true;
	}

	// The acknowledgement NET-03 would carry: the newest frame and the 32 before it.
	void ack(ClientView &server, uint32_t now) const {
		if (received.empty()) {
			return;
		}
		const uint32_t newest = received.back();
		uint32_t bits = 0;
		for (uint32_t t : received) {
			if (t < newest && newest - t <= 32) {
				bits |= 1u << (newest - t - 1);
			}
		}
		server.on_ack(now, newest & 0xFFFFu, bits);
	}

	const ViewState &latest() const { return history.at(received.back()); }
};

inline ReplicationParams roomy() {
	ReplicationParams p;
	p.budget_bytes_per_tick = 100000;
	p.burst_bytes = 100000;
	p.max_frame_bytes = 100000;
	return p;
}

} // namespace net_fixture

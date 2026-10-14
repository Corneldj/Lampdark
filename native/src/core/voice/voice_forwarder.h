#pragma once
// SND-07: the server's voice forwarder. A speaker's frame comes in; for every listener its routes
// name, it goes out with that listener's header (stream id, gain, flags, apparent position), the
// Opus bytes untouched. It never decodes, mixes or keeps a frame: everything is built and handed
// back in one call. Routes are set by server/systems/sound/voice_routes.gd (who is in range, by
// road or thin rock, and how). Bands 5-7 are refused. No Opus header is included here. Engine-free.

#include <cstddef>
#include <cstdint>
#include <map>
#include <utility>
#include <vector>

namespace lb::core::voice {

struct VoiceRoute {
	uint32_t listener = 0; // a slot
	uint16_t stream = 0;
	int8_t gain_db = 0;
	uint8_t flags = 0; // wire::MUFFLED | TELEPHONE | DRY
	uint8_t crackle = 0;
	int32_t x16 = 0; // apparent position, 1/16 tiles
	int32_t y16 = 0;
};

struct UpstreamHead {
	bool valid = false;
	uint16_t seq = 0;
	int band = 0;
	uint8_t flags = 0; // wire::END | PROBE
};

class VoiceForwarder {
public:
	// Reads an upstream packet's head; invalid when too short or the band is 5-7.
	static UpstreamHead parse(const uint8_t *data, size_t size);

	void set_routes(uint32_t speaker, std::vector<VoiceRoute> routes) { routes_[speaker] = std::move(routes); }
	void clear(uint32_t speaker) { routes_.erase(speaker); }
	size_t route_count(uint32_t speaker) const;

	// One upstream packet from `speaker`: (listener, downstream packet) for each route; nothing kept.
	std::vector<std::pair<uint32_t, std::vector<uint8_t>>> forward(uint32_t speaker, const uint8_t *data, size_t size) const;

private:
	std::map<uint32_t, std::vector<VoiceRoute>> routes_;
};

} // namespace lb::core::voice

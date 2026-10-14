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

#include "core/voice/voice_loss.h"

namespace lb::core::voice {

struct VoiceRoute {
	uint32_t listener = 0; // a slot
	uint16_t stream = 0;
	int8_t gain_db = 0;
	uint8_t flags = 0; // wire::MUFFLED | TELEPHONE | DRY
	uint8_t treat = 0; // wire::CRACKLE | muffle level << wire::MUFFLE_SHIFT
	double loss = 0.0; // SND-08: this listener's combined drop share
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

	// SND-08: the run seed the loss processes are keyed from, and their run lengths.
	void set_loss(uint64_t run_seed, const LossParams &p) {
		run_seed_ = run_seed;
		loss_params_ = p;
	}
	// The speaker's routes for utterance `utterance`; a new utterance starts fresh loss processes.
	void set_routes(uint32_t speaker, std::vector<VoiceRoute> routes, uint64_t utterance = 0);
	void clear(uint32_t speaker);
	size_t route_count(uint32_t speaker) const;

	// One upstream packet from `speaker`: (listener, downstream packet) for each route whose loss
	// process keeps this frame; nothing kept between calls but the processes' state.
	std::vector<std::pair<uint32_t, std::vector<uint8_t>>> forward(uint32_t speaker, const uint8_t *data, size_t size);

	// This utterance's counts per listener: frames that reached the forwarder, frames sent on.
	struct Counts {
		uint32_t seen = 0;
		uint32_t sent = 0;
	};
	std::map<uint32_t, Counts> counts(uint32_t speaker) const;

private:
	struct Speaker {
		std::vector<VoiceRoute> routes;
		uint64_t utterance = 0;
		std::map<uint32_t, LossProcess> loss;
		std::map<uint32_t, Counts> counts;
	};
	std::map<uint32_t, Speaker> speakers_;
	uint64_t run_seed_ = 0;
	LossParams loss_params_;
};

} // namespace lb::core::voice

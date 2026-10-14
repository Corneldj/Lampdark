#pragma once
// SND-07: one voice stream's jitter buffer. Frame k of a stream plays at the first packet's arrival
// plus the target delay plus k frames; a frame still missing when its time comes is lost (the
// player conceals or smears it), and one that arrives after its time is dropped. The target is
// fixed for a stream, so speech is never stretched mid-utterance; it adapts between streams:
// each measures its arrival jitter (RFC 3550's estimate), and the next starts from
// suggest_ms(), between `min_ms` and `max_ms`. Engine-free.

#include <cstdint>
#include <map>
#include <vector>

namespace lb::core::voice {

struct JitterParams {
	int frame_ms = 20;
	int min_ms = 0; // voice.jitter_buffer_min_ms
	int max_ms = 0; // voice.jitter_buffer_max_ms
	int start_ms = 0; // the target at the stream's start
};

class JitterBuffer {
public:
	enum class Kind {
		NONE,
		FRAME,
		LOST,
		END,
	};
	struct Out {
		Kind kind = Kind::NONE;
		uint16_t seq = 0;
		uint8_t head = 0;
		int lost_run = 0; // consecutive frames lost, this one included
		std::vector<uint8_t> payload;
	};

	explicit JitterBuffer(const JitterParams &p);
	// The target for the next stream, from the jitter measured so far: twice it plus a frame.
	static int suggest_ms(double jitter_ms, const JitterParams &p);
	// A packet of this stream; false if it came after its playout time (dropped) or is a duplicate.
	bool push(uint16_t seq, uint8_t head, const uint8_t *payload, size_t size, int64_t now_us);
	// The next frame whose time has come, if any.
	bool pop(int64_t now_us, Out &out);
	// The stream has ended (its END packet played, or nothing arrived for max_ms after its last).
	bool done() const { return done_; }
	double jitter_ms() const { return jitter_us_ / 1000.0; }
	int target_ms() const { return target_ms_; }
	size_t waiting() const { return frames_.size(); }

private:
	struct Frame {
		uint8_t head = 0;
		std::vector<uint8_t> payload;
	};
	int64_t due_us(int32_t k) const { return base_us_ + static_cast<int64_t>(target_ms_) * 1000 + static_cast<int64_t>(k) * params_.frame_ms * 1000; }

	JitterParams params_;
	bool started_ = false;
	bool done_ = false;
	uint16_t base_seq_ = 0;
	int64_t base_us_ = 0;
	int32_t next_k_ = 0; // the next frame to play, counted from the base
	int32_t end_k_ = -1; // the END packet's frame, once known
	int32_t last_k_ = -1; // the newest frame received
	int64_t last_arrival_us_ = 0;
	int lost_run_ = 0;
	int target_ms_ = 0;
	double jitter_us_ = 0.0;
	bool have_transit_ = false;
	int64_t prev_transit_us_ = 0;
	std::map<int32_t, Frame> frames_;
};

} // namespace lb::core::voice

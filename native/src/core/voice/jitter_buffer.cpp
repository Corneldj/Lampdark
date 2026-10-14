#include "core/voice/jitter_buffer.h"

#include <algorithm>
#include <cstdlib>

#include "core/voice/voice_wire.h"

namespace lb::core::voice {

JitterBuffer::JitterBuffer(const JitterParams &p) : params_(p) {
	target_ms_ = std::clamp(p.start_ms, p.min_ms, std::max(p.min_ms, p.max_ms));
}

int JitterBuffer::suggest_ms(double jitter_ms, const JitterParams &p) {
	return std::clamp(static_cast<int>(2.0 * jitter_ms) + p.frame_ms, p.min_ms, p.max_ms);
}

bool JitterBuffer::push(uint16_t seq, uint8_t head, const uint8_t *payload, size_t size, int64_t now_us) {
	if (done_) {
		return false;
	}
	if (!started_) {
		started_ = true;
		base_seq_ = seq;
		base_us_ = now_us;
	}
	const int32_t k = static_cast<int16_t>(static_cast<uint16_t>(seq - base_seq_));
	if (k < next_k_ || frames_.count(k) != 0) {
		return false; // late (its time has passed) or a duplicate
	}
	// RFC 3550's interarrival jitter, from each packet's transit relative to the stream's clock.
	const int64_t transit = now_us - static_cast<int64_t>(k) * params_.frame_ms * 1000;
	if (have_transit_) {
		const double d = static_cast<double>(std::llabs(transit - prev_transit_us_));
		jitter_us_ += (d - jitter_us_) / 16.0;
	}
	have_transit_ = true;
	prev_transit_us_ = transit;
	Frame f;
	f.head = head;
	f.payload.assign(payload, payload + size);
	frames_.emplace(k, std::move(f));
	last_k_ = std::max(last_k_, k);
	last_arrival_us_ = now_us;
	if (head & wire::END) {
		end_k_ = k;
	}
	// Bound the buffer: never more than max_ms ahead of playout.
	while (!frames_.empty() && frames_.rbegin()->first - next_k_ > params_.max_ms / params_.frame_ms + 2) {
		frames_.erase(std::prev(frames_.end()));
	}
	return true;
}

bool JitterBuffer::pop(int64_t now_us, Out &out) {
	if (!started_ || done_ || now_us < due_us(next_k_)) {
		return false;
	}
	out = Out{};
	out.seq = static_cast<uint16_t>(base_seq_ + next_k_);
	auto it = frames_.find(next_k_);
	if (it != frames_.end()) {
		out.kind = (it->second.head & wire::END) && it->second.payload.empty() ? Kind::END : Kind::FRAME;
		out.head = it->second.head;
		out.payload = std::move(it->second.payload);
		frames_.erase(it);
		lost_run_ = 0;
	} else if (end_k_ >= 0 && next_k_ >= end_k_) {
		out.kind = Kind::END;
	} else if (now_us - last_arrival_us_ > static_cast<int64_t>(params_.max_ms + 4 * params_.frame_ms) * 1000 && frames_.empty()) {
		out.kind = Kind::END; // the stream went quiet with no END: its last run was lost
	} else {
		out.kind = Kind::LOST;
		out.lost_run = ++lost_run_;
	}
	if (out.kind == Kind::END || (out.kind == Kind::FRAME && (out.head & wire::END))) {
		done_ = true;
	}
	next_k_++;
	return true;
}

} // namespace lb::core::voice

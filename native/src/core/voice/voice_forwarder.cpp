#include "core/voice/voice_forwarder.h"

#include "core/voice/voice_wire.h"

namespace lb::core::voice {

namespace {

void put16(std::vector<uint8_t> &b, uint16_t v) {
	b.push_back(static_cast<uint8_t>(v & 0xFF));
	b.push_back(static_cast<uint8_t>(v >> 8));
}

void put32(std::vector<uint8_t> &b, int32_t v) {
	const uint32_t u = static_cast<uint32_t>(v);
	for (int i = 0; i < 4; i++) {
		b.push_back(static_cast<uint8_t>((u >> (8 * i)) & 0xFF));
	}
}

} // namespace

UpstreamHead VoiceForwarder::parse(const uint8_t *data, size_t size) {
	UpstreamHead h;
	if (data == nullptr || size < static_cast<size_t>(wire::UP_HEADER)) {
		return h;
	}
	h.seq = static_cast<uint16_t>(data[0] | (data[1] << 8));
	h.band = data[2] & wire::BAND_MASK;
	h.flags = data[2] & wire::UP_FLAGS;
	h.valid = h.band <= wire::MAX_BAND && (data[2] & ~(wire::BAND_MASK | wire::UP_FLAGS)) == 0;
	return h;
}

size_t VoiceForwarder::route_count(uint32_t speaker) const {
	auto it = routes_.find(speaker);
	return it == routes_.end() ? 0 : it->second.size();
}

std::vector<std::pair<uint32_t, std::vector<uint8_t>>> VoiceForwarder::forward(uint32_t speaker, const uint8_t *data, size_t size) const {
	std::vector<std::pair<uint32_t, std::vector<uint8_t>>> out;
	const UpstreamHead h = parse(data, size);
	auto it = routes_.find(speaker);
	if (!h.valid || it == routes_.end()) {
		return out;
	}
	const uint8_t *opus = data + wire::UP_HEADER;
	const size_t opus_size = size - wire::UP_HEADER;
	out.reserve(it->second.size());
	for (const VoiceRoute &r : it->second) {
		std::vector<uint8_t> b;
		b.reserve(wire::DOWN_HEADER + opus_size);
		put16(b, r.stream);
		put16(b, h.seq);
		b.push_back(static_cast<uint8_t>(h.band | h.flags | (r.flags & (wire::MUFFLED | wire::TELEPHONE | wire::DRY))));
		b.push_back(static_cast<uint8_t>(r.gain_db));
		b.push_back(r.crackle);
		put32(b, r.x16);
		put32(b, r.y16);
		b.insert(b.end(), opus, opus + opus_size);
		out.emplace_back(r.listener, std::move(b));
	}
	return out;
}

} // namespace lb::core::voice

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

void VoiceForwarder::set_routes(uint32_t speaker, std::vector<VoiceRoute> routes, uint64_t utterance) {
	Speaker &s = speakers_[speaker];
	if (s.utterance != utterance) {
		s.utterance = utterance;
		s.loss.clear();
		s.counts.clear();
	}
	s.routes = std::move(routes);
}

void VoiceForwarder::clear(uint32_t speaker) {
	speakers_.erase(speaker);
}

size_t VoiceForwarder::route_count(uint32_t speaker) const {
	auto it = speakers_.find(speaker);
	return it == speakers_.end() ? 0 : it->second.routes.size();
}

std::map<uint32_t, VoiceForwarder::Counts> VoiceForwarder::counts(uint32_t speaker) const {
	auto it = speakers_.find(speaker);
	return it == speakers_.end() ? std::map<uint32_t, Counts>{} : it->second.counts;
}

std::vector<std::pair<uint32_t, std::vector<uint8_t>>> VoiceForwarder::forward(uint32_t speaker, const uint8_t *data, size_t size) {
	std::vector<std::pair<uint32_t, std::vector<uint8_t>>> out;
	const UpstreamHead h = parse(data, size);
	auto it = speakers_.find(speaker);
	if (!h.valid || it == speakers_.end()) {
		return out;
	}
	Speaker &s = it->second;
	const uint8_t *opus = data + wire::UP_HEADER;
	const size_t opus_size = size - wire::UP_HEADER;
	out.reserve(s.routes.size());
	for (const VoiceRoute &r : s.routes) {
		Counts &c = s.counts[r.listener];
		c.seen++;
		// SND-08: an END always goes through (it carries no audio, and closes the stream).
		if (r.loss > 0.0 && !(h.flags & wire::END)) {
			auto lp = s.loss.find(r.listener);
			if (lp == s.loss.end()) {
				lp = s.loss.emplace(r.listener, LossProcess(run_seed_, s.utterance, r.listener, loss_params_)).first;
			}
			if (!lp->second.keep(r.loss)) {
				continue; // dropped frames are never sent
			}
		}
		c.sent++;
		std::vector<uint8_t> b;
		b.reserve(wire::DOWN_HEADER + opus_size);
		put16(b, r.stream);
		put16(b, h.seq);
		b.push_back(static_cast<uint8_t>(h.band | h.flags | (r.flags & (wire::MUFFLED | wire::TELEPHONE | wire::DRY))));
		b.push_back(static_cast<uint8_t>(r.gain_db));
		b.push_back(r.treat);
		put32(b, r.x16);
		put32(b, r.y16);
		b.insert(b.end(), opus, opus + opus_size);
		out.emplace_back(r.listener, std::move(b));
	}
	return out;
}

} // namespace lb::core::voice

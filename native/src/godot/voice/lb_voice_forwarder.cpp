#include "godot/voice/lb_voice_forwarder.h"

#include "core/voice/voice_wire.h"

#include <godot_cpp/core/class_db.hpp>

#include <algorithm>
#include <cmath>

using namespace godot;
namespace cv = lb::core::voice;

namespace lb::godot {

Dictionary LbVoiceForwarder::parse(const PackedByteArray &packet) {
	const cv::UpstreamHead h = cv::VoiceForwarder::parse(packet.ptr(), static_cast<size_t>(packet.size()));
	Dictionary d;
	d["valid"] = h.valid;
	d["seq"] = h.seq;
	d["band"] = h.band;
	d["end"] = (h.flags & cv::wire::END) != 0;
	d["probe"] = (h.flags & cv::wire::PROBE) != 0;
	return d;
}

void LbVoiceForwarder::set_routes(int64_t speaker, const Array &routes) {
	std::vector<cv::VoiceRoute> rs;
	for (int64_t i = 0; i < routes.size(); i++) {
		const Dictionary r = routes[i];
		cv::VoiceRoute v;
		v.listener = static_cast<uint32_t>(static_cast<int64_t>(r.get("listener", 0)));
		v.stream = static_cast<uint16_t>(static_cast<int64_t>(r.get("stream", 0)));
		v.gain_db = static_cast<int8_t>(std::clamp<int64_t>(static_cast<int64_t>(std::lround(static_cast<double>(r.get("gain_db", 0.0)))), -128, 127));
		v.flags = static_cast<uint8_t>(static_cast<int64_t>(r.get("flags", 0)));
		v.crackle = static_cast<uint8_t>(static_cast<int64_t>(r.get("crackle", 0)));
		v.x16 = static_cast<int32_t>(std::lround(static_cast<double>(r.get("x", 0.0)) * cv::wire::POS_SCALE));
		v.y16 = static_cast<int32_t>(std::lround(static_cast<double>(r.get("y", 0.0)) * cv::wire::POS_SCALE));
		rs.push_back(v);
	}
	fwd_.set_routes(static_cast<uint32_t>(speaker), std::move(rs));
}

void LbVoiceForwarder::clear(int64_t speaker) {
	fwd_.clear(static_cast<uint32_t>(speaker));
}

int64_t LbVoiceForwarder::route_count(int64_t speaker) const {
	return static_cast<int64_t>(fwd_.route_count(static_cast<uint32_t>(speaker)));
}

Array LbVoiceForwarder::forward(int64_t speaker, const PackedByteArray &packet) const {
	Array out;
	for (const auto &item : fwd_.forward(static_cast<uint32_t>(speaker), packet.ptr(), static_cast<size_t>(packet.size()))) {
		PackedByteArray b;
		b.resize(static_cast<int64_t>(item.second.size()));
		std::copy(item.second.begin(), item.second.end(), b.ptrw());
		Array pair;
		pair.push_back(static_cast<int64_t>(item.first));
		pair.push_back(b);
		out.push_back(pair);
	}
	return out;
}

void LbVoiceForwarder::_bind_methods() {
	ClassDB::bind_static_method("LbVoiceForwarder", D_METHOD("parse", "packet"), &LbVoiceForwarder::parse);
	ClassDB::bind_method(D_METHOD("set_routes", "speaker", "routes"), &LbVoiceForwarder::set_routes);
	ClassDB::bind_method(D_METHOD("clear", "speaker"), &LbVoiceForwarder::clear);
	ClassDB::bind_method(D_METHOD("route_count", "speaker"), &LbVoiceForwarder::route_count);
	ClassDB::bind_method(D_METHOD("forward", "speaker", "packet"), &LbVoiceForwarder::forward);
	BIND_CONSTANT(cv::wire::END);
}

} // namespace lb::godot

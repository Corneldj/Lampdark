#include "godot/voice/lb_voice_playout.h"

#include "core/voice/voice_wire.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/vector2.hpp>

using namespace godot;
namespace cv = lb::core::voice;

namespace lb::godot {

void LbVoicePlayout::configure(const Dictionary &d) {
	cv::PlayoutParams p;
	p.jitter.frame_ms = static_cast<int>(static_cast<int64_t>(d.get("frame_ms", 20)));
	p.jitter.min_ms = static_cast<int>(static_cast<int64_t>(d.get("min_ms", 40)));
	p.jitter.max_ms = static_cast<int>(static_cast<int64_t>(d.get("max_ms", 120)));
	p.jitter.start_ms = static_cast<int>(static_cast<int64_t>(d.get("start_ms", 60)));
	p.speech_low_hz = d.get("speech_low_hz", 300.0);
	p.speech_high_hz = d.get("speech_high_hz", 3400.0);
	const PackedFloat32Array caps = d.get("cap_dbfs", PackedFloat32Array());
	for (int i = 0; i < 4 && i < caps.size(); i++) {
		p.cap_dbfs[i + 1] = caps[i];
	}
	p.smear_dbfs = d.get("smear_dbfs", -60.0);
	p.hiss_dbfs = d.get("hiss_dbfs", -60.0);
	p_ = std::make_unique<cv::VoicePlayout>(p);
}

bool LbVoicePlayout::push(const PackedByteArray &packet, int64_t now_usec) {
	return p_ && p_->push(packet.ptr(), static_cast<size_t>(packet.size()), now_usec);
}

Array LbVoicePlayout::pop(int64_t now_usec) {
	Array out;
	if (!p_) {
		return out;
	}
	static const char *kinds[] = {"frame", "conceal", "smear", "end"};
	for (const cv::VoicePlayout::Out &o : p_->pop(now_usec)) {
		Dictionary d;
		d["kind"] = kinds[static_cast<int>(o.kind)];
		PackedFloat32Array pcm;
		pcm.resize(static_cast<int64_t>(o.pcm.size()));
		std::copy(o.pcm.begin(), o.pcm.end(), pcm.ptrw());
		d["pcm"] = pcm;
		d["band"] = o.head & cv::wire::BAND_MASK;
		d["probe_t0_usec"] = o.probe_t0_us;
		d["cap_db"] = o.cap_gain_db;
		out.push_back(d);
	}
	return out;
}

bool LbVoicePlayout::done() const {
	return !p_ || p_->done();
}

double LbVoicePlayout::jitter_ms() const {
	return p_ ? p_->jitter_ms() : 0.0;
}

int64_t LbVoicePlayout::target_ms() const {
	return p_ ? p_->target_ms() : 0;
}

Dictionary LbVoicePlayout::header() const {
	Dictionary d;
	if (!p_) {
		return d;
	}
	d["gain_db"] = p_->gain_db();
	d["muffled"] = (p_->flags() & cv::wire::MUFFLED) != 0;
	d["telephone"] = (p_->flags() & cv::wire::TELEPHONE) != 0;
	d["dry"] = (p_->flags() & cv::wire::DRY) != 0;
	d["crackle"] = p_->crackle();
	d["position"] = Vector2(static_cast<real_t>(p_->x()), static_cast<real_t>(p_->y()));
	return d;
}

int64_t LbVoicePlayout::suggest_ms(double jitter_ms, int64_t min_ms, int64_t max_ms, int64_t frame_ms) {
	cv::JitterParams p;
	p.min_ms = static_cast<int>(min_ms);
	p.max_ms = static_cast<int>(max_ms);
	p.frame_ms = static_cast<int>(frame_ms);
	return cv::JitterBuffer::suggest_ms(jitter_ms, p);
}

int64_t LbVoicePlayout::stream_of(const PackedByteArray &packet) {
	if (packet.size() < cv::wire::DOWN_HEADER) {
		return 0;
	}
	return static_cast<int64_t>(packet[0] | (packet[1] << 8));
}

void LbVoicePlayout::_bind_methods() {
	ClassDB::bind_method(D_METHOD("configure", "params"), &LbVoicePlayout::configure);
	ClassDB::bind_method(D_METHOD("push", "packet", "now_usec"), &LbVoicePlayout::push);
	ClassDB::bind_method(D_METHOD("pop", "now_usec"), &LbVoicePlayout::pop);
	ClassDB::bind_method(D_METHOD("done"), &LbVoicePlayout::done);
	ClassDB::bind_method(D_METHOD("jitter_ms"), &LbVoicePlayout::jitter_ms);
	ClassDB::bind_method(D_METHOD("target_ms"), &LbVoicePlayout::target_ms);
	ClassDB::bind_method(D_METHOD("header"), &LbVoicePlayout::header);
	ClassDB::bind_static_method("LbVoicePlayout", D_METHOD("suggest_ms", "jitter_ms", "min_ms", "max_ms", "frame_ms"), &LbVoicePlayout::suggest_ms);
	ClassDB::bind_static_method("LbVoicePlayout", D_METHOD("stream_of", "packet"), &LbVoicePlayout::stream_of);
}

} // namespace lb::godot

#include "godot/voice/lb_voice_capture.h"

#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/core/class_db.hpp>

#include <chrono>

using namespace godot;
namespace cv = lb::core::voice;

namespace lb::godot {

std::atomic<int64_t> LbVoiceCapture::total_opens_{0};

LbVoiceCapture::LbVoiceCapture() = default;

// The driver is made on first use, so nothing touches the system's audio until the client asks.
cv::MicCapture &LbVoiceCapture::mic() {
	if (!mic_) {
		use_driver(kind_);
	}
	return *mic_;
}

const cv::MicCapture *LbVoiceCapture::mic_if_made() const {
	return mic_.get();
}

bool LbVoiceCapture::use_driver(const String &kind) {
	if (mic_) {
		mic_->close();
	}
	fake_ = nullptr;
	std::unique_ptr<cv::CaptureDriver> d;
	if (kind == "device") {
		d = cv::make_miniaudio_driver();
	} else if (kind == "null") {
		d = cv::make_null_miniaudio_driver();
#ifdef LB_DEBUG_TOOLS
	} else if (kind == "fake") {
		auto f = std::make_unique<cv::FakeCaptureDriver>();
		fake_ = f.get();
		d = std::move(f);
#endif
	} else {
		return false;
	}
	kind_ = kind;
	mic_ = std::make_unique<cv::MicCapture>(std::move(d));
	mic_->configure(params_);
	return true;
}

bool LbVoiceCapture::configure(const String &backend, const String &noise, double speex_tail_ms,
		const PackedFloat32Array &speex_suppress_db) {
	cv::ProcessorParams p;
	if (!cv::parse_backend(backend.utf8().get_data(), p.backend) || !cv::parse_noise_level(noise.utf8().get_data(), p.noise) ||
			speex_suppress_db.size() != 4) {
		return false;
	}
	p.speex_echo_tail_ms = speex_tail_ms;
	for (int i = 0; i < 4; i++) {
		p.speex_suppress_db[i] = speex_suppress_db[i];
	}
	if (!mic().configure(p)) {
		return false;
	}
	params_ = p;
	return true;
}

Array LbVoiceCapture::devices() {
	Array out;
	for (const cv::CaptureDevice &d : mic().devices()) {
		Dictionary e;
		e["id"] = String::utf8(d.id.c_str());
		e["name"] = String::utf8(d.name.c_str());
		e["is_default"] = d.is_default;
		out.push_back(e);
	}
	return out;
}

bool LbVoiceCapture::open(const String &id) {
	const bool was_open = mic().is_open();
	const bool ok = mic().open(id.utf8().get_data());
	if (ok && !was_open) {
		total_opens_.fetch_add(1);
	}
	return ok;
}

void LbVoiceCapture::close() {
	if (mic_) {
		mic_->close();
	}
}

bool LbVoiceCapture::is_open() const {
	return mic_ && mic_->is_open();
}

bool LbVoiceCapture::is_lost() const {
	return mic_ && mic_->lost();
}

String LbVoiceCapture::device_id() const {
	return mic_ ? String::utf8(mic_->device_id().c_str()) : String();
}

int64_t LbVoiceCapture::open_count() const {
	return mic_ ? static_cast<int64_t>(mic_->open_count()) : 0;
}

int64_t LbVoiceCapture::total_open_count() {
	return total_opens_.load();
}

void LbVoiceCapture::push_far_end(const PackedVector2Array &frames, int64_t mix_rate) {
	if (!mic_ || frames.is_empty() || mix_rate <= 0) {
		return;
	}
	// Vector2 is two floats: the stereo frames, interleaved, as they lie.
	mic_->push_far_end_stereo(reinterpret_cast<const float *>(frames.ptr()), static_cast<uint32_t>(frames.size()),
			static_cast<uint32_t>(mix_rate));
}

Array LbVoiceCapture::pop_frames() {
	Array out;
	if (!mic_) {
		return out;
	}
	cv::CaptureFrame f;
	const int64_t steady_now = std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now().time_since_epoch()).count();
	const int64_t ticks_now = static_cast<int64_t>(Time::get_singleton()->get_ticks_usec());
	while (mic_->pop_frame(f)) {
		PackedFloat32Array pcm;
		pcm.resize(cv::CAPTURE_FRAME);
		std::copy(std::begin(f.pcm), std::end(f.pcm), pcm.ptrw());
		Array item;
		item.push_back(pcm);
		item.push_back(ticks_now - (steady_now - f.steady_usec));
		out.push_back(item);
	}
	std::fill(std::begin(f.pcm), std::end(f.pcm), 0.0f);
	return out;
}

Dictionary LbVoiceCapture::stats() const {
	Dictionary d;
	const cv::MicCapture *m = mic_if_made();
	d["device_latency_ms"] = m ? m->device_latency_ms() : 0.0;
	d["processing_us_p95"] = m ? m->processing_us_p95() : 0.0;
	d["dropped_frames"] = m ? static_cast<int64_t>(m->dropped_frames()) : 0;
	d["dropped_far_end"] = m ? static_cast<int64_t>(m->dropped_far_end()) : 0;
	return d;
}

void LbVoiceCapture::fake_add_device(const String &id, const String &name, bool is_default) {
	if (fake_ != nullptr) {
		fake_->add_device(id.utf8().get_data(), name.utf8().get_data(), is_default);
	}
}

void LbVoiceCapture::fake_remove_device(const String &id) {
	if (fake_ != nullptr) {
		fake_->remove_device(id.utf8().get_data());
	}
}

bool LbVoiceCapture::fake_feed(const PackedFloat32Array &samples) {
	return fake_ != nullptr && fake_->feed(samples.ptr(), static_cast<uint32_t>(samples.size()));
}

void LbVoiceCapture::_bind_methods() {
	ClassDB::bind_method(D_METHOD("use_driver", "kind"), &LbVoiceCapture::use_driver);
	ClassDB::bind_method(D_METHOD("configure", "backend", "noise", "speex_tail_ms", "speex_suppress_db"), &LbVoiceCapture::configure);
	ClassDB::bind_method(D_METHOD("devices"), &LbVoiceCapture::devices);
	ClassDB::bind_method(D_METHOD("open", "id"), &LbVoiceCapture::open);
	ClassDB::bind_method(D_METHOD("close"), &LbVoiceCapture::close);
	ClassDB::bind_method(D_METHOD("is_open"), &LbVoiceCapture::is_open);
	ClassDB::bind_method(D_METHOD("is_lost"), &LbVoiceCapture::is_lost);
	ClassDB::bind_method(D_METHOD("device_id"), &LbVoiceCapture::device_id);
	ClassDB::bind_method(D_METHOD("open_count"), &LbVoiceCapture::open_count);
	ClassDB::bind_static_method("LbVoiceCapture", D_METHOD("total_open_count"), &LbVoiceCapture::total_open_count);
	ClassDB::bind_method(D_METHOD("push_far_end", "frames", "mix_rate"), &LbVoiceCapture::push_far_end);
	ClassDB::bind_method(D_METHOD("pop_frames"), &LbVoiceCapture::pop_frames);
	ClassDB::bind_method(D_METHOD("stats"), &LbVoiceCapture::stats);
#ifdef LB_DEBUG_TOOLS
	ClassDB::bind_method(D_METHOD("fake_add_device", "id", "name", "is_default"), &LbVoiceCapture::fake_add_device);
	ClassDB::bind_method(D_METHOD("fake_remove_device", "id"), &LbVoiceCapture::fake_remove_device);
	ClassDB::bind_method(D_METHOD("fake_feed", "samples"), &LbVoiceCapture::fake_feed);
#endif
}

} // namespace lb::godot

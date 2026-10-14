#include "godot/audio/lb_audio_mixer.h"

#include <godot_cpp/core/class_db.hpp>

#include <vector>

using namespace godot;
namespace audio = lb::core::audio;

namespace lb::godot {

void LbAudioMixer::_bind_methods() {
	ClassDB::bind_method(D_METHOD("setup", "sample_rate", "hrtf_frame", "hrtf_bilinear"), &LbAudioMixer::setup, DEFVAL(512), DEFVAL(false));
	ClassDB::bind_method(D_METHOD("set_pose", "x", "y", "facing_u16"), &LbAudioMixer::set_pose);
	ClassDB::bind_method(D_METHOD("set_mode", "mode"), &LbAudioMixer::set_mode);
	ClassDB::bind_method(D_METHOD("get_mode"), &LbAudioMixer::get_mode);
	ClassDB::bind_method(D_METHOD("set_rear", "start_deg", "min_hz"), &LbAudioMixer::set_rear);
	ClassDB::bind_method(D_METHOD("add", "samples", "rate", "x", "y", "gain_db", "group", "positional", "loop"), &LbAudioMixer::add);
	ClassDB::bind_method(D_METHOD("remove", "id"), &LbAudioMixer::remove);
	ClassDB::bind_method(D_METHOD("open_stream", "rate", "x", "y", "gain_db", "group", "positional"), &LbAudioMixer::open_stream);
	ClassDB::bind_method(D_METHOD("append", "id", "samples"), &LbAudioMixer::append);
	ClassDB::bind_method(D_METHOD("set_gain", "id", "gain_db"), &LbAudioMixer::set_gain);
	ClassDB::bind_method(D_METHOD("close_stream", "id"), &LbAudioMixer::close_stream);
	ClassDB::bind_method(D_METHOD("queued", "id"), &LbAudioMixer::queued);
	ClassDB::bind_method(D_METHOD("has", "id"), &LbAudioMixer::has);
	ClassDB::bind_method(D_METHOD("move", "id", "x", "y"), &LbAudioMixer::move);
	ClassDB::bind_method(D_METHOD("count"), &LbAudioMixer::count);
	ClassDB::bind_method(D_METHOD("mix", "group", "frames"), &LbAudioMixer::mix);
	ClassDB::bind_method(D_METHOD("azimuth_of", "id"), &LbAudioMixer::azimuth_of);
	ClassDB::bind_method(D_METHOD("rear_cutoff_of", "id"), &LbAudioMixer::rear_cutoff_of);
#ifdef LB_DEBUG_TOOLS
	ClassDB::bind_method(D_METHOD("set_screen_up", "on"), &LbAudioMixer::set_screen_up);
#endif
	ClassDB::bind_method(D_METHOD("is_screen_up"), &LbAudioMixer::is_screen_up);
	ClassDB::bind_method(D_METHOD("has_hrtf"), &LbAudioMixer::has_hrtf);
	ClassDB::bind_method(D_METHOD("hrtf_name"), &LbAudioMixer::hrtf_name);
	ClassDB::bind_method(D_METHOD("hrtf_error"), &LbAudioMixer::hrtf_error);
	ClassDB::bind_method(D_METHOD("use_hrtf", "on"), &LbAudioMixer::use_hrtf);
}

void LbAudioMixer::setup(double sample_rate, int64_t hrtf_frame, bool hrtf_bilinear) {
	mixer_ = std::make_unique<audio::Mixer>(sample_rate);
	std::unique_ptr<audio::PhononHrtf> phonon =
			audio::PhononHrtf::load(static_cast<int>(sample_rate), static_cast<int>(hrtf_frame), "", hrtf_bilinear);
	hrtf_ = std::shared_ptr<audio::Hrtf>(std::move(phonon));
	hrtf_error_ = hrtf_ ? "" : audio::PhononHrtf::last_error();
	mixer_->set_hrtf(hrtf_);
}

bool LbAudioMixer::has_hrtf() const {
	return mixer_->hrtf() != nullptr;
}

String LbAudioMixer::hrtf_name() const {
	return mixer_->hrtf() != nullptr ? String(mixer_->hrtf()->name()) : String("spherical_head");
}

String LbAudioMixer::hrtf_error() const {
	return String(hrtf_error_.c_str());
}

void LbAudioMixer::use_hrtf(bool on) {
	mixer_->set_hrtf(on ? hrtf_ : nullptr);
}

void LbAudioMixer::set_pose(double x, double y, int64_t facing_u16) {
	mixer_->set_pose(audio::Pose{x, y, static_cast<double>(facing_u16 & 0xFFFF) / 65536.0});
}

void LbAudioMixer::set_mode(int64_t mode) {
	mixer_->set_mode(static_cast<audio::OutputMode>(mode < 0 || mode > 2 ? 0 : mode));
}

int64_t LbAudioMixer::get_mode() const {
	return static_cast<int64_t>(mixer_->mode());
}

void LbAudioMixer::set_rear(double start_deg, double min_hz) {
	audio::RearParams p;
	p.start_deg = start_deg;
	p.min_hz = min_hz;
	mixer_->set_rear(p);
}

int64_t LbAudioMixer::add(const PackedFloat32Array &samples, double rate, double x, double y, double gain_db, int64_t group,
		bool positional, bool loop) {
	audio::SourceDesc d;
	d.samples.assign(samples.ptr(), samples.ptr() + samples.size());
	d.rate = rate;
	d.x = x;
	d.y = y;
	d.gain_db = gain_db;
	d.group = static_cast<uint8_t>(group & 0xFF);
	d.positional = positional;
	d.loop = loop;
	return mixer_->add(d);
}

int64_t LbAudioMixer::open_stream(double rate, double x, double y, double gain_db, int64_t group, bool positional) {
	audio::SourceDesc d;
	d.rate = rate;
	d.x = x;
	d.y = y;
	d.gain_db = gain_db;
	d.group = static_cast<uint8_t>(group & 0xFF);
	d.positional = positional;
	d.streaming = true;
	return mixer_->add(d);
}

bool LbAudioMixer::append(int64_t id, const PackedFloat32Array &samples) {
	return mixer_->append(static_cast<uint32_t>(id), samples.ptr(), static_cast<size_t>(samples.size()));
}

void LbAudioMixer::set_gain(int64_t id, double gain_db) {
	mixer_->set_gain(static_cast<uint32_t>(id), gain_db);
}

void LbAudioMixer::close_stream(int64_t id) {
	mixer_->close_stream(static_cast<uint32_t>(id));
}

int64_t LbAudioMixer::queued(int64_t id) const {
	return static_cast<int64_t>(mixer_->queued(static_cast<uint32_t>(id)));
}

bool LbAudioMixer::remove(int64_t id) {
	return mixer_->remove(static_cast<uint32_t>(id));
}

bool LbAudioMixer::has(int64_t id) const {
	return mixer_->has(static_cast<uint32_t>(id));
}

void LbAudioMixer::move(int64_t id, double x, double y) {
	mixer_->move(static_cast<uint32_t>(id), x, y);
}

int64_t LbAudioMixer::count() const {
	return static_cast<int64_t>(mixer_->count());
}

PackedVector2Array LbAudioMixer::mix(int64_t group, int64_t frames) {
	PackedVector2Array out;
	if (frames <= 0) {
		return out;
	}
	std::vector<float> buf(static_cast<size_t>(frames) * 2);
	mixer_->mix(static_cast<uint8_t>(group & 0xFF), buf.data(), static_cast<size_t>(frames));
	out.resize(frames);
	for (int64_t i = 0; i < frames; i++) {
		out[i] = Vector2(buf[static_cast<size_t>(i) * 2], buf[static_cast<size_t>(i) * 2 + 1]);
	}
	return out;
}

double LbAudioMixer::azimuth_of(int64_t id) const {
	return mixer_->azimuth_of(static_cast<uint32_t>(id));
}

double LbAudioMixer::rear_cutoff_of(int64_t id) const {
	return mixer_->rear_cutoff_of(static_cast<uint32_t>(id));
}

#ifdef LB_DEBUG_TOOLS
void LbAudioMixer::set_screen_up(bool on) {
	mixer_->set_screen_up(on);
}
#endif

bool LbAudioMixer::is_screen_up() const {
	return mixer_->screen_up();
}

} // namespace lb::godot

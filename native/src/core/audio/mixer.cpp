#include "core/audio/mixer.h"

#include <algorithm>
#include <cmath>

namespace lb::core::audio {

uint32_t Mixer::add(const SourceDesc &d) {
	const uint32_t id = next_id_++;
	Source s;
	s.d = d;
	sources_.emplace(id, std::move(s));
	return id;
}

Mixer::~Mixer() {
	if (hrtf_) {
		for (auto &kv : sources_) {
			if (kv.second.hrtf_id != 0) {
				hrtf_->close(kv.second.hrtf_id);
			}
		}
	}
}

void Mixer::set_hrtf(std::shared_ptr<Hrtf> h) {
	for (auto &kv : sources_) {
		if (hrtf_ && kv.second.hrtf_id != 0) {
			hrtf_->close(kv.second.hrtf_id);
		}
		kv.second.hrtf_id = 0;
		kv.second.left.clear();
		kv.second.right.clear();
		kv.second.read = 0;
	}
	hrtf_ = std::move(h);
}

bool Mixer::remove(uint32_t id) {
	auto it = sources_.find(id);
	if (it == sources_.end()) {
		return false;
	}
	if (hrtf_ && it->second.hrtf_id != 0) {
		hrtf_->close(it->second.hrtf_id);
	}
	sources_.erase(it);
	return true;
}

float Mixer::next_sample(Source &s, double gain, double step, bool &finished) {
	const size_t n = s.d.samples.size();
	if (n == 0) {
		finished = true;
		return 0.0f;
	}
	if (s.cursor >= static_cast<double>(n - 1)) {
		if (s.d.loop) {
			s.cursor = std::fmod(s.cursor, static_cast<double>(n - 1 > 0 ? n - 1 : 1));
		} else {
			finished = true;
			return 0.0f;
		}
	}
	const size_t i0 = static_cast<size_t>(s.cursor);
	const double frac = s.cursor - static_cast<double>(i0);
	const double v = s.d.samples[i0] * (1.0 - frac) + s.d.samples[i0 + 1 < n ? i0 + 1 : i0] * frac;
	s.cursor += step;
	return s.rear.process(static_cast<float>(v * gain));
}

bool Mixer::mix_hrtf(Source &s, double az, double gain, float *out, size_t frames) {
	const size_t block = static_cast<size_t>(hrtf_->frame_size());
	const double step = s.d.rate / rate_;
	std::vector<float> in(block), l(block), r(block);
	while (s.left.size() - s.read < frames && !s.ended) {
		for (size_t i = 0; i < block; i++) {
			bool finished = false;
			in[i] = s.ended ? 0.0f : next_sample(s, gain, step, finished);
			if (finished) {
				s.ended = true;
				in[i] = 0.0f;
			}
		}
		hrtf_->process(s.hrtf_id, az, in.data(), l.data(), r.data());
		if (s.read > 0) {
			s.left.erase(s.left.begin(), s.left.begin() + static_cast<std::ptrdiff_t>(s.read));
			s.right.erase(s.right.begin(), s.right.begin() + static_cast<std::ptrdiff_t>(s.read));
			s.read = 0;
		}
		s.left.insert(s.left.end(), l.begin(), l.end());
		s.right.insert(s.right.end(), r.begin(), r.end());
	}
	const size_t take = std::min(frames, s.left.size() - s.read);
	const bool mono = mode_ == OutputMode::MONO;
	for (size_t f = 0; f < take; f++) {
		const float lv = s.left[s.read + f];
		const float rv = s.right[s.read + f];
		out[f * 2] += mono ? 0.5f * (lv + rv) : lv;
		out[f * 2 + 1] += mono ? 0.5f * (lv + rv) : rv;
	}
	s.read += take;
	return !(s.ended && s.read >= s.left.size());
}

void Mixer::move(uint32_t id, double x, double y) {
	auto it = sources_.find(id);
	if (it != sources_.end()) {
		it->second.d.x = x;
		it->second.d.y = y;
	}
}

Pose Mixer::listening_pose() const {
	Pose p = pose_;
	if (screen_up_) {
		p.facing_turns = 0.75;  // north: straight up the screen
	}
	return p;
}

double Mixer::azimuth_of(uint32_t id) const {
	auto it = sources_.find(id);
	if (it == sources_.end() || !it->second.d.positional) {
		return 0.0;
	}
	return azimuth_deg(listening_pose(), it->second.d.x, it->second.d.y);
}

double Mixer::rear_cutoff_of(uint32_t id) const {
	auto it = sources_.find(id);
	if (it == sources_.end() || !it->second.d.positional) {
		return 0.0;
	}
	return rear_cutoff_hz(azimuth_of(id), rear_);
}

void Mixer::mix(uint8_t group, float *out, size_t frames) {
	for (size_t i = 0; i < frames * 2; i++) {
		out[i] = 0.0f;
	}
	const Pose pose = listening_pose();
	for (auto it = sources_.begin(); it != sources_.end();) {
		Source &s = it->second;
		if (s.d.group != group) {
			++it;
			continue;
		}
		const double az = s.d.positional ? azimuth_deg(pose, s.d.x, s.d.y) : 0.0;
		s.rear.set(s.d.positional ? rear_cutoff_hz(az, rear_) : 0.0, rate_);
		const double gain = std::pow(10.0, s.d.gain_db / 20.0);  // determinism: allow (client audio output, never sim state)
		if (s.d.positional && hrtf_ && mode_ != OutputMode::SPEAKERS) {
			if (s.hrtf_id == 0) {
				s.hrtf_id = hrtf_->open();
			}
			if (s.hrtf_id != 0) {
				if (mix_hrtf(s, az, gain, out, frames)) {
					++it;
				} else {
					hrtf_->close(s.hrtf_id);
					it = sources_.erase(it);
				}
				continue;
			}
		}
		double gl = 0.7071067811865476, gr = 0.7071067811865476;
		Binaural b;
		size_t delay_samples = 0;
		if (s.d.positional && mode_ == OutputMode::SPEAKERS) {
			const auto g = pan_gains(az);
			gl = g.first;
			gr = g.second;
		} else if (s.d.positional && mode_ == OutputMode::HEADPHONES) {
			b = binaural(az);
			delay_samples = static_cast<size_t>(std::lround(b.itd_s * rate_));
			s.shadow.set(b.far_cutoff_hz, rate_);
		}
		const double step = s.d.rate / rate_;
		bool finished = false;
		for (size_t f = 0; f < frames; f++) {
			const float x = next_sample(s, gain, step, finished);
			if (finished) {
				break;
			}
			float l = 0.0f, r = 0.0f;
			if (s.d.positional && mode_ == OutputMode::HEADPHONES) {
				s.delay.push_back(x);
				while (s.delay.size() > delay_samples + 1) {
					s.delay.pop_front();  // the source swung toward the centre: the far ear catches up
				}
				float far = 0.0f;
				if (s.delay.size() > delay_samples) {
					far = s.delay.front();
					s.delay.pop_front();
				}
				const float shadowed = static_cast<float>(s.shadow.process(far) * b.far_gain);
				l = b.left_near ? x : shadowed;
				r = b.left_near ? shadowed : x;
			} else {
				l = static_cast<float>(x * gl);
				r = static_cast<float>(x * gr);
			}
			out[f * 2] += l;
			out[f * 2 + 1] += r;
		}
		if (finished) {
			it = sources_.erase(it);
		} else {
			++it;
		}
	}
}

} // namespace lb::core::audio

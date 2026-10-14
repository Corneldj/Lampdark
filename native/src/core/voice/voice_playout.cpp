#include "core/voice/voice_playout.h"

#include <algorithm>
#include <cmath>
#include <cstring>

#include "core/voice/opus_codec.h"
#include "core/voice/voice_wire.h"

namespace lb::core::voice {

namespace {

BandParams level_params(const PlayoutParams &p) {
	BandParams b;
	b.low_hz = p.speech_low_hz;
	b.high_hz = p.speech_high_hz;
	b.median_frames = 1;
	b.hysteresis_frames = 1;
	b.thresholds_dbfs = {-1e9, -1e9, -1e9, -1e9};
	return b;
}

// An RBJ biquad (Q = 1/sqrt(2)), as {b0, b1, b2, a1, a2}.
void biquad(double rate, double hz, bool high, double *c) {
	const double w = 2.0 * 3.14159265358979323846 * hz / rate;
	const double cw = std::cos(w); // determinism: allow (client voice playback, never sim state)
	const double alpha = std::sin(w) / (2.0 * 0.70710678118654752440); // determinism: allow (client voice playback)
	const double a0 = 1.0 + alpha;
	c[0] = (high ? (1.0 + cw) : (1.0 - cw)) / 2.0 / a0;
	c[1] = (high ? -(1.0 + cw) : (1.0 - cw)) / a0;
	c[2] = c[0];
	c[3] = -2.0 * cw / a0;
	c[4] = (1.0 - alpha) / a0;
}

double db_to_lin(double db) {
	return std::pow(10.0, db / 20.0); // determinism: allow (client voice playback)
}

} // namespace

VoicePlayout::VoicePlayout(const PlayoutParams &p) : params_(p), jitter_(p.jitter), decoder_(std::make_unique<OpusVoiceDecoder>()), level_(level_params(p)) {
	biquad(48000.0, p.telephone_low_hz, true, tel_b_[0]);
	biquad(48000.0, p.telephone_high_hz, false, tel_b_[1]);
}

VoicePlayout::~VoicePlayout() = default;

bool VoicePlayout::push(const uint8_t *packet, size_t size, int64_t now_us) {
	if (packet == nullptr || size < static_cast<size_t>(wire::DOWN_HEADER)) {
		return false;
	}
	const uint16_t seq = static_cast<uint16_t>(packet[2] | (packet[3] << 8));
	const uint8_t head = packet[4];
	if ((head & wire::BAND_MASK) > wire::MAX_BAND) {
		return false;
	}
	gain_db_ = static_cast<int8_t>(packet[5]);
	treat_ = packet[6];
	flags_ = head & (wire::MUFFLED | wire::TELEPHONE | wire::DRY);
	int32_t x = 0, y = 0;
	for (int i = 0; i < 4; i++) {
		x |= static_cast<int32_t>(packet[7 + i]) << (8 * i);
		y |= static_cast<int32_t>(packet[11 + i]) << (8 * i);
	}
	x16_ = x;
	y16_ = y;
	return jitter_.push(seq, head, packet + wire::DOWN_HEADER, size - wire::DOWN_HEADER, now_us);
}

void VoicePlayout::cap(std::vector<float> &pcm, int band, double &cut_db) {
	cut_db = 0.0;
	level_.push(pcm.data(), pcm.size());
	// Aimed half a dB under the cap: the speech filter's carry-over from the frame before can lift a
	// frame's measured level by a tenth of a dB, and the cap is a ceiling, never a target.
	const double limit = params_.cap_dbfs[std::clamp(band, 1, 4)] - 0.5;
	const double over = level_.level_dbfs() - limit;
	if (over > 0.0) {
		const float g = static_cast<float>(db_to_lin(-over));
		for (float &v : pcm) {
			v *= g;
		}
		cut_db = over;
	}
}

void VoicePlayout::telephone(std::vector<float> &pcm) {
	const double hiss = db_to_lin(params_.hiss_dbfs) * 1.7320508; // uniform noise: RMS = amplitude / sqrt(3)
	for (float &v : pcm) {
		double x = v;
		for (int f = 0; f < 2; f++) {
			const double *c = tel_b_[f];
			const double y = c[0] * x + tel_z_[f * 2];
			tel_z_[f * 2] = c[1] * x - c[3] * y + tel_z_[f * 2 + 1];
			tel_z_[f * 2 + 1] = c[2] * x - c[4] * y;
			x = y;
		}
		noise_ = noise_ * 1664525u + 1013904223u;
		x += hiss * (static_cast<double>(noise_ >> 8) / 8388608.0 - 1.0);
		v = static_cast<float>(x);
	}
}

// SND-08's treatment: the distance muffle (a low-pass falling from muffle_max_hz to muffle_min_hz
// as the muffle rises) and the Stythe's crackle (sparse decaying pops under the voice, like a
// guttering wick).
void VoicePlayout::treat(std::vector<float> &pcm) {
	const double m = muffle();
	if (m > 0.0) {
		const double ratio = params_.muffle_min_hz / params_.muffle_max_hz;
		const double fc = params_.muffle_max_hz * std::pow(ratio, m); // determinism: allow (client voice playback)
		const double a = 1.0 - std::exp(-2.0 * 3.14159265358979323846 * fc / 48000.0); // determinism: allow (client voice playback)
		for (float &v : pcm) {
			muffle_lp_ += a * (v - muffle_lp_);
			v = static_cast<float>(muffle_lp_);
		}
	}
	if (crackle()) {
		const double amp = db_to_lin(params_.crackle_dbfs) * 4.0;
		for (float &v : pcm) {
			noise_ = noise_ * 1664525u + 1013904223u;
			if ((noise_ >> 20) < 6) { // a pop about every 350 samples
				crackle_env_ = 1.0;
			}
			crackle_env_ *= 0.985;
			noise_ = noise_ * 1664525u + 1013904223u;
			v += static_cast<float>(amp * crackle_env_ * (static_cast<double>(noise_ >> 8) / 8388608.0 - 1.0));
		}
	}
}

// Quiet, darkened room tone at the smear level; fading in when it starts.
std::vector<float> VoicePlayout::smear(bool fade_in) {
	std::vector<float> out(OPUS_FRAME);
	const double amp = db_to_lin(params_.smear_dbfs) * 1.7320508 * 4.0; // the low-pass takes ~12 dB
	for (int i = 0; i < OPUS_FRAME; i++) {
		noise_ = noise_ * 1664525u + 1013904223u;
		const double w = static_cast<double>(noise_ >> 8) / 8388608.0 - 1.0;
		smear_lp_ += 0.06 * (w - smear_lp_);
		const double fade = fade_in ? static_cast<double>(i) / OPUS_FRAME : 1.0;
		out[i] = static_cast<float>(amp * smear_lp_ * fade);
	}
	return out;
}

std::vector<VoicePlayout::Out> VoicePlayout::pop(int64_t now_us) {
	std::vector<Out> outs;
	JitterBuffer::Out j;
	while (jitter_.pop(now_us, j)) {
		Out o;
		o.head = j.head;
		if (j.kind == JitterBuffer::Kind::END) {
			o.kind = Kind::END;
			outs.push_back(std::move(o));
			break;
		}
		if (j.kind == JitterBuffer::Kind::FRAME && (j.head & wire::PROBE)) {
			// NET-12's marked frame: timed at playout, never decoded or heard.
			int64_t t0 = 0;
			if (j.payload.size() >= 8) {
				std::memcpy(&t0, j.payload.data(), 8);
			}
			o.probe_t0_us = t0;
			o.pcm.assign(OPUS_FRAME, 0.0f);
			outs.push_back(std::move(o));
			continue;
		}
		const int band = j.kind == JitterBuffer::Kind::FRAME ? (j.head & wire::BAND_MASK) : last_band_;
		if (j.kind == JitterBuffer::Kind::FRAME) {
			o.kind = Kind::FRAME;
			o.pcm = decoder_->decode(j.payload.data(), j.payload.size());
			if (o.pcm.empty()) {
				o.kind = Kind::CONCEAL;
				o.pcm = decoder_->conceal();
			}
			last_band_ = std::max(1, band);
			if (smearing_) {
				// Back from a smear: the voice fades in over the room tone.
				const std::vector<float> tail = smear(false);
				for (int i = 0; i < OPUS_FRAME && i < static_cast<int>(o.pcm.size()); i++) {
					const float k = static_cast<float>(i) / OPUS_FRAME;
					o.pcm[i] = o.pcm[i] * k + tail[i] * (1.0f - k);
				}
				smearing_ = false;
			}
		} else if (j.lost_run <= 1) {
			o.kind = Kind::CONCEAL;
			o.pcm = decoder_->conceal();
		} else {
			o.kind = Kind::SMEAR;
			o.pcm = smear(!smearing_);
			smearing_ = true;
		}
		if (o.kind != Kind::SMEAR) {
			cap(o.pcm, last_band_, o.cap_gain_db);
			if (flags_ & wire::TELEPHONE) {
				telephone(o.pcm);
			}
		}
		treat(o.pcm);
		outs.push_back(std::move(o));
	}
	return outs;
}

} // namespace lb::core::voice

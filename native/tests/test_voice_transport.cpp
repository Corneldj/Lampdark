// SND-07: the voice transport's native parts. The forwarder (fan-out with per-listener headers,
// nothing kept, no ids, bands 5-7 refused), the jitter buffer (playout time, late frames, loss
// runs, the end), the playout (concealment, smears, the band cap, probe frames), and the mixer's
// streams.

#include "doctest.h"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <vector>

#include "core/audio/mixer.h"
#include "core/voice/jitter_buffer.h"
#include "core/voice/opus_codec.h"
#include "core/voice/voice_forwarder.h"
#include "core/voice/voice_playout.h"
#include "core/voice/voice_wire.h"
#include "voice_signals.h"

using namespace lb::core::voice;
namespace w = lb::core::voice::wire;

namespace {

std::vector<uint8_t> up(uint16_t seq, int band, uint8_t flags, const std::vector<uint8_t> &opus) {
	std::vector<uint8_t> b = {static_cast<uint8_t>(seq & 0xFF), static_cast<uint8_t>(seq >> 8), static_cast<uint8_t>(band | flags)};
	b.insert(b.end(), opus.begin(), opus.end());
	return b;
}

JitterParams jp() {
	JitterParams p;
	p.frame_ms = 20;
	p.min_ms = 40;
	p.max_ms = 120;
	p.start_ms = 60;
	return p;
}

PlayoutParams pp() {
	PlayoutParams p;
	p.jitter = jp();
	p.speech_low_hz = 300.0;
	p.speech_high_hz = 3400.0;
	p.cap_dbfs = {0.0, -34.0, -16.0, -6.0, -1.0};
	p.smear_dbfs = -60.0;
	p.hiss_dbfs = -50.0;
	return p;
}

// A downstream packet as the forwarder makes it.
std::vector<uint8_t> down(uint16_t seq, int band, uint8_t flags, const std::vector<uint8_t> &opus) {
	VoiceForwarder f;
	VoiceRoute r;
	r.listener = 1;
	r.stream = 77;
	r.flags = flags & (w::MUFFLED | w::TELEPHONE | w::DRY);
	f.set_routes(0, {r});
	const auto out = f.forward(0, up(seq, band, flags & w::UP_FLAGS, opus).data(), up(seq, band, flags & w::UP_FLAGS, opus).size());
	return out.at(0).second;
}

} // namespace

TEST_CASE("SND-07: the forwarder fans a frame out with each listener's header and keeps nothing") {
	VoiceForwarder f;
	VoiceRoute a;
	a.listener = 2;
	a.stream = 0x1234;
	a.gain_db = -6;
	a.flags = w::MUFFLED;
	a.x16 = 10 * 16 + 8;
	a.y16 = -3 * 16;
	VoiceRoute b;
	b.listener = 3;
	b.stream = 0x0BEE;
	f.set_routes(0, {a, b});
	const std::vector<uint8_t> opus = {9, 8, 7, 6, 5};
	const std::vector<uint8_t> pkt = up(513, 2, 0, opus);
	const auto out = f.forward(0, pkt.data(), pkt.size());
	REQUIRE(out.size() == 2);
	CHECK(out[0].first == 2);
	const std::vector<uint8_t> &d = out[0].second;
	CHECK(d.size() == static_cast<size_t>(w::DOWN_HEADER) + opus.size());
	CHECK((d[0] | (d[1] << 8)) == 0x1234); // stream
	CHECK((d[2] | (d[3] << 8)) == 513); // seq
	CHECK((d[4] & w::BAND_MASK) == 2);
	CHECK((d[4] & w::MUFFLED) != 0);
	CHECK(static_cast<int8_t>(d[5]) == -6);
	CHECK(std::vector<uint8_t>(d.end() - 5, d.end()) == opus); // the Opus bytes untouched
	CHECK(out[1].first == 3);
	CHECK((out[1].second[0] | (out[1].second[1] << 8)) == 0x0BEE);
	// The downstream header is exactly: stream, seq, head, gain, crackle, x, y. No speaker, no entity.
	CHECK(w::DOWN_HEADER == 2 + 2 + 1 + 1 + 1 + 4 + 4);
}

TEST_CASE("QA-01: the forwarder's counts are audio frames only; an END goes through uncounted") {
	VoiceForwarder f;
	VoiceRoute r;
	r.listener = 4;
	r.stream = 9;
	f.set_routes(0, {r});
	const std::vector<uint8_t> opus = {1, 2, 3};
	for (uint16_t seq = 0; seq < 5; ++seq) {
		const std::vector<uint8_t> pkt = up(seq, 2, 0, opus);
		CHECK(f.forward(0, pkt.data(), pkt.size()).size() == 1);
	}
	const std::vector<uint8_t> end = up(5, 2, w::END, {});
	CHECK(f.forward(0, end.data(), end.size()).size() == 1); // the END still closes the stream
	const auto counts = f.counts(0);
	REQUIRE(counts.count(4) == 1);
	CHECK(counts.at(4).seen == 5);
	CHECK(counts.at(4).sent == 5);
}

TEST_CASE("RSC-04: a route's band cap: a shout forced to a whisper says whisper in its header") {
	VoiceForwarder f;
	VoiceRoute capped;
	capped.listener = 1;
	capped.flags = w::MUFFLED;
	capped.band_cap = 1;
	VoiceRoute open;
	open.listener = 2;
	f.set_routes(0, {capped, open});
	const std::vector<uint8_t> shout = up(1, 3, 0, {4, 5});
	const auto out = f.forward(0, shout.data(), shout.size());
	REQUIRE(out.size() == 2);
	CHECK((out[0].second[4] & w::BAND_MASK) == 1);
	CHECK((out[0].second[4] & w::MUFFLED) != 0);
	CHECK((out[1].second[4] & w::BAND_MASK) == 3); // an uncapped route keeps the speaker's band
	const std::vector<uint8_t> whisper = up(2, 1, 0, {4, 5});
	CHECK((f.forward(0, whisper.data(), whisper.size()).at(0).second[4] & w::BAND_MASK) == 1);
}

TEST_CASE("SND-07: bands 5-7 and malformed packets are refused") {
	VoiceForwarder f;
	VoiceRoute r;
	r.listener = 1;
	f.set_routes(0, {r});
	for (int band = 5; band <= 7; band++) {
		const auto pkt = up(1, band, 0, {1, 2});
		CHECK_FALSE(VoiceForwarder::parse(pkt.data(), pkt.size()).valid);
		CHECK(f.forward(0, pkt.data(), pkt.size()).empty());
	}
	const uint8_t short_pkt[2] = {1, 0};
	CHECK_FALSE(VoiceForwarder::parse(short_pkt, 2).valid);
	const auto bad_flags = up(1, 1, 0x40, {1}); // a downstream-only flag sent upstream
	CHECK_FALSE(VoiceForwarder::parse(bad_flags.data(), bad_flags.size()).valid);
	const auto ok = up(1, 4, w::END, {});
	CHECK(VoiceForwarder::parse(ok.data(), ok.size()).valid);
	CHECK(f.forward(9, ok.data(), ok.size()).empty()); // a speaker without routes reaches nobody
}

TEST_CASE("SND-07: the jitter buffer plays frame k at the first arrival plus the target plus k frames") {
	JitterBuffer j(jp());
	const uint8_t x = 0;
	CHECK(j.push(100, 1, &x, 1, 1'000'000));
	CHECK(j.push(102, 1, &x, 1, 1'030'000)); // 101 is missing for now
	JitterBuffer::Out o;
	CHECK_FALSE(j.pop(1'059'000, o)); // not yet: 60 ms after the first arrival
	CHECK(j.pop(1'060'000, o));
	CHECK(o.kind == JitterBuffer::Kind::FRAME);
	CHECK(o.seq == 100);
	CHECK(j.push(101, 1, &x, 1, 1'070'000)); // arrives before its time (1.080 s)
	CHECK(j.pop(1'080'000, o));
	CHECK(o.seq == 101);
	CHECK(o.kind == JitterBuffer::Kind::FRAME);
	CHECK(j.pop(1'100'000, o));
	CHECK(o.seq == 102);
	CHECK(j.pop(1'120'000, o));
	CHECK(o.kind == JitterBuffer::Kind::LOST);
	CHECK(o.lost_run == 1);
	CHECK_FALSE(j.push(103, 1, &x, 1, 1'121'000)); // its time has passed: dropped, never played late
	CHECK(j.pop(1'140'000, o));
	CHECK(o.lost_run == 2);
	CHECK(j.push(105, w::END, nullptr, 0, 1'141'000));
	CHECK(j.pop(1'160'000, o));
	CHECK(o.kind == JitterBuffer::Kind::END);
	CHECK(j.done());
}

TEST_CASE("SND-07: the next stream's target follows the measured jitter, within 40-120 ms") {
	CHECK(JitterBuffer::suggest_ms(0.0, jp()) == 40);
	CHECK(JitterBuffer::suggest_ms(15.0, jp()) == 50);
	CHECK(JitterBuffer::suggest_ms(80.0, jp()) == 120);
	JitterBuffer j(jp());
	const uint8_t x = 0;
	// Arrivals 20 ms apart, wobbling by 10 ms: a jitter of a few ms.
	for (int k = 0; k < 50; k++) {
		j.push(static_cast<uint16_t>(k), 1, &x, 1, 1'000'000 + k * 20'000 + (k % 2) * 10'000);
	}
	CHECK(j.jitter_ms() > 5.0);
	CHECK(j.jitter_ms() < 12.0);
}

TEST_CASE("SND-07: a whisper-tagged frame recorded at -10 dBFS plays at -34 dBFS or less") {
	// Speech-band noise at -10 dBFS, encoded, sent as a whisper, played: the cap holds it down.
	std::vector<float> loud(OPUS_FRAME * 10);
	{
		voice_signals::Lcg r(5);
		for (float &v : loud) {
			v = r.next();
		}
	}
	OpusVoiceEncoder enc(24000, true);
	VoicePlayout play(pp());
	BandParams bp;
	bp.low_hz = 300.0;
	bp.high_hz = 3400.0;
	bp.thresholds_dbfs = {-50, -40, -22, -12};
	BandMeter in(bp), out(bp);
	int64_t now = 1'000'000;
	double worst = -200.0;
	double raw = -200.0;
	for (int f = 0; f < 10; f++) {
		std::vector<float> frame(loud.begin() + f * OPUS_FRAME, loud.begin() + (f + 1) * OPUS_FRAME);
		// Scale the frame's speech band to -10 dBFS.
		in.push(frame.data(), frame.size());
		const double g = std::pow(10.0, (-10.0 - in.level_dbfs()) / 20.0);
		for (float &v : frame) {
			v = static_cast<float>(v * g);
		}
		const std::vector<uint8_t> packet = enc.encode(frame.data());
		REQUIRE_FALSE(packet.empty());
		const auto pkt = down(static_cast<uint16_t>(f), 1, 0, packet);
		CHECK(play.push(pkt.data(), pkt.size(), now));
		now += 20'000;
	}
	for (const auto &o : play.pop(now + 1'000'000)) {
		if (o.kind == VoicePlayout::Kind::FRAME) {
			out.push(o.pcm.data(), o.pcm.size());
			worst = std::max(worst, out.level_dbfs());
			raw = std::max(raw, out.level_dbfs() + o.cap_gain_db);
		}
	}
	std::printf("    whisper frame: decoded at %.1f dBFS, played at %.1f dBFS\n", raw, worst);
	CHECK(raw > -20.0); // it really was loud
	CHECK(worst <= -34.0);
}

TEST_CASE("SND-07: one lost frame is concealed; a longer run smears into room tone and fades back") {
	OpusVoiceEncoder enc(24000, true);
	VoicePlayout play(pp());
	const std::vector<float> talk = voice_signals::speechlike(OPUS_FRAME * 12, 3, 0.2f);
	int64_t now = 1'000'000;
	std::vector<VoicePlayout::Kind> kinds;
	for (int f = 0; f < 12; f++) {
		const auto opus = enc.encode(talk.data() + f * OPUS_FRAME);
		if (f != 3 && (f < 6 || f > 8)) { // frame 3 lost; frames 6-8 lost
			const auto pkt = down(static_cast<uint16_t>(f), 2, 0, opus);
			play.push(pkt.data(), pkt.size(), now);
		}
		now += 20'000;
		for (const auto &o : play.pop(now)) {
			kinds.push_back(o.kind);
		}
	}
	for (const auto &o : play.pop(now + 120'000)) {
		kinds.push_back(o.kind);
		if (o.kind == VoicePlayout::Kind::SMEAR) {
			double e = 0.0;
			for (float v : o.pcm) {
				e += v * v;
			}
			CHECK(10.0 * std::log10(e / o.pcm.size() + 1e-20) < -50.0); // quiet room tone, never a glitch
		}
	}
	REQUIRE(kinds.size() >= 12);
	CHECK(kinds[3] == VoicePlayout::Kind::CONCEAL);
	CHECK(kinds[6] == VoicePlayout::Kind::CONCEAL);
	CHECK(kinds[7] == VoicePlayout::Kind::SMEAR);
	CHECK(kinds[8] == VoicePlayout::Kind::SMEAR);
	CHECK(kinds[9] == VoicePlayout::Kind::FRAME);
}

TEST_CASE("SND-07: a probe frame carries its send time to playout and is never decoded") {
	VoicePlayout play(pp());
	int64_t t0 = 123456789;
	std::vector<uint8_t> payload(8);
	std::memcpy(payload.data(), &t0, 8);
	const auto pkt = down(0, 1, w::PROBE, payload);
	CHECK(play.push(pkt.data(), pkt.size(), 1'000'000));
	const auto outs = play.pop(1'060'000);
	REQUIRE(outs.size() == 1);
	CHECK(outs[0].probe_t0_us == t0);
}

TEST_CASE("SND-07: a mixer stream plays what is appended, waits when starved, and ends once closed and drained") {
	lb::core::audio::Mixer m(48000.0);
	lb::core::audio::SourceDesc d;
	d.rate = 48000.0;
	d.streaming = true;
	d.positional = false;
	d.group = 4;
	const uint32_t id = m.add(d);
	std::vector<float> out(2 * 480);
	m.mix(4, out.data(), 480);
	CHECK(m.has(id)); // starved: still there
	const std::vector<float> one(960, 0.5f);
	CHECK(m.append(id, one.data(), one.size()));
	CHECK(m.queued(id) > 900);
	m.mix(4, out.data(), 480);
	CHECK(std::fabs(out[100]) > 0.1f);
	m.close_stream(id);
	CHECK_FALSE(m.append(id, one.data(), one.size())); // closed: no more
	m.mix(4, out.data(), 480);
	m.mix(4, out.data(), 480);
	CHECK_FALSE(m.has(id));
}

// SND-05: what the capture hands SND-06: 48 kHz mono, 20 ms (960-sample) frames, timestamped, from
// device callbacks of any size; the open and close rules at the native layer; nothing left behind
// after close; the far end resampled from the game's mix rate; and the real miniaudio path on its
// null device.

#include <cstdlib>
#include "doctest.h"

#include <chrono>
#include <thread>

#include "core/voice/mic_capture.h"
#include "voice_signals.h"

using namespace lb::core::voice;

namespace {

ProcessorParams params(ApmBackend b) {
	ProcessorParams p;
	p.backend = b;
	p.speex_echo_tail_ms = 100.0;
	const double db[4] = {-10.0, -15.0, -22.0, -30.0};
	for (int i = 0; i < 4; i++) {
		p.speex_suppress_db[i] = db[i];
	}
	return p;
}

struct Rig {
	FakeCaptureDriver *fake = nullptr;
	std::unique_ptr<MicCapture> mic;
	explicit Rig(ApmBackend b = ApmBackend::WEBRTC) {
		auto d = std::make_unique<FakeCaptureDriver>();
		fake = d.get();
		fake->add_device("usb-1", "USB headset", true);
		mic = std::make_unique<MicCapture>(std::move(d));
		REQUIRE(mic->configure(params(b)));
	}
};

} // namespace

TEST_CASE("SND-05: odd-sized device callbacks come out as whole 20 ms frames, in order and timestamped") {
	Rig rig(ApmBackend::NONE);
	REQUIRE(rig.mic->open(""));
	std::vector<float> s(48000);
	for (size_t i = 0; i < s.size(); i++) {
		s[i] = static_cast<float>(i % 1000) / 1000.0f;
	}
	// 1 s in callbacks of 441, 512 and 37 samples, drained as the game would, between callbacks.
	const uint32_t sizes[3] = {441, 512, 37};
	size_t at = 0;
	int frames = 0;
	int64_t last = 0;
	bool in_order = true;
	CaptureFrame f;
	size_t sample = 0;
	for (int k = 0; at < s.size(); k++) {
		const uint32_t n = std::min<uint32_t>(sizes[k % 3], static_cast<uint32_t>(s.size() - at));
		REQUIRE(rig.fake->feed(s.data() + at, n));
		at += n;
		while (rig.mic->pop_frame(f)) {
			CHECK(f.steady_usec >= last);
			last = f.steady_usec;
			for (int i = 0; i < CAPTURE_FRAME; i++) {
				in_order = in_order && f.pcm[i] == s[sample++];
			}
			frames++;
		}
	}
	CHECK(frames == 48000 / CAPTURE_FRAME); // 50 frames a second
	CHECK(in_order); // the pass-through backend: samples untouched, none lost
	CHECK(CAPTURE_FRAME == 960);
	CHECK(CAPTURE_RATE == 48000);
}

TEST_CASE("SND-05: open counts, close zeroes everything, and a closed device yields nothing") {
	Rig rig;
	CHECK(rig.mic->open_count() == 0);
	REQUIRE(rig.mic->open(""));
	CHECK(rig.mic->device_id() == "usb-1");
	const std::vector<float> talk = voice_signals::speechlike(4800, 5, 0.3f);
	rig.fake->feed(talk.data(), static_cast<uint32_t>(talk.size()));
	const std::vector<float> far = voice_signals::speechlike(4410 * 2, 6, 0.3f);
	rig.mic->push_far_end_stereo(far.data(), 4410, 44100);
	CHECK_FALSE(rig.mic->buffers_zeroed());
	rig.mic->close();
	CHECK(rig.mic->buffers_zeroed());
	CaptureFrame f;
	CHECK_FALSE(rig.mic->pop_frame(f));
	CHECK_FALSE(rig.fake->feed(talk.data(), 480)); // the device is closed
	CHECK(rig.mic->open(""));
	CHECK(rig.mic->open("")); // already open: no second open
	CHECK(rig.mic->open_count() == 2);
}

TEST_CASE("SND-05: an unplugged device is lost and stops frames; a different device can open") {
	Rig rig;
	REQUIRE(rig.mic->open(""));
	CHECK_FALSE(rig.mic->lost());
	rig.fake->remove_device("usb-1");
	CHECK(rig.mic->lost());
	const float s[480] = {};
	CHECK_FALSE(rig.fake->feed(s, 480));
	rig.mic->close();
	CHECK_FALSE(rig.mic->open("")); // no device at all
	rig.fake->add_device("bt-2", "Bluetooth headset", true);
	REQUIRE(rig.mic->open(""));
	CHECK(rig.mic->device_id() == "bt-2");
}

TEST_CASE("SND-05: the far end at the game's mix rate is resampled to 48 kHz") {
	Rig rig(ApmBackend::NONE);
	REQUIRE(rig.mic->open(""));
	// 0.5 s of 44.1 kHz stereo in 15 game frames (the ring holds about 0.68 s at 48 kHz).
	std::vector<float> st(44100 * 2, 0.25f);
	for (int k = 0; k < 15; k++) {
		rig.mic->push_far_end_stereo(st.data() + k * 1470 * 2, 1470, 44100);
	}
	// About 24,000 samples queued (the resampler holds a few back): all fit, none dropped. Then the
	// microphone's next 1 s drains them, 480 at a time, as its blocks come.
	CHECK(rig.mic->dropped_far_end() == 0);
	std::vector<float> s(480, 0.0f);
	CaptureFrame f;
	for (int k = 0; k < 100; k++) {
		rig.fake->feed(s.data(), 480);
		while (rig.mic->pop_frame(f)) {
		}
	}
	CHECK(rig.mic->dropped_frames() == 0);
}

TEST_CASE("SND-05: processing stays well inside the 30 ms budget per 10 ms block") {
	Rig rig;
	REQUIRE(rig.mic->open(""));
	const std::vector<float> talk = voice_signals::speechlike(48000 * 3, 5, 0.3f);
	const std::vector<float> far = voice_signals::speechlike(48000 * 3, 6, 0.3f);
	for (size_t at = 0; at + 480 <= talk.size(); at += 480) {
		rig.mic->push_far_end(far.data() + at, 480);
		rig.fake->feed(talk.data() + at, 480);
	}
	const double p95 = rig.mic->processing_us_p95();
	std::printf("    webrtc processing per 10 ms block: p95 %.0f us\n", p95);
	CHECK(p95 > 0.0);
	if (std::getenv("LB_TIMING_REPORT_ONLY") == nullptr) { // FND-04: reported on CI's shared runners
		CHECK(p95 < 5000.0);
	}
}

TEST_CASE("SND-05: miniaudio's null device runs the real driver path: open, frames, close") {
	auto drv = make_null_miniaudio_driver();
	auto *raw = drv.get();
	MicCapture mic(std::move(drv));
	REQUIRE(mic.configure(params(ApmBackend::WEBRTC)));
	CHECK_FALSE(mic.devices().empty());
	REQUIRE(mic.open(""));
	CHECK_FALSE(raw->opened_id().empty());
	CHECK(mic.device_latency_ms() > 0.0);
	CaptureFrame f;
	int frames = 0;
	for (int i = 0; i < 100 && frames < 3; i++) {
		std::this_thread::sleep_for(std::chrono::milliseconds(10));
		while (mic.pop_frame(f)) {
			frames++;
		}
	}
	CHECK(frames >= 3);
	mic.close();
	CHECK(mic.buffers_zeroed());
	CHECK(mic.open_count() == 1);
}

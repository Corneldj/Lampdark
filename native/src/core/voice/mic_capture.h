#pragma once
// SND-05: the microphone, from device to clean 20 ms frames. A CaptureDriver opens the default
// (or a named) input in shared mode at 48 kHz mono: miniaudio on the real thing, with WASAPI's raw
// stream where Windows allows it; a fake for tests. Its callback runs on the device's thread: the
// samples go in 10 ms blocks through the VoiceProcessor (echo cancelling against the far-end ring
// the game fills, then noise suppression) and come out as timestamped 20 ms frames on a ring the
// game drains. Nothing is ever written to disk, a log or the network here; the rings are zeroed
// when the device closes. Engine-free.

#include <algorithm>
#include <atomic>
#include <iterator>
#include <cstdint>
#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

#include "core/voice/ring_buffer.h"
#include "core/voice/voice_processor.h"

struct SpeexResamplerState_;

namespace lb::core::voice {

struct CaptureDevice {
	std::string id; // stable across enumerations of the same device
	std::string name;
	bool is_default = false;
};

class CaptureDriver {
public:
	// 48 kHz mono samples, on the device's thread.
	using DataFn = std::function<void(const float *samples, uint32_t count)>;
	// The device went away (unplugged, disabled, access revoked), on any thread.
	using LostFn = std::function<void()>;
	virtual ~CaptureDriver() = default;
	virtual std::vector<CaptureDevice> devices() = 0;
	// `id` empty: the system default. True once the device runs.
	virtual bool open(const std::string &id, DataFn on_data, LostFn on_lost) = 0;
	// Stops the device thread before returning.
	virtual void close() = 0;
	// The device actually opened (the default resolved), empty when closed.
	virtual std::string opened_id() const = 0;
	// Open and still running. A device that vanished stops running even when its backend sends no
	// notice (PulseAudio's killed stream; WASAPI's invalidated device).
	virtual bool alive() const = 0;
	// What the device adds before a callback, in milliseconds: one period (the latency budget).
	virtual double device_latency_ms() const = 0;
};

// The real devices, through miniaudio (WASAPI on Windows, PulseAudio or ALSA on Linux and Proton).
std::unique_ptr<CaptureDriver> make_miniaudio_driver();
// miniaudio's null device: silence from a device that always exists (tests of the real driver path).
std::unique_ptr<CaptureDriver> make_null_miniaudio_driver();

// Tests: devices are added and removed by hand, and samples fed synchronously as if from the device.
class FakeCaptureDriver final : public CaptureDriver {
public:
	void add_device(const std::string &id, const std::string &name, bool is_default = false);
	// Removes it; if it is open, the device is lost.
	void remove_device(const std::string &id);
	// Feeds samples through the open device's callback; false when closed.
	bool feed(const float *samples, uint32_t count);
	std::vector<CaptureDevice> devices() override;
	bool open(const std::string &id, DataFn on_data, LostFn on_lost) override;
	void close() override;
	std::string opened_id() const override { return opened_; }
	bool alive() const override { return !opened_.empty(); }
	double device_latency_ms() const override { return 10.0; }

private:
	std::vector<CaptureDevice> devices_;
	std::string opened_;
	DataFn on_data_;
	LostFn on_lost_;
};

struct CaptureFrame {
	float pcm[CAPTURE_FRAME] = {};
	int64_t steady_usec = 0; // std::chrono::steady_clock time the frame's last sample was processed
	bool operator==(const CaptureFrame &o) const {
		return steady_usec == o.steady_usec && std::equal(std::begin(pcm), std::end(pcm), std::begin(o.pcm));
	}
};

class MicCapture {
public:
	explicit MicCapture(std::unique_ptr<CaptureDriver> driver);
	~MicCapture();
	MicCapture(const MicCapture &) = delete;
	MicCapture &operator=(const MicCapture &) = delete;

	// Takes effect at the next open. False if the backend cannot start.
	bool configure(const ProcessorParams &params);
	std::vector<CaptureDevice> devices();
	// Opens `id` (empty: the default). Counts every successful open.
	bool open(const std::string &id);
	// Stops the device and zeroes every buffer it touched.
	void close();
	bool is_open() const { return open_; }
	// The open device went away; frames have stopped. Cleared by close().
	bool lost() const { return lost_.load(std::memory_order_acquire) || (open_ && driver_ && !driver_->alive()); }
	std::string device_id() const;
	uint64_t open_count() const { return open_count_; }

	// The game's final mix (interleaved stereo at `rate`), from the game thread: downmixed, resampled
	// to 48 kHz and queued as the echo canceller's far end. Ignored while closed.
	void push_far_end_stereo(const float *interleaved, uint32_t frames, uint32_t rate);
	// 48 kHz mono far end, already at the capture rate (tests).
	void push_far_end(const float *mono, uint32_t count);
	// The next clean frame, oldest first; false when none is waiting.
	bool pop_frame(CaptureFrame &out);

	// Measurements for the spike report and SND-05's latency budget.
	double device_latency_ms() const;
	double processing_us_p95() const;
	uint64_t dropped_frames() const; // clean frames the game did not drain in time
	uint64_t dropped_far_end() const; // far-end samples that found the ring full
	// SND-06's speakers warning: the processor's echo return loss, dB (< 0: unknown).
	double echo_return_loss_db() const { return erl_.load(std::memory_order_relaxed); }
	// Only for tests: every buffer is zero (after close()).
	bool buffers_zeroed() const;

private:
	void on_data(const float *samples, uint32_t count);

	std::unique_ptr<CaptureDriver> driver_;
	ProcessorParams params_;
	std::unique_ptr<VoiceProcessor> proc_;
	bool open_ = false;
	std::atomic<bool> lost_{false};
	std::atomic<double> erl_{-1.0};
	uint64_t open_count_ = 0;

	SpscRing<float> far_; // game thread -> device thread, 48 kHz mono
	SpscRing<CaptureFrame> frames_; // device thread -> game thread
	// Device-thread state.
	float block_[CAPTURE_BLOCK] = {};
	uint32_t block_fill_ = 0;
	float far_block_[CAPTURE_BLOCK] = {};
	CaptureFrame frame_{};
	uint32_t frame_fill_ = 0;
	std::vector<uint32_t> proc_us_; // the last processing times (device thread), read under stats_
	size_t proc_next_ = 0;
	mutable std::mutex stats_;
	// Game-thread state: the far end's resampler and downmix scratch.
	SpeexResamplerState_ *resampler_ = nullptr;
	uint32_t resampler_rate_ = 0;
	std::vector<float> mono_;
	std::vector<float> resampled_;
};

} // namespace lb::core::voice

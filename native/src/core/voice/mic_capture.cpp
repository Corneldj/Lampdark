#include "core/voice/mic_capture.h"

#include <algorithm>
#include <chrono>
#include <cstring>

#include "lb_miniaudio.h"
#include "speex/speex_resampler.h"

namespace lb::core::voice {

namespace {

int64_t steady_usec() {
	return std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now().time_since_epoch()).count();
}

// A device id as text: the backend's id bytes in hex, trailing zeros trimmed.
std::string id_text(const ma_device_id &id) {
	const auto *b = reinterpret_cast<const unsigned char *>(&id);
	size_t n = sizeof(ma_device_id);
	while (n > 0 && b[n - 1] == 0) {
		n--;
	}
	if (n == 0) {
		return "00"; // an all-zero id (the null device's) still names a device
	}
	static const char *hex = "0123456789abcdef";
	std::string out;
	out.reserve(n * 2);
	for (size_t i = 0; i < n; i++) {
		out.push_back(hex[b[i] >> 4]);
		out.push_back(hex[b[i] & 15]);
	}
	return out;
}

class MiniaudioDriver final : public CaptureDriver {
public:
	explicit MiniaudioDriver(bool null_backend) {
#if defined(_WIN32)
		ma_backend real[] = {ma_backend_wasapi};
		ma_uint32 real_count = 1;
#else
		ma_backend real[] = {ma_backend_pulseaudio, ma_backend_alsa};
		ma_uint32 real_count = 2;
#endif
		ma_backend null[] = {ma_backend_null};
		ma_context_config cc = ma_context_config_init();
		cc.pulse.pApplicationName = "LAMPBLACK";
		ready_ = ma_context_init(null_backend ? null : real, null_backend ? 1 : real_count, &cc, &context_) == MA_SUCCESS;
	}
	~MiniaudioDriver() override {
		close();
		if (ready_) {
			ma_context_uninit(&context_);
		}
	}

	std::vector<CaptureDevice> devices() override {
		std::vector<CaptureDevice> out;
		if (!ready_) {
			return out;
		}
		ma_device_info *play = nullptr;
		ma_device_info *cap = nullptr;
		ma_uint32 play_n = 0;
		ma_uint32 cap_n = 0;
		if (ma_context_get_devices(&context_, &play, &play_n, &cap, &cap_n) != MA_SUCCESS) {
			return out;
		}
		for (ma_uint32 i = 0; i < cap_n; i++) {
			out.push_back(CaptureDevice{id_text(cap[i].id), cap[i].name, cap[i].isDefault != 0});
		}
		return out;
	}

	bool open(const std::string &id, DataFn on_data, LostFn on_lost) override {
		close();
		if (!ready_) {
			return false;
		}
		// Always a named device, the default resolved first: a stream on "the default" would follow
		// the system to another microphone when this one is unplugged, where the design wants a lost
		// device to read as silent until the client opens a replacement itself (GDD §15.6).
		ma_device_id chosen{};
		bool found = false;
		ma_device_info *play = nullptr;
		ma_device_info *cap = nullptr;
		ma_uint32 play_n = 0;
		ma_uint32 cap_n = 0;
		if (ma_context_get_devices(&context_, &play, &play_n, &cap, &cap_n) == MA_SUCCESS) {
			for (ma_uint32 i = 0; i < cap_n && !found; i++) {
				if (id.empty() ? cap[i].isDefault != 0 : id_text(cap[i].id) == id) {
					chosen = cap[i].id;
					found = true;
				}
			}
			if (!found && id.empty() && cap_n > 0) {
				chosen = cap[0].id;
				found = true;
			}
		}
		if (!found) {
			return false;
		}
		on_data_ = std::move(on_data);
		on_lost_ = std::move(on_lost);
		ma_device_config c = ma_device_config_init(ma_device_type_capture);
		c.capture.pDeviceID = &chosen;
		c.capture.format = ma_format_f32;
		c.capture.channels = 1;
		c.capture.shareMode = ma_share_mode_shared;
		c.sampleRate = CAPTURE_RATE;
		c.periodSizeInMilliseconds = 10;
		c.dataCallback = &MiniaudioDriver::data_cb;
		c.notificationCallback = &MiniaudioDriver::notify_cb;
		c.pUserData = this;
		c.pulse.pStreamNameCapture = "LAMPBLACK voice";
		closing_.store(false);
		if (ma_device_init(&context_, &c, &device_) != MA_SUCCESS) {
			return false;
		}
		if (ma_device_start(&device_) != MA_SUCCESS) {
			ma_device_uninit(&device_);
			return false;
		}
		running_ = true;
		ma_device_info info{};
		opened_ = ma_device_get_info(&device_, ma_device_type_capture, &info) == MA_SUCCESS ? id_text(info.id) : id_text(chosen);
		// A capture callback fires as each period fills: a period is what the device adds, however
		// many periods its buffer holds.
		latency_ms_ = 1000.0 * device_.capture.internalPeriodSizeInFrames / device_.capture.internalSampleRate;
		return true;
	}

	void close() override {
		if (!running_) {
			return;
		}
		closing_.store(true);
		ma_device_uninit(&device_); // stops the device thread first
		running_ = false;
		opened_.clear();
	}

	std::string opened_id() const override { return opened_; }
	bool alive() const override { return running_ && ma_device_get_state(const_cast<ma_device *>(&device_)) == ma_device_state_started; }
	double device_latency_ms() const override { return latency_ms_; }

private:
	static void data_cb(ma_device *d, void *, const void *input, ma_uint32 frames) {
		auto *self = static_cast<MiniaudioDriver *>(d->pUserData);
		if (input != nullptr && self->on_data_) {
			self->on_data_(static_cast<const float *>(input), frames);
		}
	}
	static void notify_cb(const ma_device_notification *n) {
		auto *self = static_cast<MiniaudioDriver *>(n->pDevice->pUserData);
		// A stop nobody asked for: the device was unplugged, disabled or taken away.
		if (n->type == ma_device_notification_type_stopped && !self->closing_.load() && self->on_lost_) {
			self->on_lost_();
		}
	}

	ma_context context_{};
	ma_device device_{};
	bool ready_ = false;
	bool running_ = false;
	std::atomic<bool> closing_{false};
	std::string opened_;
	double latency_ms_ = 0.0;
	DataFn on_data_;
	LostFn on_lost_;
};

} // namespace

std::unique_ptr<CaptureDriver> make_miniaudio_driver() {
	return std::make_unique<MiniaudioDriver>(false);
}

std::unique_ptr<CaptureDriver> make_null_miniaudio_driver() {
	return std::make_unique<MiniaudioDriver>(true);
}

// ---- FakeCaptureDriver ----

void FakeCaptureDriver::add_device(const std::string &id, const std::string &name, bool is_default) {
	devices_.push_back(CaptureDevice{id, name, is_default});
}

void FakeCaptureDriver::remove_device(const std::string &id) {
	devices_.erase(std::remove_if(devices_.begin(), devices_.end(), [&](const CaptureDevice &d) { return d.id == id; }), devices_.end());
	if (opened_ == id) {
		opened_.clear();
		on_data_ = nullptr;
		if (on_lost_) {
			on_lost_();
		}
	}
}

bool FakeCaptureDriver::feed(const float *samples, uint32_t count) {
	if (opened_.empty() || !on_data_) {
		return false;
	}
	on_data_(samples, count);
	return true;
}

std::vector<CaptureDevice> FakeCaptureDriver::devices() {
	return devices_;
}

bool FakeCaptureDriver::open(const std::string &id, DataFn on_data, LostFn on_lost) {
	close();
	const CaptureDevice *pick = nullptr;
	for (const CaptureDevice &d : devices_) {
		if ((id.empty() && (d.is_default || pick == nullptr)) || d.id == id) {
			pick = &d;
		}
	}
	if (pick == nullptr) {
		return false;
	}
	opened_ = pick->id;
	on_data_ = std::move(on_data);
	on_lost_ = std::move(on_lost);
	return true;
}

void FakeCaptureDriver::close() {
	opened_.clear();
	on_data_ = nullptr;
	on_lost_ = nullptr;
}

// ---- MicCapture ----

MicCapture::MicCapture(std::unique_ptr<CaptureDriver> driver) : driver_(std::move(driver)), far_(CAPTURE_RATE / 2), frames_(16), proc_us_(512, 0) {}

MicCapture::~MicCapture() {
	close();
	if (resampler_ != nullptr) {
		speex_resampler_destroy(resampler_);
	}
}

bool MicCapture::configure(const ProcessorParams &params) {
	if (!make_processor(params)) {
		return false;
	}
	params_ = params;
	return true;
}

std::vector<CaptureDevice> MicCapture::devices() {
	return driver_ ? driver_->devices() : std::vector<CaptureDevice>{};
}

bool MicCapture::open(const std::string &id) {
	if (open_) {
		return true;
	}
	if (!driver_) {
		return false;
	}
	proc_ = make_processor(params_);
	if (!proc_) {
		return false;
	}
	lost_.store(false, std::memory_order_release);
	block_fill_ = 0;
	frame_fill_ = 0;
	const bool ok = driver_->open(
			id, [this](const float *s, uint32_t n) { on_data(s, n); },
			[this]() { lost_.store(true, std::memory_order_release); });
	if (!ok) {
		proc_.reset();
		return false;
	}
	open_ = true;
	open_count_++;
	return true;
}

void MicCapture::close() {
	if (driver_) {
		driver_->close();
	}
	open_ = false;
	lost_.store(false, std::memory_order_release);
	proc_.reset();
	far_.wipe();
	frames_.wipe();
	std::fill(std::begin(block_), std::end(block_), 0.0f);
	std::fill(std::begin(far_block_), std::end(far_block_), 0.0f);
	frame_ = CaptureFrame{};
	std::fill(mono_.begin(), mono_.end(), 0.0f);
	std::fill(resampled_.begin(), resampled_.end(), 0.0f);
	block_fill_ = 0;
	frame_fill_ = 0;
	if (resampler_ != nullptr) {
		speex_resampler_reset_mem(resampler_);
	}
}

std::string MicCapture::device_id() const {
	return driver_ ? driver_->opened_id() : std::string();
}

void MicCapture::push_far_end(const float *mono, uint32_t count) {
	if (open_) {
		far_.push(mono, count);
	}
}

void MicCapture::push_far_end_stereo(const float *interleaved, uint32_t frames, uint32_t rate) {
	if (!open_ || frames == 0 || rate == 0) {
		return;
	}
	mono_.resize(frames);
	for (uint32_t i = 0; i < frames; i++) {
		mono_[i] = 0.5f * (interleaved[2 * i] + interleaved[2 * i + 1]);
	}
	if (rate == static_cast<uint32_t>(CAPTURE_RATE)) {
		far_.push(mono_.data(), frames);
		return;
	}
	if (resampler_ == nullptr || resampler_rate_ != rate) {
		if (resampler_ != nullptr) {
			speex_resampler_destroy(resampler_);
		}
		int err = 0;
		resampler_ = speex_resampler_init(1, rate, CAPTURE_RATE, SPEEX_RESAMPLER_QUALITY_VOIP, &err);
		resampler_rate_ = rate;
		if (resampler_ == nullptr) {
			return;
		}
	}
	resampled_.resize(static_cast<size_t>(frames) * CAPTURE_RATE / rate + 16);
	spx_uint32_t in_len = frames;
	spx_uint32_t out_len = static_cast<spx_uint32_t>(resampled_.size());
	speex_resampler_process_float(resampler_, 0, mono_.data(), &in_len, resampled_.data(), &out_len);
	far_.push(resampled_.data(), out_len);
}

bool MicCapture::pop_frame(CaptureFrame &out) {
	return frames_.pop(&out, 1);
}

void MicCapture::on_data(const float *samples, uint32_t count) {
	if (!proc_) {
		return;
	}
	while (count > 0) {
		const uint32_t take = std::min(count, static_cast<uint32_t>(CAPTURE_BLOCK) - block_fill_);
		std::memcpy(block_ + block_fill_, samples, take * sizeof(float));
		block_fill_ += take;
		samples += take;
		count -= take;
		if (block_fill_ < static_cast<uint32_t>(CAPTURE_BLOCK)) {
			break;
		}
		block_fill_ = 0;
		const int64_t t0 = steady_usec();
		// Render first: every far-end block that has arrived, then the microphone's block.
		while (far_.pop(far_block_, CAPTURE_BLOCK)) {
			proc_->far_end(far_block_);
		}
		proc_->capture(block_);
		const int64_t t1 = steady_usec();
		if (stats_.try_lock()) {
			proc_us_[proc_next_++ % proc_us_.size()] = static_cast<uint32_t>(t1 - t0);
			stats_.unlock();
		}
		std::memcpy(frame_.pcm + frame_fill_, block_, sizeof(block_));
		frame_fill_ += CAPTURE_BLOCK;
		if (frame_fill_ == static_cast<uint32_t>(CAPTURE_FRAME)) {
			frame_.steady_usec = t1;
			frames_.push(&frame_, 1);
			frame_fill_ = 0;
		}
	}
}

double MicCapture::device_latency_ms() const {
	return driver_ && open_ ? driver_->device_latency_ms() : 0.0;
}

double MicCapture::processing_us_p95() const {
	std::lock_guard<std::mutex> lock(stats_);
	const size_t n = std::min(proc_next_, proc_us_.size());
	if (n == 0) {
		return 0.0;
	}
	std::vector<uint32_t> v(proc_us_.begin(), proc_us_.begin() + static_cast<std::ptrdiff_t>(n));
	std::sort(v.begin(), v.end());
	return v[std::min(n - 1, (n * 95) / 100)];
}

uint64_t MicCapture::dropped_frames() const {
	return frames_.dropped();
}

uint64_t MicCapture::dropped_far_end() const {
	return far_.dropped();
}

bool MicCapture::buffers_zeroed() const {
	auto zero = [](const float *p, size_t n) { return std::all_of(p, p + n, [](float v) { return v == 0.0f; }); };
	return far_.all_zero() && frames_.all_zero() && zero(block_, CAPTURE_BLOCK) && zero(far_block_, CAPTURE_BLOCK) &&
			zero(frame_.pcm, CAPTURE_FRAME) && zero(mono_.data(), mono_.size()) && zero(resampled_.data(), resampled_.size());
}

} // namespace lb::core::voice

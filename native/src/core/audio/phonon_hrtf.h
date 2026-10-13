#pragma once
// SND-04: Steam Audio's binaural rendering (Apache 2.0, native/thirdparty/steamaudio) for the
// headphone path. The library is loaded at run time from beside this module (libphonon.so or
// phonon.dll), never linked, so a build without it still runs: load() returns null and the mixer
// keeps the spherical-head model (the month-1 spike's fallback). One context and one default HRTF
// per mixer; one binaural effect per source, so each keeps its own interpolation. Engine-free.

#include "core/audio/hrtf.h"

#include <map>
#include <memory>
#include <string>

namespace lb::core::audio {

class PhononHrtf : public Hrtf {
public:
	~PhononHrtf() override;

	// The library beside this module (or at `path` when given); null if it is missing or refuses.
	// `bilinear`: interpolate between measured directions (smoother for noise-like sounds, about
	// half again the cost) rather than take the nearest.
	static std::unique_ptr<PhononHrtf> load(int sample_rate, int frame_size, const std::string &path = "", bool bilinear = false);
	// Where load() looks by default: this module's directory plus the platform's library name.
	static std::string default_path();
	// Why the last load() failed ("" after a success).
	static const std::string &last_error();

	int frame_size() const override { return frame_; }
	uint32_t open() override;
	void close(uint32_t id) override;
	void process(uint32_t id, double azimuth_deg, const float *in, float *left, float *right) override;
	const char *name() const override { return "steam_audio"; }
	// The default HRTF's median plane (where broadband sound is balanced between the ears) sits a few
	// degrees off its nominal ahead; load() finds it, and process() turns every azimuth by it, so a
	// source straight ahead is centred. Degrees, negative to the left.
	double centre_deg() const { return centre_deg_; }

private:
	struct Api;
	PhononHrtf() = default;
	std::unique_ptr<Api> api_;
	void *library_ = nullptr;
	void *context_ = nullptr;
	void *hrtf_ = nullptr;
	int rate_ = 48000;
	int frame_ = 512;
	bool bilinear_ = false;
	double centre_deg_ = 0.0;
	// Left minus right, dB, of a fixed broadband burst at `azimuth_deg` (no centre applied).
	double balance_db(double azimuth_deg);
	uint32_t next_ = 1;
	std::map<uint32_t, void *> effects_;
};

} // namespace lb::core::audio

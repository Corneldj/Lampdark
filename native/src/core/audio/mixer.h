#pragma once
// SND-04: the one native mixer for every positional sound (SND-03's events, SND-07's voice frames,
// SND-11's callouts). Each source is mono PCM at its own rate with the server's gain, a position
// (tiles) and an output group (the bus it plays on: Game, Muffled, Tells, Voice...). Every mix
// renders one group: per source, a linear resample, its gain, the rear low-pass for its azimuth,
// then the output mode (speakers: equal power; headphones: Steam Audio's HRTF when one is set, in
// fixed blocks, else the spherical-head binaural model; mono: the binaural output summed).
// There is no distance attenuation anywhere. A dev and QA listener mode faces north whatever the
// facing (criterion 5's screen-up A/B); it is compiled only with LB_DEBUG_TOOLS. Engine-free.

#include "core/audio/hrtf.h"
#include "core/audio/spatializer.h"

#include <cstdint>
#include <deque>
#include <map>
#include <memory>
#include <vector>

namespace lb::core::audio {

struct SourceDesc {
	std::vector<float> samples;  // mono
	double rate = 22050.0;
	double x = 0.0, y = 0.0;     // tiles
	double gain_db = 0.0;
	uint8_t group = 0;
	bool positional = true;
	bool loop = false;
	// SND-07: a stream (live voice): samples are appended as they arrive; starved, it plays silence
	// and waits; it ends only once closed and drained.
	bool streaming = false;
};

class Mixer {
public:
	explicit Mixer(double sample_rate = 44100.0) : rate_(sample_rate) {}

	void set_pose(const Pose &p) { pose_ = p; }
	const Pose &pose() const { return pose_; }
	void set_mode(OutputMode m) { mode_ = m; }
	OutputMode mode() const { return mode_; }
	void set_rear(const RearParams &r) { rear_ = r; }
	// SND-04: the headphone path's HRTF (Steam Audio); null keeps the spherical-head model.
	void set_hrtf(std::shared_ptr<Hrtf> h);
	const Hrtf *hrtf() const { return hrtf_.get(); }
#ifdef LB_DEBUG_TOOLS
	// Criterion 5's A/B: the listener faces north whatever the miner's facing. Dev and QA only.
	void set_screen_up(bool on) { screen_up_ = on; }
#endif
	bool screen_up() const { return screen_up_; }

	uint32_t add(const SourceDesc &d);
	bool remove(uint32_t id);
	~Mixer();
	bool has(uint32_t id) const { return sources_.count(id) != 0; }
	void move(uint32_t id, double x, double y);
	size_t count() const { return sources_.size(); }
	// SND-07's streams: append samples (at the source's rate), set the gain, close (end when drained),
	// and how many samples wait to play.
	bool append(uint32_t id, const float *samples, size_t count);
	void set_gain(uint32_t id, double gain_db);
	void close_stream(uint32_t id);
	size_t queued(uint32_t id) const;

	// Renders `frames` stereo frames of one group into out (interleaved L, R), advancing those
	// sources; finished non-looping sources are dropped.
	void mix(uint8_t group, float *out, size_t frames);

	// What the listener does with a source now (tests and diagnostics).
	double azimuth_of(uint32_t id) const;
	double rear_cutoff_of(uint32_t id) const;
	Pose listening_pose() const;

private:
	struct Source {
		SourceDesc d;
		double cursor = 0.0;
		OnePole rear;
		OnePole shadow;
		std::deque<float> delay;
		// The HRTF path: its effect, and rendered ears not yet mixed.
		uint32_t hrtf_id = 0;
		std::vector<float> left, right;
		size_t read = 0;
		bool ended = false;
		bool closed = false; // a stream that takes no more samples
	};
	// The source's next mono sample after resampling, gain and the rear low-pass; `finished` once it
	// has none (a one-shot's end).
	float next_sample(Source &s, double gain, double step, bool &finished);
	// The HRTF path for one source: false once it has ended and drained.
	bool mix_hrtf(Source &s, double az, double gain, float *out, size_t frames);
	double rate_;
	Pose pose_;
	OutputMode mode_ = OutputMode::HEADPHONES;
	RearParams rear_;
	bool screen_up_ = false;
	uint32_t next_id_ = 1;
	std::map<uint32_t, Source> sources_;
	std::shared_ptr<Hrtf> hrtf_;
};

} // namespace lb::core::audio

#include "core/audio/phonon_hrtf.h"

#include <phonon.h>

#include <cmath>
#include <vector>

#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#else
#include <dlfcn.h>
#endif

namespace lb::core::audio {

namespace {

constexpr double PI = 3.14159265358979323846;
std::string g_last_error;

#ifdef _WIN32
constexpr const char *LIBRARY = "phonon.dll";
#else
constexpr const char *LIBRARY = "libphonon.so";
#endif

void *open_library(const std::string &path) {
#ifdef _WIN32
	std::wstring w(path.begin(), path.end());
	return reinterpret_cast<void *>(LoadLibraryW(w.c_str()));
#else
	return dlopen(path.c_str(), RTLD_NOW | RTLD_LOCAL);
#endif
}

void *symbol(void *library, const char *name) {
#ifdef _WIN32
	return reinterpret_cast<void *>(GetProcAddress(reinterpret_cast<HMODULE>(library), name));
#else
	return dlsym(library, name);
#endif
}

void close_library(void *library) {
	if (library == nullptr) {
		return;
	}
#ifdef _WIN32
	FreeLibrary(reinterpret_cast<HMODULE>(library));
#else
	dlclose(library);
#endif
}

} // namespace

struct PhononHrtf::Api {
	decltype(&iplContextCreate) context_create = nullptr;
	decltype(&iplContextRelease) context_release = nullptr;
	decltype(&iplHRTFCreate) hrtf_create = nullptr;
	decltype(&iplHRTFRelease) hrtf_release = nullptr;
	decltype(&iplBinauralEffectCreate) effect_create = nullptr;
	decltype(&iplBinauralEffectRelease) effect_release = nullptr;
	decltype(&iplBinauralEffectApply) effect_apply = nullptr;
};

const std::string &PhononHrtf::last_error() {
	return g_last_error;
}

std::string PhononHrtf::default_path() {
	std::string self;
#ifdef _WIN32
	HMODULE module = nullptr;
	if (GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
				reinterpret_cast<LPCWSTR>(&PhononHrtf::default_path), &module)) {
		wchar_t buffer[4096];
		const DWORD n = GetModuleFileNameW(module, buffer, 4096);
		for (DWORD i = 0; i < n; i++) {
			self.push_back(static_cast<char>(buffer[i] < 128 ? buffer[i] : '?'));
		}
	}
	const size_t slash = self.find_last_of("\\/");
#else
	Dl_info info;
	if (dladdr(reinterpret_cast<void *>(&PhononHrtf::default_path), &info) != 0 && info.dli_fname != nullptr) {
		self = info.dli_fname;
	}
	const size_t slash = self.find_last_of('/');
#endif
	const std::string dir = slash == std::string::npos ? std::string(".") : self.substr(0, slash);
	return dir + "/" + LIBRARY;
}

std::unique_ptr<PhononHrtf> PhononHrtf::load(int sample_rate, int frame_size, const std::string &path, bool bilinear) {
	const std::string where = path.empty() ? default_path() : path;
	void *library = open_library(where);
	if (library == nullptr) {
		g_last_error = "cannot open " + where;
		return nullptr;
	}
	std::unique_ptr<PhononHrtf> out(new PhononHrtf());
	out->library_ = library;
	out->rate_ = sample_rate;
	out->frame_ = frame_size;
	out->bilinear_ = bilinear;
	out->api_ = std::make_unique<Api>();
	Api &a = *out->api_;
	a.context_create = reinterpret_cast<decltype(a.context_create)>(symbol(library, "iplContextCreate"));
	a.context_release = reinterpret_cast<decltype(a.context_release)>(symbol(library, "iplContextRelease"));
	a.hrtf_create = reinterpret_cast<decltype(a.hrtf_create)>(symbol(library, "iplHRTFCreate"));
	a.hrtf_release = reinterpret_cast<decltype(a.hrtf_release)>(symbol(library, "iplHRTFRelease"));
	a.effect_create = reinterpret_cast<decltype(a.effect_create)>(symbol(library, "iplBinauralEffectCreate"));
	a.effect_release = reinterpret_cast<decltype(a.effect_release)>(symbol(library, "iplBinauralEffectRelease"));
	a.effect_apply = reinterpret_cast<decltype(a.effect_apply)>(symbol(library, "iplBinauralEffectApply"));
	if (!a.context_create || !a.context_release || !a.hrtf_create || !a.hrtf_release || !a.effect_create || !a.effect_release ||
			!a.effect_apply) {
		g_last_error = where + " lacks the binaural API";
		return nullptr;
	}
	IPLContextSettings cs{};
	cs.version = STEAMAUDIO_VERSION;
	cs.simdLevel = IPL_SIMDLEVEL_AVX2;
	IPLContext context = nullptr;
	if (a.context_create(&cs, &context) != IPL_STATUS_SUCCESS) {
		g_last_error = "iplContextCreate failed (version mismatch?)";
		return nullptr;
	}
	out->context_ = context;
	IPLAudioSettings as{sample_rate, frame_size};
	IPLHRTFSettings hs{};
	hs.type = IPL_HRTFTYPE_DEFAULT;
	hs.volume = 1.0f;
	hs.normType = IPL_HRTFNORMTYPE_NONE;
	IPLHRTF hrtf = nullptr;
	if (a.hrtf_create(context, &as, &hs, &hrtf) != IPL_STATUS_SUCCESS) {
		g_last_error = "iplHRTFCreate failed";
		return nullptr;
	}
	out->hrtf_ = hrtf;
	// Find the median plane near ahead: the azimuth within +-15 degrees where a broadband burst is
	// most nearly balanced (1 degree steps, then tenths around the best; ties go to the smaller turn).
	double best = 0.0, best_abs = std::fabs(out->balance_db(0.0));
	for (int coarse = -15; coarse <= 15; coarse++) {
		const double b = std::fabs(out->balance_db(coarse));
		if (b < best_abs - 0.05 || (b <= best_abs + 0.05 && std::abs(coarse) < std::fabs(best))) {
			best = coarse;
			best_abs = b;
		}
	}
	const double around = best;
	for (int fine = -9; fine <= 9; fine++) {
		const double az = around + fine / 10.0;
		const double b = std::fabs(out->balance_db(az));
		if (b < best_abs - 0.05) {
			best = az;
			best_abs = b;
		}
	}
	out->centre_deg_ = best;
	g_last_error.clear();
	return out;
}

double PhononHrtf::balance_db(double azimuth_deg) {
	const uint32_t id = open();
	if (id == 0) {
		return 0.0;
	}
	std::vector<float> in(static_cast<size_t>(frame_)), l(in.size()), r(in.size());
	uint32_t state = 0x2545F491u;  // a fixed burst: the same every load
	double el = 0.0, er = 0.0;
	const int blocks = 4 + (24000 / frame_);
	for (int b = 0; b < blocks; b++) {
		for (float &x : in) {
			state = state * 1664525u + 1013904223u;
			x = static_cast<float>(static_cast<int32_t>(state) / 4294967296.0);
		}
		const double saved = centre_deg_;
		centre_deg_ = 0.0;
		process(id, azimuth_deg, in.data(), l.data(), r.data());
		centre_deg_ = saved;
		if (b >= 4) {
			for (size_t i = 0; i < in.size(); i++) {
				el += l[i] * l[i];
				er += r[i] * r[i];
			}
		}
	}
	close(id);
	return 10.0 * std::log10((el + 1e-20) / (er + 1e-20));  // determinism: allow (client audio output, never sim state)
}

PhononHrtf::~PhononHrtf() {
	if (api_) {
		for (auto &kv : effects_) {
			IPLBinauralEffect e = static_cast<IPLBinauralEffect>(kv.second);
			api_->effect_release(&e);
		}
		if (hrtf_ != nullptr) {
			IPLHRTF h = static_cast<IPLHRTF>(hrtf_);
			api_->hrtf_release(&h);
		}
		if (context_ != nullptr) {
			IPLContext c = static_cast<IPLContext>(context_);
			api_->context_release(&c);
		}
	}
	close_library(library_);
}

uint32_t PhononHrtf::open() {
	IPLAudioSettings as{rate_, frame_};
	IPLBinauralEffectSettings es{};
	es.hrtf = static_cast<IPLHRTF>(hrtf_);
	IPLBinauralEffect effect = nullptr;
	if (api_->effect_create(static_cast<IPLContext>(context_), &as, &es, &effect) != IPL_STATUS_SUCCESS) {
		return 0;
	}
	const uint32_t id = next_++;
	effects_[id] = effect;
	return id;
}

void PhononHrtf::close(uint32_t id) {
	auto it = effects_.find(id);
	if (it == effects_.end()) {
		return;
	}
	IPLBinauralEffect e = static_cast<IPLBinauralEffect>(it->second);
	api_->effect_release(&e);
	effects_.erase(it);
}

void PhononHrtf::process(uint32_t id, double azimuth_deg, const float *in, float *left, float *right) {
	auto it = effects_.find(id);
	if (it == effects_.end()) {
		for (int i = 0; i < frame_; i++) {
			left[i] = right[i] = 0.0f;
		}
		return;
	}
	// Steam Audio's listener space: +x right, +y up, -z ahead.
	const double a = (azimuth_deg + centre_deg_) * PI / 180.0;
	IPLBinauralEffectParams p{};
	p.direction = IPLVector3{static_cast<float>(std::sin(a)), 0.0f, static_cast<float>(-std::cos(a))};  // determinism: allow (client audio output, never sim state)
	p.interpolation = bilinear_ ? IPL_HRTFINTERPOLATION_BILINEAR : IPL_HRTFINTERPOLATION_NEAREST;
	p.spatialBlend = 1.0f;
	p.hrtf = static_cast<IPLHRTF>(hrtf_);
	p.peakDelays = nullptr;
	float *in_ch[1] = {const_cast<float *>(in)};
	float *out_ch[2] = {left, right};
	IPLAudioBuffer ib{1, frame_, in_ch};
	IPLAudioBuffer ob{2, frame_, out_ch};
	api_->effect_apply(static_cast<IPLBinauralEffect>(it->second), &p, &ib, &ob);
}

} // namespace lb::core::audio

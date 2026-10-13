# webrtc-audio-processing 2.1 (vendored for SND-05)

- Source: https://freedesktop.org/software/pulseaudio/webrtc-audio-processing/webrtc-audio-processing-2.1.tar.xz
  (SHA-256 ae9302824b2038d394f10213cab05312c564a038434269f11dbf68f511f9f9fe; no published checksum).
  PulseAudio's standalone packaging of WebRTC's audio processing module (AEC3, noise suppression,
  the high-pass filter).
- abseil-cpp 20240722.0, which it depends on, from its meson wrap:
  https://github.com/abseil/abseil-cpp/releases/download/20240722.0/abseil-cpp-20240722.0.tar.gz
  (SHA-256 f50e5ac311a81382da7fa75b97310e4b9006474f9560ac46f54a9967f07d4ae3, as the wrap pins it).
- Licences: BSD 3-clause (`COPYING`, `webrtc/LICENSE`, with Google's patent grant in
  `webrtc/PATENTS`); abseil is Apache 2.0 (`abseil/LICENSE`).
- **What is kept.** Only what `AudioProcessing` with AEC3, noise suppression and the high-pass links:
  213 sources (8 of them abseil's), found from the linker map of a probe program built with the
  project's own meson files, listed in `sources.txt` with each AVX2/SSE2 kernel's ISA flags. Every
  header of `webrtc/` and of abseil's `absl/` is kept.
- **Built** by `native/SConstruct` (`voice_objects`): warnings off, `NDEBUG` in both targets,
  `WEBRTC_APM_DEBUG_DUMP=0` (no debug dumps can be written), and `-include cstdint`, since GCC 16's
  headers no longer pull in `<cstdint>` where these sources expect it. Unchanged otherwise.
- Nothing in it opens a file in this build: its AEC dump factory is the null one.

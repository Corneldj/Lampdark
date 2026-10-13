# Third-party components

Every third-party component in the game, with its version and licence. This list feeds the store's legal and credits review (STM-13). Add a row whenever a component is added or its pin moves.

| Component | Version | Licence | Location | Source |
|---|---|---|---|---|
| Godot Engine | 4.7.2-stable | MIT | Engine and export templates (not vendored) | https://godotengine.org |
| GUT (Godot Unit Test) | 9.7.1 | MIT | `addons/gut/` (licence: `addons/gut/LICENSE.md`) | https://github.com/bitwes/Gut |
| godot-cpp | 10.0.0-stable (`507ed9d`) | MIT | `native/godot-cpp/` (submodule) | https://github.com/godotengine/godot-cpp |
| doctest | 2.5.3 | MIT | `native/thirdparty/doctest/` (licence: `LICENSE.txt`); test builds only | https://github.com/doctest/doctest |
| libopus | 1.6 | BSD 3-clause | `native/thirdparty/opus/` (licence: `COPYING`); built into the core library | https://opus-codec.org |
| Steam Audio | 4.8.1 | Apache 2.0 | `native/thirdparty/steamaudio/` (licence: `LICENSE.md`, its own third-party list: `THIRDPARTY.md`); `libphonon.so` and `phonon.dll` ship beside the core library in client builds | https://github.com/ValveSoftware/steam-audio |
| webrtc-audio-processing | 2.1 | BSD 3-clause, with Google's patent grant | `native/thirdparty/webrtc-apm/` (licence: `COPYING`, `webrtc/LICENSE`, `webrtc/PATENTS`); built into the core library | https://gitlab.freedesktop.org/pulseaudio/webrtc-audio-processing |
| abseil-cpp (the parts webrtc-audio-processing links) | 20240722.0 | Apache 2.0 | `native/thirdparty/webrtc-apm/abseil/` (licence: `LICENSE`); built into the core library | https://github.com/abseil/abseil-cpp |
| SpeexDSP | 1.2.1 | BSD 3-clause | `native/thirdparty/speexdsp/` (licence: `COPYING`); built into the core library | https://www.speex.org |
| miniaudio | 0.11.25 (patched: see its README) | Public domain (Unlicense) or MIT No Attribution | `native/thirdparty/miniaudio/` (licence: `LICENSE`); built into the core library | https://miniaud.io |
| Anonymous Pro, Courier Prime, Lobster Two fonts (bundled with GUT) | as shipped in GUT 9.7.1 | SIL OFL 1.1 | `addons/gut/fonts/` (licence: `addons/gut/fonts/OFL.txt`) | Bundled with GUT |

GUT is a development tool and is excluded from release exports (FND-03).

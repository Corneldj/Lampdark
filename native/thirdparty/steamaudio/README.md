# Steam Audio 4.8.1 (vendored for SND-04)

- Source: https://github.com/ValveSoftware/steam-audio/releases/tag/v4.8.1, `steamaudio_4.8.1.zip`
  (SHA-256 4a0aa5ec1176f38f0b0993a37c2259d9e86f27e22d5e24f83ec4c3cb9a1d5449, checked on download).
- Licence: Apache 2.0 (`LICENSE.md`, from the repository at the v4.8.1 tag); third-party notices in
  `THIRDPARTY.md`.
- Taken: `include/` (phonon.h, phonon_interfaces.h, phonon_version.h), `lib/linux-x64/libphonon.so`
  and `lib/windows-x64/phonon.dll`. Nothing else (no x86, Android, macOS, GPU or TrueAudioNext parts).
- Use: the core library loads it at run time (dlopen / LoadLibrary) from beside itself, for the
  headphone path's HRTF (`src/core/audio/phonon_hrtf.*`); nothing links against it, so the core DLL
  still imports only KERNEL32, msvcrt and WINMM. The build copies it into `native/bin/`, and
  `lampblack_core.gdextension` lists it as a dependency so exports ship it beside the core.
- The binaries go through Git LFS (`.gitattributes`).

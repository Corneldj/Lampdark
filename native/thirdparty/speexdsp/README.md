# SpeexDSP 1.2.1 (vendored for SND-05)

- Source: https://downloads.xiph.org/releases/speex/speexdsp-1.2.1.tar.gz
  (SHA-256 8c777343e4a6399569c72abc38a95b24db56882c83dbdb6c6424a5f4aeb54d3d, checked against
  xiph.org's SHA256SUMS.txt on download).
- Licence: BSD 3-clause (`COPYING`).
- The voice capture's fallback backend (GDD §15.13): MDF echo cancelling and the preprocessor's
  noise suppression; its resampler also brings the game's mix to 48 kHz as the echo canceller's far
  end for every backend.
- Kept: `libspeexdsp/` without its test programs, and `include/speex/`. `speexdsp_config_types.h`
  is written by hand in place of configure's output.
- Built by `native/SConstruct` (`voice_objects`): `FLOATING_POINT`, `USE_SMALLFT`, warnings off,
  from `mdf.c`, `preprocess.c`, `fftwrap.c`, `smallft.c`, `filterbank.c` and `resample.c`.

# libopus 1.6 (vendored for SND-07 and SND-13)

- Source: https://downloads.xiph.org/releases/opus/opus-1.6.tar.gz
  (SHA-256 b7637334527201fdfd6dd6a02e67aceffb0e5e60155bbd89175647a80301c92c, checked against
  xiph.org's SHA256SUMS.txt on download). The same version Fedora 44 ships.
- Licence: BSD 3-clause (`COPYING`).
- Taken: `include/`, `celt/`, `silk/` with `silk/float/`, `src/` (no demos), and the `*_sources.mk`
  lists, which `native/SConstruct` reads. Not taken: the fixed-point, x86/ARM/MIPS-intrinsic and DNN
  (deep PLC, DRED, OSCE) parts, which this build does not enable.
- Built: as plain C into the core library and the doctest runner (float build, `OPUS_BUILD`,
  `USE_ALLOCA`), statically, so no runtime dependency and no new DLL import.

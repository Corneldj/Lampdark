# miniaudio 0.11.25 (vendored for SND-05)

- Source: https://github.com/mackron/miniaudio/archive/refs/tags/0.11.25.tar.gz
  (SHA-256 b900edcffe979816e2560a0580b9b1216d674b4f17fbadeca8f777a7f8ab0274; no published checksum).
- Licence: public domain (Unlicense) or MIT No Attribution, at the user's choice (`LICENSE`).
- Kept: `miniaudio.h` only. `lb_miniaudio.h` fixes the configuration (capture backends only, no
  encoder or decoder); `lb_miniaudio_impl.c` holds the implementation. Both are ours.
- **Patched:** WASAPI capture asks for the raw stream (`AUDCLNT_STREAMOPTIONS_RAW`), so Windows's
  own effects, automatic gain above all, are bypassed where the device allows it (search
  "LAMPBLACK patch" in `miniaudio.h`).

#!/usr/bin/env bash
# SND-05, SND-06, GDD §15.6: microphone samples never reach a disk, a log or the network except as SND-07's
# encoded frames. Fails if any file on the capture path can write a file, print or log, if miniaudio
# is built with its encoder, or if WebRTC's debug dumps are compiled in.
set -uo pipefail
GAME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$GAME_DIR"
status=0
native=(native/src/core/voice/mic_capture.h native/src/core/voice/mic_capture.cpp native/src/core/voice/voice_processor.h
	native/src/core/voice/voice_processor.cpp native/src/core/voice/ring_buffer.h native/src/godot/voice/lb_voice_capture.h
	native/src/godot/voice/lb_voice_capture.cpp native/src/core/voice/band_meter.h native/src/core/voice/band_meter.cpp
	native/src/godot/voice/lb_band_meter.h native/src/godot/voice/lb_band_meter.cpp)
for f in "${native[@]}"; do
	[ -f "$f" ] || { echo "FAIL $f is missing" >&2; status=1; continue; }
	if grep -nE '\b(fopen|fwrite|fprintf|fputs|ofstream|fstream|FILE[[:space:]]*\*|std::cout|std::cerr|printf|puts|UtilityFunctions::print|FileAccess|ma_encoder|send|sendto|socket)\b' "$f"; then
		echo "FAIL $f can write, print or send" >&2
		status=1
	fi
done
gd=(client/audio/voice_capture.gd client/audio/voice_bands.gd)
for f in "${gd[@]}"; do
	if grep -nE '\b(FileAccess|print|printerr|print_rich|push_warning|push_error|Log\.(debug|info|warn|error)\([^)]*(pcm|frame|sample))' "$f" | grep -vE 'Log\.warn\("voice: the %s backend failed'; then
		echo "FAIL $f can write or log audio" >&2
		status=1
	fi
done
# SND-06: calibration writes one file, the per-device thresholds store, and nothing else.
cal=client/audio/calibration.gd
if grep -nE '\b(print|printerr|print_rich|Log\.)' "$cal" || [ "$(grep -cE 'store_(string|line|buffer|var|float|32|16|8)' "$cal")" -ne 1 ] \
	|| ! grep -q 'f.store_string(JSON.stringify(all, "\\t"))' "$cal"; then
	echo "FAIL $cal writes or logs more than the thresholds store" >&2
	status=1
fi
# SND-07: the server never decodes, mixes or keeps a voice frame. One native library serves both
# ends, so the check is that no server script names a decoder or player, the forwarder includes no
# Opus code, and the voice system stores no packet beyond the call that forwards it.
if grep -rnE '\b(LbOpusDecoder|LbOpusEncoder|LbVoicePlayout|VoicePlayback|LbVoiceCapture)\b' server/ --include=*.gd; then
	echo "FAIL the server names an Opus coder or voice player" >&2
	status=1
fi
if grep -nE '#include.*(opus|voice_playout|jitter_buffer)' native/src/core/voice/voice_forwarder.* native/src/godot/voice/lb_voice_forwarder.*; then
	echo "FAIL the voice forwarder includes Opus or playout code" >&2
	status=1
fi
if grep -nE '^var [a-z_]+: (Array\[PackedByteArray\]|PackedByteArray)' server/systems/sound/voice_system.gd; then
	echo "FAIL the voice system keeps packets" >&2
	status=1
fi
grep -q '^#define MA_NO_ENCODING' native/thirdparty/miniaudio/lb_miniaudio.h || { echo "FAIL miniaudio is built with its encoder" >&2; status=1; }
grep -q '("WEBRTC_APM_DEBUG_DUMP", "0")' native/SConstruct || { echo "FAIL WebRTC's debug dumps are not compiled out" >&2; status=1; }
[ "$status" -eq 0 ] && echo "ok   the capture path cannot write, print, log or send microphone audio; the server never decodes or keeps voice"
exit "$status"

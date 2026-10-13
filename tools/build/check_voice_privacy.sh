#!/usr/bin/env bash
# SND-05, GDD §15.6: microphone samples never reach a disk, a log or the network except as SND-07's
# encoded frames. Fails if any file on the capture path can write a file, print or log, if miniaudio
# is built with its encoder, or if WebRTC's debug dumps are compiled in.
set -uo pipefail
GAME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$GAME_DIR"
status=0
native=(native/src/core/voice/mic_capture.h native/src/core/voice/mic_capture.cpp native/src/core/voice/voice_processor.h
	native/src/core/voice/voice_processor.cpp native/src/core/voice/ring_buffer.h native/src/godot/voice/lb_voice_capture.h
	native/src/godot/voice/lb_voice_capture.cpp)
for f in "${native[@]}"; do
	[ -f "$f" ] || { echo "FAIL $f is missing" >&2; status=1; continue; }
	if grep -nE '\b(fopen|fwrite|fprintf|fputs|ofstream|fstream|FILE[[:space:]]*\*|std::cout|std::cerr|printf|puts|UtilityFunctions::print|FileAccess|ma_encoder|send|sendto|socket)\b' "$f"; then
		echo "FAIL $f can write, print or send" >&2
		status=1
	fi
done
gd=(client/audio/voice_capture.gd)
for f in "${gd[@]}"; do
	if grep -nE '\b(FileAccess|print|printerr|print_rich|push_warning|push_error|Log\.(debug|info|warn|error)\([^)]*(pcm|frame|sample))' "$f" | grep -vE 'Log\.warn\("voice: the %s backend failed'; then
		echo "FAIL $f can write or log audio" >&2
		status=1
	fi
done
grep -q '^#define MA_NO_ENCODING' native/thirdparty/miniaudio/lb_miniaudio.h || { echo "FAIL miniaudio is built with its encoder" >&2; status=1; }
grep -q '("WEBRTC_APM_DEBUG_DUMP", "0")' native/SConstruct || { echo "FAIL WebRTC's debug dumps are not compiled out" >&2; status=1; }
[ "$status" -eq 0 ] && echo "ok   the capture path cannot write, print, log or send microphone audio"
exit "$status"

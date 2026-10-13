#!/usr/bin/env bash
# SND-05's spike on Linux without touching anyone's real microphone: a PipeWire/PulseAudio null
# sink with a virtual source on its monitor ("LAMPBLACK spike mic"), a generated test signal played
# into it, and capture_spike.gd reading that source through the real driver. With --unplug the
# virtual source is removed mid-run, and the run must notice the loss. The modules are unloaded on
# exit; the system's default devices are left as they were. Nothing is recorded.
# With --wine <Godot .exe> the Windows editor runs the same script under Wine, whose winepulse
# serves the virtual source to the Windows build through WASAPI (FND-02's Windows stand-in).
# Usage: tools/voice/run_capture_spike.sh [--backend webrtc|speex|none] [--unplug] [--wine <godot.exe>]
set -uo pipefail
GAME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GODOT="${GODOT:-godot}"
BACKEND=webrtc
UNPLUG=0
WINE_EXE=""
while [ "$#" -gt 0 ]; do
	case "$1" in
		--backend) BACKEND="$2"; shift 2 ;;
		--unplug) UNPLUG=1; shift ;;
		--wine) WINE_EXE="$2"; shift 2 ;;
		*) echo "usage: run_capture_spike.sh [--backend b] [--unplug]" >&2; exit 2 ;;
	esac
done
default_source="$(pactl get-default-source)"
default_sink="$(pactl get-default-sink)"
work="$(mktemp -d)"
sink_mod="$(pactl load-module module-null-sink sink_name=lb_spike_sink sink_properties=device.description=LAMPBLACK-spike-sink)"
src_mod="$(pactl load-module module-remap-source master=lb_spike_sink.monitor source_name=lb_spike_mic source_properties=device.description=LAMPBLACK-spike-mic)"
cleanup() {
	[ -n "${player:-}" ] && kill "$player" 2>/dev/null
	pactl unload-module "$src_mod" 2>/dev/null
	pactl unload-module "$sink_mod" 2>/dev/null
	pactl set-default-source "$default_source" 2>/dev/null
	pactl set-default-sink "$default_sink" 2>/dev/null
	rm -rf "$work"
}
trap cleanup EXIT
# A generated test signal (speech-like bursts), 10 s, 48 kHz mono 16-bit.
python3 -I - "$work/signal.wav" <<'PY'
import math, random, struct, sys, wave
random.seed(5)
w = wave.open(sys.argv[1], "wb"); w.setnchannels(1); w.setsampwidth(2); w.setframerate(48000)
lp1 = lp2 = 0.0; frames = bytearray()
for i in range(48000 * 10):
    x = random.uniform(-1, 1); lp1 += 0.25 * (x - lp1); lp2 += 0.02 * (lp1 - lp2)
    env = max(0.0, math.sin(2 * math.pi * 5 * i / 48000))
    frames += struct.pack("<h", int(max(-1, min(1, 0.9 * env * (lp1 - lp2))) * 32767))
w.writeframes(bytes(frames)); w.close()
PY
paplay --device=lb_spike_sink "$work/signal.wav" & player=$!
extra=()
if [ "$UNPLUG" -eq 1 ]; then
	extra=(--expect-loss)
	( sleep 2; pactl unload-module "$src_mod" ) &
fi
run=("$GODOT" --headless --path "$GAME_DIR")
if [ -n "$WINE_EXE" ]; then
	run=(wine "$WINE_EXE" --headless --path "Z:$(tr / '\\' <<<"$GAME_DIR")")
fi
timeout 90 "${run[@]}" -s tools/voice/capture_spike.gd -- --device LAMPBLACK-spike-mic --seconds 4 --backend "$BACKEND" "${extra[@]}" 2>&1 | grep -a "^spike:"
status=${PIPESTATUS[0]}
[ -n "$WINE_EXE" ] && wineserver -k 2>/dev/null
[ "$(pactl get-default-source)" = "$default_source" ] && echo "spike: default source unchanged"
exit "$status"

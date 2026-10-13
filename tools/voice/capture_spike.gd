extends SceneTree
## SND-05's month-1 spike, the capture half: opens one named input through the real driver
## (miniaudio), cleans it with the chosen backend and reports what came out, without ever keeping a
## sample: frames per second, frame size, the device's buffering, processing time per 10 ms block,
## the cleaned signal's level, and how soon a vanished device is noticed.
## Usage: godot --headless --path <game> -s tools/voice/capture_spike.gd -- --device <name part>
##        [--seconds 5] [--backend webrtc|speex|none] [--expect-loss]
## A -s script runs before the autoloads exist, so the voice keys are read from the tuning file.

const VOICE: String = "res://data/tuning/voice.json"


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var want: String = _arg(args, "--device", "")
	var seconds: float = float(_arg(args, "--seconds", "5"))
	var expect_loss: bool = args.has("--expect-loss")
	var keys: Dictionary = Variants.dict(Variants.dict(JSON.parse_string(FileAccess.get_file_as_string(VOICE)))["keys"])
	var backend: String = _arg(args, "--backend", str(Variants.dict(keys["voice.apm_backend"])["value"]))
	var mic: LbVoiceCapture = LbVoiceCapture.new()
	var ok: bool = mic.configure(backend, str(Variants.dict(keys["voice.noise_suppression_level"])["value"]),
		float(Variants.number(Variants.dict(keys["voice.speex_echo_tail_ms"])["value"])),
		PackedFloat32Array(Variants.array(Variants.dict(keys["voice.speex_noise_suppress_db"])["value"])))
	print("spike: backend %s configured: %s" % [backend, ok])
	var chosen: String = ""
	for raw: Variant in mic.devices():
		var d: Dictionary = raw
		print("spike: input '%s'%s" % [d["name"], " (default)" if Variants.flag(d["is_default"]) else ""])
		if not want.is_empty() and str(d["name"]).contains(want):
			chosen = str(d["id"])
	if chosen.is_empty():
		print("spike: no input matching '%s'; nothing opened" % want)
		quit(2)
		return
	if not mic.open(chosen):
		print("spike: open failed")
		quit(1)
		return
	var start: int = Time.get_ticks_usec()
	var frames: int = 0
	var sizes_ok: bool = true
	var sum_sq: float = 0.0
	var samples: int = 0
	var last_frame_usec: int = start
	var lost_after_ms: float = -1.0
	while Time.get_ticks_usec() - start < int(seconds * 1000000.0):
		OS.delay_msec(10)
		for raw: Variant in mic.pop_frames():
			var item: Array = raw
			var pcm: PackedFloat32Array = item[0]
			sizes_ok = sizes_ok and pcm.size() == 960
			for v: float in pcm:
				sum_sq += v * v
			samples += pcm.size()
			frames += 1
			last_frame_usec = Time.get_ticks_usec()
		if mic.is_lost() and lost_after_ms < 0.0:
			lost_after_ms = (Time.get_ticks_usec() - last_frame_usec) / 1000.0
			print("spike: device lost; noticed %.0f ms after its last frame" % lost_after_ms)
			break
	var elapsed: float = (Time.get_ticks_usec() - start) / 1000000.0
	var stats: Dictionary = mic.stats()
	print("spike: %d frames in %.2f s (%.1f a second; 50 expected), every frame 960 samples: %s" % [frames, elapsed, frames / elapsed, sizes_ok])
	print("spike: device period %.1f ms; processing p95 %.0f us per 10 ms block; dropped %d" % [
		float(Variants.number(stats["device_latency_ms"])), float(Variants.number(stats["processing_us_p95"])),
		int(Variants.number(stats["dropped_frames"]))])
	print("spike: cleaned level %.1f dBFS" % (10.0 * log(sum_sq / maxf(1.0, samples) + 1e-20) / log(10.0)))
	mic.close()
	var status: int = 0
	if expect_loss and lost_after_ms < 0.0:
		print("spike: FAIL the device's loss was not noticed")
		status = 1
	quit(status)


func _arg(args: PackedStringArray, name: String, fallback: String) -> String:
	var i: int = args.find(name)
	return args[i + 1] if i >= 0 and i + 1 < args.size() else fallback

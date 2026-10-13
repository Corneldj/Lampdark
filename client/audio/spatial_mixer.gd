class_name SpatialMixer
extends Node
## SND-04: the client's one native mixer (LbAudioMixer) for every positional sound: SND-03's events and
## sputters, SND-07's voice frames, SND-11's callouts. Each source is placed in tiles and mixed for the
## listener's pose (MinerListener: on the miner, never the camera) and the output mode: equal-power
## panning on speakers, the binaural model on headphones, a mono sum; each with the rear low-pass
## deepening across the blind area (noise.rear_filter_start_deg off facing, down to
## noise.rear_lowpass_min_hz behind). Every bus that carries positional sound has one generator player,
## filled each frame with that bus's mix, so the bus effects (Muffled's low-pass, the tell volume,
## Master's limiter) still apply. No distance attenuation: the server's gain is the only level.

enum Mode { HEADPHONES = 0, SPEAKERS = 1, MONO = 2 }

## The buses positional sounds play on, in group order (the native group is the index).
const GROUPS: Array[String] = ["Game", "Muffled", "Tells", "Ambience", "Voice", "Callouts"]
## Each generator's buffer, s: rides out a slow frame (three at 60 fps) without lagging the ears.
const BUFFER_S: float = 0.05

var native: LbAudioMixer = null
## group -> AudioStreamGeneratorPlayback, once in the tree.
var _playbacks: Dictionary = {}


func _init() -> void:
	native = LbAudioMixer.new()
	native.setup(AudioServer.get_mix_rate(), Tuning.i(&"noise.hrtf_frame_samples"), Tuning.b(&"noise.hrtf_bilinear"))
	if native.has_hrtf():
		Log.info("audio: headphones through %s" % native.hrtf_name())
	else:
		Log.warn("audio: Steam Audio unavailable (%s); headphones use the spherical-head model" % native.hrtf_error())
	native.set_rear(Tuning.f(&"noise.rear_filter_start_deg"), float(Tuning.i(&"noise.rear_lowpass_min_hz")))


func _ready() -> void:
	for g: int in GROUPS.size():
		var gen: AudioStreamGenerator = AudioStreamGenerator.new()
		gen.mix_rate = AudioServer.get_mix_rate()
		gen.buffer_length = BUFFER_S
		var p: AudioStreamPlayer = AudioStreamPlayer.new()
		p.name = GROUPS[g]
		p.stream = gen
		p.bus = GROUPS[g]
		add_child(p)
		p.play()
		_playbacks[g] = p.get_stream_playback()


func _process(_delta: float) -> void:
	pump()


## Fills every bus's generator with as many frames as it will take.
func pump() -> void:
	for raw: Variant in _playbacks.keys():
		var g: int = int(Variants.number(raw))
		var pb: AudioStreamGeneratorPlayback = _playbacks[g]
		var n: int = pb.get_frames_available()
		if n > 0:
			pb.push_buffer(native.mix(g, n))


static func group_of(bus: String) -> int:
	return maxi(0, GROUPS.find(bus))


## One source (mono PCM at `rate`) at `at` (tiles) on `bus`; its id.
func add(samples: PackedFloat32Array, rate: float, at: Vector2, gain_db: float, bus: String, loop: bool = false,
		positional: bool = true) -> int:
	return native.add(samples, rate, at.x, at.y, gain_db, group_of(bus), positional, loop)


func remove(id: int) -> void:
	native.remove(id)


func has(id: int) -> bool:
	return native.has(id)


func move(id: int, at: Vector2) -> void:
	native.move(id, at.x, at.y)


func set_pose(at: Vector2, facing: int) -> void:
	native.set_pose(at.x, at.y, facing)


func set_mode(output: Mode) -> void:
	native.set_mode(output)


func mode() -> Mode:
	return native.get_mode() as Mode


## Criterion 5's A/B (QA-01): the listener faces north whatever the facing. Compiled into dev and QA
## builds only; false (and nothing changes) in a release build.
## The headphone renderer: "steam_audio", or "spherical_head" without the library.
func hrtf_name() -> String:
	return native.hrtf_name()


func screen_up_available() -> bool:
	return native.has_method(&"set_screen_up")


func set_screen_up(on: bool) -> bool:
	if not screen_up_available():
		return false
	native.call(&"set_screen_up", on)
	return true

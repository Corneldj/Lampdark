class_name SampleBank
extends RefCounted
## SND-03: placeholder samples, generated per sound type (clicks, thumps, noise bursts, tonal bells,
## hums), normalised to full scale; produced effects replace them (not ticketed). Deterministic:
## the same type always gives the same sample. Beds loop.

const RATE: int = 22050

static var _cache: Dictionary = {}
## A sample's mono float PCM for the native mixer (SND-04), by the stream's instance id.
static var _pcm: Dictionary = {}


static func stream(type: int) -> AudioStreamWAV:
	if _cache.has(type):
		var cached: AudioStreamWAV = _cache[type]
		return cached
	var id: String = NoiseTypes.id_of(type as NoiseTypes.Type) if type < 200 else LocalSounds.id_of(type)
	var kind: String = "burst"
	if id.begins_with("step") or id.contains("thump") or id.contains("fall") or id.contains("blast") or id == "shot":
		kind = "thump"
	elif id.contains("click") or id.contains("tap") or id.contains("clink") or id.contains("snap"):
		kind = "click"
	elif id.contains("bell") or id.contains("buzzer") or id.contains("canary"):
		kind = "bell"
	elif id.contains("hiss") or id.contains("ticking") or id.contains("moth"):
		kind = "hiss"
	if id == "rock_crack":
		kind = "crack"
	elif id == "rock_hush":
		kind = "trickle"
	var s: AudioStreamWAV = make(kind, 0.8 if kind == "bell" or kind == "crack" else (1.2 if kind == "trickle" else 0.4), type, 0.35 if kind == "trickle" else 1.0)
	_cache[type] = s
	return s


## A named bed layer (drips, timber, air, seam, hum, draught): a quiet loop. Placeholders with no
## steady hiss: sparse drips, a rare low creak, a faint deep rumble; the flame's sputter keeps its
## noise (it plays only while a flame gutters).
static func bed(layer: String) -> AudioStreamWAV:
	var key: String = "bed:" + layer
	if _cache.has(key):
		var cached: AudioStreamWAV = _cache[key]
		return cached
	var kind: String = "hiss"
	var seconds: float = 2.0
	var level: float = 1.0
	match layer:
		"hum":
			kind = "hum"
		"drips":
			kind = "drips"
			seconds = 7.0
			level = 0.5
		"timber", "seam":
			kind = "creak"
			seconds = 9.0 if layer == "timber" else 13.0
			level = 0.3
		"seam_cooling":  # DIR-02's cooling seam: sparse dry ticks of rock giving up its heat
			kind = "ticks"
			seconds = 11.0
			level = 0.35
		"air", "draught":
			kind = "rumble"
			seconds = 6.0
			level = 0.18
	var s: AudioStreamWAV = make(kind, seconds, layer.hash(), level)
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_end = int(seconds * RATE)
	_cache[key] = s
	return s


## RSC-06's placeholder brass band at the pithead: a slow hymn of four held chords, looped (the
## recorded band replaces it).
static func band() -> AudioStreamWAV:
	if _cache.has("band"):
		var cached: AudioStreamWAV = _cache["band"]
		return cached
	var seconds: float = 8.0
	var s: AudioStreamWAV = make("band", seconds, 1919, 0.5)
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_end = int(seconds * RATE)
	_cache["band"] = s
	return s


## A 16-bit sample as mono floats in -1..1 (cached): what SpatialMixer plays.
static func pcm(wav: AudioStreamWAV) -> PackedFloat32Array:
	var key: int = wav.get_instance_id()
	if _pcm.has(key):
		var cached: PackedFloat32Array = _pcm[key]
		return cached
	var data: PackedByteArray = wav.data
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(data.size() / 2)
	for i: int in out.size():
		out[i] = data.decode_s16(i * 2) / 32768.0
	_pcm[key] = out
	return out


## SND-04's placeholder ringing: a high whine decaying over `seconds`.
static func ringing(seconds: float) -> AudioStreamWAV:
	var key: String = "ringing:%d" % roundi(seconds * 100.0)
	if _cache.has(key):
		var cached: AudioStreamWAV = _cache[key]
		return cached
	var s: AudioStreamWAV = make("ringing", seconds, 4)
	_cache[key] = s
	return s


## A placeholder of `kind`, normalised to `level` of full scale.
static func make(kind: String, seconds: float, seed_value: int, level: float = 1.0) -> AudioStreamWAV:
	var n: int = int(seconds * RATE)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(n)
	var peak: float = 1e-9
	match kind:
		"drips":
			_drips(samples, rng)
		"creak":
			_creak(samples, rng)
		"rumble":
			_rumble(samples, rng)
		"ticks":
			_ticks(samples, rng)
		"band":
			_band(samples)
	for i: int in n:
		if kind == "drips" or kind == "creak" or kind == "rumble" or kind == "ticks" or kind == "band":
			peak = maxf(peak, absf(samples[i]))
			continue
		var t: float = float(i) / RATE
		var v: float = 0.0
		match kind:
			"thump":
				v = sin(TAU * 70.0 * t) * exp(-t * 18.0) + rng.randf_range(-0.3, 0.3) * exp(-t * 60.0)
			"click":
				v = rng.randf_range(-1.0, 1.0) * exp(-t * 120.0)
			"knock":  # SND-15's placeholder: a dull knock on wood
				v = sin(TAU * 160.0 * t) * exp(-t * 30.0) + 0.5 * sin(TAU * 410.0 * t) * exp(-t * 55.0) \
					+ rng.randf_range(-0.4, 0.4) * exp(-t * 90.0)
			"bell":
				v = (sin(TAU * 880.0 * t) + 0.5 * sin(TAU * 1760.0 * t)) * exp(-t * 4.0)
			"hum":
				v = 0.6 * sin(TAU * 50.0 * t) + 0.3 * sin(TAU * 100.0 * t)
			"hiss":
				v = rng.randf_range(-1.0, 1.0) * 0.5
			"crack":  # the strike from the rock: a sharp split of rock over a low knock
				v = rng.randf_range(-1.0, 1.0) * exp(-t * 26.0) + 0.8 * sin(TAU * 90.0 * t) * exp(-t * 9.0)
			"trickle":  # it goes quiet: a few grains of grit falling, very soft
				v = rng.randf_range(-1.0, 1.0) * 0.25 * exp(-fmod(t, 0.23) * 60.0) * exp(-t * 2.0)
			"ringing":
				v = (sin(TAU * 3800.0 * t) + 0.3 * sin(TAU * 4100.0 * t)) * (1.0 - t / seconds)
			_:
				v = rng.randf_range(-1.0, 1.0) * exp(-t * 10.0)
		samples[i] = v
		peak = maxf(peak, absf(v))
	var data: PackedByteArray = PackedByteArray()
	data.resize(n * 2)
	for i: int in n:
		data.encode_s16(i * 2, clampi(roundi(samples[i] / peak * level * 32767.0), -32768, 32767))
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.data = data
	return wav


## Four chords of two seconds (C, F, G, C), three voices each with two brass-like partials, each
## swelling in and easing off so the loop's seam is soft.
static func _band(out: PackedFloat32Array) -> void:
	var chords: Array = [[261.6, 329.6, 392.0], [174.6, 349.2, 440.0], [196.0, 392.0, 493.9], [261.6, 329.6, 392.0]]
	var per: int = out.size() / chords.size()
	for c: int in chords.size():
		var voices: Array = chords[c]
		for j: int in per:
			var t: float = float(j) / RATE
			var u: float = float(j) / per
			var env: float = minf(1.0, u * 6.0) * (1.0 - 0.6 * u)
			var v: float = 0.0
			for raw: Variant in voices:
				var f: float = float(Variants.number(raw))
				v += sin(TAU * f * t) + 0.45 * sin(TAU * 2.0 * f * t)
			out[c * per + j] = v * env


## Three to five water drips over the loop: a short falling blip and a fainter echo, silence between.
static func _drips(out: PackedFloat32Array, rng: RandomNumberGenerator) -> void:
	var n: int = out.size()
	var count: int = rng.randi_range(3, 5)
	for _d: int in count:
		var at: int = rng.randi_range(0, n - int(0.5 * RATE))
		var pitch: float = rng.randf_range(1100.0, 1900.0)
		var gain: float = rng.randf_range(0.4, 1.0)
		for echo: int in 2:
			var start: int = at + echo * int(0.13 * RATE)
			var g: float = gain * (1.0 if echo == 0 else 0.25)
			var phase: float = 0.0
			for i: int in int(0.09 * RATE):
				if start + i >= n:
					break
				var t: float = float(i) / RATE
				phase += TAU * pitch * (1.0 - 0.45 * minf(t / 0.03, 1.0)) / RATE
				out[start + i] += g * sin(phase) * exp(-t * 55.0)


## Rock ticking as it cools: a dozen or so short dry clicks, unevenly spaced, some faint.
static func _ticks(out: PackedFloat32Array, rng: RandomNumberGenerator) -> void:
	var n: int = out.size()
	var count: int = rng.randi_range(9, 15)
	for _k: int in count:
		var at: int = rng.randi_range(0, n - int(0.02 * RATE))
		var gain: float = rng.randf_range(0.25, 1.0)
		var last: float = 0.0
		for i: int in int(0.012 * RATE):
			if at + i >= n:
				break
			var t: float = float(i) / RATE
			var noise: float = rng.randf_range(-1.0, 1.0)
			out[at + i] += gain * (noise - last) * 0.5 * exp(-t * 600.0) # a bright, dry click
			last = noise


## One slow low creak somewhere in the loop: a wavering low tone under a bell-shaped swell.
static func _creak(out: PackedFloat32Array, rng: RandomNumberGenerator) -> void:
	var n: int = out.size()
	var length: int = int(rng.randf_range(0.7, 1.3) * RATE)
	var at: int = rng.randi_range(0, n - length - 1)
	var base: float = rng.randf_range(85.0, 140.0)
	var phase: float = 0.0
	var smooth: float = 0.0
	for i: int in length:
		var t: float = float(i) / length
		var f: float = base * (1.0 + 0.08 * sin(TAU * 3.0 * t) + rng.randf_range(-0.04, 0.04))
		phase += TAU * f / RATE
		var raw: float = (fposmod(phase / TAU, 1.0) * 2.0 - 1.0)  # a soft sawtooth, then smoothed
		smooth += (raw - smooth) * 0.08
		out[at + i] += smooth * sin(PI * t)


## A faint deep rumble: noise low-passed twice (nothing above a few hundred hertz), its end
## crossfaded into its start so the loop has no seam.
static func _rumble(out: PackedFloat32Array, rng: RandomNumberGenerator) -> void:
	var n: int = out.size()
	var fade: int = int(0.5 * RATE)
	var a: float = 0.0
	var b: float = 0.0
	var k: float = 1.0 - exp(-TAU * 90.0 / RATE)
	var full: PackedFloat32Array = PackedFloat32Array()
	full.resize(n + fade)
	for i: int in n + fade:
		a += (rng.randf_range(-1.0, 1.0) - a) * k
		b += (a - b) * k
		full[i] = b
	for i: int in n:
		out[i] = full[i]
	for i: int in fade:
		var w: float = float(i) / fade
		out[i] = full[n + i] * (1.0 - w) + full[i] * w
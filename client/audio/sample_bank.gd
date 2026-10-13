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
	var s: AudioStreamWAV = make(kind, 0.4 if kind != "bell" else 0.8, type)
	_cache[type] = s
	return s


## A named bed layer (drips, timber, air, seam, hum, draught): a quiet loop.
static func bed(layer: String) -> AudioStreamWAV:
	var key: String = "bed:" + layer
	if _cache.has(key):
		var cached: AudioStreamWAV = _cache[key]
		return cached
	var s: AudioStreamWAV = make("hum" if layer == "hum" else "hiss", 2.0, layer.hash())
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_end = int(2.0 * RATE)
	_cache[key] = s
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


static func make(kind: String, seconds: float, seed_value: int) -> AudioStreamWAV:
	var n: int = int(seconds * RATE)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(n)
	var peak: float = 1e-9
	for i: int in n:
		var t: float = float(i) / RATE
		var v: float = 0.0
		match kind:
			"thump":
				v = sin(TAU * 70.0 * t) * exp(-t * 18.0) + rng.randf_range(-0.3, 0.3) * exp(-t * 60.0)
			"click":
				v = rng.randf_range(-1.0, 1.0) * exp(-t * 120.0)
			"bell":
				v = (sin(TAU * 880.0 * t) + 0.5 * sin(TAU * 1760.0 * t)) * exp(-t * 4.0)
			"hum":
				v = 0.6 * sin(TAU * 50.0 * t) + 0.3 * sin(TAU * 100.0 * t)
			"hiss":
				v = rng.randf_range(-1.0, 1.0) * 0.5
			"ringing":
				v = (sin(TAU * 3800.0 * t) + 0.3 * sin(TAU * 4100.0 * t)) * (1.0 - t / seconds)
			_:
				v = rng.randf_range(-1.0, 1.0) * exp(-t * 10.0)
		samples[i] = v
		peak = maxf(peak, absf(v))
	var data: PackedByteArray = PackedByteArray()
	data.resize(n * 2)
	for i: int in n:
		data.encode_s16(i * 2, clampi(roundi(samples[i] / peak * 32767.0), -32768, 32767))
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.data = data
	return wav

class_name CalloutLines
extends RefCounted
## SND-11 (Gameplay §6.7): the callout wheel's twelve lines and the job page's four, in slice order
## (slice 0 straight up, clockwise, as UI-01's WheelWidget draws them and WheelInput counts), the
## bands a pick sends at, and how a pick's distance or timing becomes a band. Lines are SND-13's
## manifest ids; their words are the text keys callout.<line>.

const WHEEL: Array[String] = ["here", "help", "is_that_you", "count_off", "douse", "light_up", "quiet", "gate", "oil", "moth",
	"tapping", "stythe"]
const JOB_PAGE: Array[String] = ["now", "right", "stop", "left"]
## RSC-04's coming-round window: 'Help!' at talk, and a moan at whisper (SND-13's recorded moan).
const COMING_ROUND: Array[String] = ["help", "moan"]
## Band -> SND-13's form; 0 is no band (cancelled), and a callout is never screamed.
const FORMS: Array[String] = ["", "whisper", "talk", "shout"]
const WHISPER: int = 1
const TALK: int = 2
const SHOUT: int = 3


## Which of `count` equal slices an angle (degrees clockwise from east) falls in, slice 0 straight up.
static func slice(angle_deg: float, count: int) -> int:
	if count <= 0:
		return -1
	var width: float = 360.0 / count
	return floori(fposmod(angle_deg + 90.0 + width / 2.0, 360.0) / width) % count


static func line_at(angle_deg: float, job_page: bool) -> String:
	var lines: Array[String] = JOB_PAGE if job_page else WHEEL
	return lines[slice(angle_deg, lines.size())]


## SND-13's form for a line at a band (the moan has one take).
static func form_of(line: String, band: int) -> String:
	return "take_1" if line == "moan" else FORMS[band]


## The band a coming-round line always goes at.
static func coming_round_band(line: String) -> int:
	return WHISPER if line == "moan" else TALK


static func text_key(line: String) -> String:
	return "voice.moan" if line == "moan" else "callout." + line


## A pick's band: by ring from {distance} (voice.wheel_ring_bounds: centre cancels, then whisper,
## talk, shout), or by timing from {hold_ms, gap_ms} (a hold of whisper_hold_s whispers, a second
## tap within the shout window shouts, a tap talks). 0 when it sends nothing.
static func band_of(pick: Dictionary, whisper_hold_s: float = -1.0) -> int:
	if pick.has("distance"):
		var bounds: Array[float] = Tuning.current.list_f(&"voice.wheel_ring_bounds")
		var d: float = float(Variants.number(pick["distance"]))
		if d < bounds[0]:
			return 0
		if d < bounds[1]:
			return WHISPER
		return TALK if d < bounds[2] else SHOUT
	if pick.has("hold_ms"):
		var hold: float = whisper_hold_s if whisper_hold_s > 0.0 else Tuning.f(&"voice.callout_whisper_hold_s")
		if float(Variants.number(pick["hold_ms"])) / 1000.0 >= hold - 1e-6:
			return WHISPER
		return SHOUT if int(Variants.number(pick.get("gap_ms", -1))) >= 0 else TALK
	return 0


## The middle of a band's ring, as a pick distance (the client sends timing picks this way).
static func ring_distance(band: int) -> float:
	var bounds: Array[float] = Tuning.current.list_f(&"voice.wheel_ring_bounds")
	var edges: Array[float] = [bounds[0], bounds[1], bounds[2], 1.0]
	return (edges[band - 1] + edges[band]) / 2.0 if band >= WHISPER and band <= SHOUT else 0.0


## Each word's share of its frames kept (frames split evenly across the words until SND-13 has word
## timings): what UI-03 shows as words or gaps.
static func word_shares(mask: PackedByteArray, words: int) -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	if words <= 0:
		return out
	var n: int = mask.size()
	for w: int in words:
		var a: int = floori(float(n) * w / words)
		var b: int = maxi(a + 1, floori(float(n) * (w + 1) / words))
		var kept: int = 0
		for i: int in range(a, mini(b, n)):
			kept += 1 if mask[i] != 0 else 0
		out.append(float(kept) / maxf(1.0, mini(b, n) - a) if n > 0 else 1.0)
	return out

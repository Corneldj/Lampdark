class_name AudioRecord
extends RefCounted
## SND-03: one sound as a client receives it (NET-04's frame events). It says what was heard, from
## where it seems to come (the Road Graph's apparent position, or a diffuse tell's points), how loud
## it arrived against how loud it was made, how long it lasts, a vocal sound's voice, and SND-03's
## flags and mask gain. No field can hold an entity, a token, an event id or a true source; an
## illusion (CRT-10) is the same type with no extra field, so it plays and captions identically.

const MUFFLED: int = 1   ## a closed portal on the path: low-passed
const DIFFUSE: int = 2   ## a diffuse tell: played from its points, captioned without direction
const LOCAL: int = 4     ## a local emitter outside the Road Graph

## Every field a record has (test_audio_record.gd keeps it this way).
const FIELDS: Array[String] = ["type", "start_tick", "apparent", "points", "level_np", "remaining_np", "duration_s",
	"voice", "flags", "gain_db"]

var type: int = 0
var start_tick: int = 0
var apparent: Vector2 = Vector2.ZERO
var points: Array[Vector2] = []
var level_np: float = 0.0
var remaining_np: float = 0.0
var duration_s: float = 0.5
var voice: int = -1
var flags: int = 0
var gain_db: int = 0


## From SND-02's player delivery record (NoiseSystem.client_record): what may leave the server.
static func from_delivery(d: Dictionary) -> AudioRecord:
	var r: AudioRecord = AudioRecord.new()
	r.type = int(Variants.number(d["type"]))
	r.start_tick = int(Variants.number(d["tick"]))
	r.apparent = d["apparent"]
	r.level_np = float(Variants.number(d.get("level_np", d["remaining_np"])))
	r.remaining_np = float(Variants.number(d["remaining_np"]))
	r.duration_s = float(Variants.number(d["duration_s"]))
	r.voice = int(Variants.number(d.get("voice_id", -1)))
	if Variants.flag(d.get("muffled", false)):
		r.flags |= MUFFLED
	return r


## LbReplication.queue_event's dictionary.
func to_event() -> Dictionary:
	return {"type": type, "start_tick": start_tick, "apparent": apparent, "remaining_np": remaining_np, "level_np": level_np,
		"duration_s": duration_s, "voice": voice, "flags": flags, "gain_db": gain_db, "points": points}


## From a decoded frame event (client side).
static func from_event(ev: Dictionary) -> AudioRecord:
	var r: AudioRecord = AudioRecord.new()
	r.type = int(Variants.number(ev["type"]))
	r.start_tick = int(Variants.number(ev["start_tick"]))
	r.apparent = ev["apparent"]
	r.level_np = float(Variants.number(ev.get("level_np", ev["remaining_np"])))
	r.remaining_np = float(Variants.number(ev["remaining_np"]))
	r.duration_s = float(Variants.number(ev["duration_s"]))
	r.voice = int(Variants.number(ev.get("voice", -1)))
	r.flags = int(Variants.number(ev.get("flags", 0)))
	r.gain_db = int(Variants.number(ev.get("gain_db", 0)))
	for raw: Variant in Variants.array(ev.get("points", [])):
		r.points.append(raw)
	return r

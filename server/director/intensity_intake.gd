class_name IntensityIntake
extends RefCounted
## DIR-01's intake (Gameplay §10.1): the true world's events, each held as a gain for the
## Draught's next tick and counted once per miner by the event's own id.
## - A grab: +director.gain_grabbed, once per grab (a re-strike on the same pin is the same grab).
## - A trap: +director.gain_caught, once per trap, even if its miner is pinned and freed in it.
## - A fall heard: +director.gain_fall_heard, once per fall, when its knocks reach the miner.
## - A blast: +director.gain_blast, once per firedamp explosion, within director.blast_range_tiles
##   in a straight line, after that tick's falls.
## Nothing else comes in here: no voice in the rock, no lie, no illusion of any kind (§9.2), and
## the cold open's screams are not a fall. Server-only.


## One tracked miner's Draught, in thousandths of intensity.
class Record:
	extends RefCounted
	## 0 to director.intensity_max.
	var value: int = 0
	## What being alone in the dark has added since it last renewed, up to director.dark_gain_cap.
	var dark: int = 0
	## Real creature entity -> the last tick it was seen within reach (its 10 s runs from there).
	var last_seen: Dictionary = {}
	## Events already counted: "grab:<id>", "trap:<id>", "fall:<id>", "blast:<id>".
	var counted: Dictionary = {}

	func save() -> Dictionary:
		var seen: Dictionary = {}
		for raw: Variant in last_seen.keys():
			seen[str(raw)] = last_seen[raw]
		var keys: Array = counted.keys()
		keys.sort()
		return {"value": value, "dark": dark, "seen": seen, "counted": keys}

	static func from(state: Dictionary) -> Record:
		var r: Record = Record.new()
		r.value = int(Variants.number(state.get("value", 0)))
		r.dark = int(Variants.number(state.get("dark", 0)))
		var seen: Dictionary = Variants.dict(state.get("seen", {}))
		for raw: Variant in seen.keys():
			r.last_seen[int(str(raw))] = int(Variants.number(seen[raw]))
		for raw: Variant in Variants.array(state.get("counted", [])):
			r.counted[str(raw)] = true
		return r

	func write_state(writer: SimStateWriter) -> void:
		writer.put_i64(value)
		writer.put_i64(dark)
		var seen: Array = last_seen.keys()
		seen.sort()
		writer.put_i64(seen.size())
		for raw: Variant in seen:
			writer.put_i64(int(Variants.number(raw)))
			writer.put_i64(int(Variants.number(last_seen[raw])))
		var keys: Array = counted.keys()
		keys.sort()
		writer.put_i64(keys.size())
		for raw: Variant in keys:
			writer.put_string(str(raw))


## [miner, key, gain]: gains waiting for the tick.
var _pending: Array[Array] = []
## [tile, blast id]: blasts waiting for the tick, where they find who is in range.
var _blasts: Array[Array] = []


## RSC-03's grab_begun.
func grabbed(victim: int, grab_id: int) -> void:
	_pending.append([victim, "grab:%d" % grab_id, _milli(&"director.gain_grabbed")])


## RSC-03's caught_begun.
func caught(victim: int, trap_id: int) -> void:
	_pending.append([victim, "trap:%d" % trap_id, _milli(&"director.gain_caught")])


## SND-15's fall_heard: the knocks reached `miner`.
func fall_heard(miner: int, fall_id: int) -> void:
	_pending.append([miner, "fall:%d" % fall_id, _milli(&"director.gain_fall_heard")])


## HAZ-04's firedamp explosion at `tile`.
func blast(tile: Vector2i, blast_id: int) -> void:
	_blasts.append([tile, blast_id])


## Adds the waiting gains to the tracked miners' records (miner -> Record), each event once per
## miner. A miner not tracked (a Hand, the unconscious, the dead) gains nothing.
func apply(run: RunState, records: Dictionary) -> void:
	for b: Array in _blasts:
		var tile: Vector2i = b[0]
		var at: Vector2 = Vector2(tile) + Vector2(0.5, 0.5)
		var reach: float = Tuning.f(&"director.blast_range_tiles")
		for raw: Variant in records.keys():
			var e: SimEntity = run.registry.get_entity(int(Variants.number(raw)))
			if e != null and e.position.distance_to(at) <= reach:
				_pending.append([int(Variants.number(raw)), "blast:%d" % int(Variants.number(b[1])), _milli(&"director.gain_blast")])
	_blasts.clear()
	for p: Array in _pending:
		var r: Record = records.get(int(Variants.number(p[0])), null)
		var key: String = str(p[1])
		if r == null or r.counted.has(key):
			continue
		r.counted[key] = true
		r.value += int(Variants.number(p[2]))
	_pending.clear()


static func _milli(key: StringName) -> int:
	return roundi(Tuning.f(key) * 1000.0)

class_name NowJudge
extends SimSystem
## NET-06's 'Now!' judge. A cue is a server audio event at tick C (TimedCues), sent reliably to
## the presser. The client reports the shown tick at which it presented it; displayed_tick_of
## clamps that to [C, C + net.rewind_max_ms]: the cue's arrival A. Without a report, A is
## estimated from the first input whose packet acknowledged a frame at or after C (that input's
## stamp is the render time just after the frame arrived). A press counts if 0 <= S - A <= the
## job's window: both on the presser's own timeline, so latency cancels out. A miss is ruled
## only once an input stamped after A + window has been processed, or the presser starved.

enum Verdict { EARLY = 0, ON_TIME = 1, LATE = 2 }

var max_ticks: float = 3.0
## slot -> {cue_id: C}
var cues: Dictionary = {}
## slot -> {cue_id: reported shown time (ticks, with fraction)}
var reported: Dictionary = {}
## slot -> {cue_id: estimated shown time}, from acknowledgements
var estimated: Dictionary = {}
## slot -> newest stamp of a real input processed; slot -> starved now
var newest_stamp: Dictionary = {}
var starved: Dictionary = {}


func _init() -> void:
	if Tuning.current.has_key(&"net.rewind_max_ms"):
		max_ticks = Tuning.f(&"net.rewind_max_ms") / (1000.0 / Tuning.f(&"net.tick_hz"))


func stage() -> int:
	return StageTable.Stage.INPUTS


func order() -> int:
	return 50


func system_name() -> String:
	return "NowJudge"


## LFT-04 names a cue it has emitted (an audio event of a TimedCues type at tick C) for a presser.
func register_cue(slot: int, type: int, start_tick: int) -> int:
	var id: int = TimedCues.cue_id(type, start_tick)
	var mine: Dictionary = cues.get(slot, {})
	mine[id] = start_tick
	cues[slot] = mine
	return id


## InputService hands over every consumed input (stage 2).
func on_consumed(_now: int, slot: int, c: InputBuffer.Consumed) -> void:
	var mine: Dictionary = cues.get(slot, {})
	for r: PackedInt64Array in c.cue_reports:
		var got: Dictionary = reported.get(slot, {})
		if not got.has(r[0]):
			got[r[0]] = float(r[1]) + r[2] / 256.0
			reported[slot] = got
	if c.real:
		newest_stamp[slot] = maxi(int(Variants.number(newest_stamp.get(slot, -1))), c.shown_tick)
		if c.acked_frame >= 0:
			var est: Dictionary = estimated.get(slot, {})
			for raw: Variant in mine.keys():
				if not est.has(raw) and c.acked_frame >= int(Variants.number(mine[raw])):
					est[raw] = float(c.shown_tick)
			estimated[slot] = est
	starved[slot] = c.starved


## A, the cue's arrival on the presser's timeline (ticks), or -1 while nothing tells it yet.
func displayed_tick_of(slot: int, cue_id: int) -> float:
	var mine: Dictionary = cues.get(slot, {})
	if not mine.has(cue_id):
		return -1.0
	var start: float = float(Variants.number(mine[cue_id]))
	var got: Dictionary = reported.get(slot, {})
	var est: Dictionary = estimated.get(slot, {})
	var at: float
	if got.has(cue_id):
		at = float(Variants.number(got[cue_id]))
	elif est.has(cue_id):
		at = float(Variants.number(est[cue_id]))
	else:
		return -1.0
	return clampf(at, start, start + max_ticks)


## A press stamped `press_stamp` (the input's shown tick) against the cue, with the job's window.
func judge(slot: int, cue_id: int, press_stamp: float, window_ticks: float) -> Verdict:
	var a: float = displayed_tick_of(slot, cue_id)
	if a < 0.0:
		a = float(Variants.number(Variants.dict(cues.get(slot, {})).get(cue_id, 0)))
	var d: float = press_stamp - a
	if d < 0.0:
		return Verdict.EARLY
	return Verdict.ON_TIME if d <= window_ticks else Verdict.LATE


## True once no press can still count: an input stamped after A + window has been processed, or
## the presser's inputs have starved (NET-03).
func miss_ruled(slot: int, cue_id: int, window_ticks: float) -> bool:
	if Variants.flag(starved.get(slot, false)):
		return true
	var a: float = displayed_tick_of(slot, cue_id)
	if a < 0.0:
		return false
	return float(Variants.number(newest_stamp.get(slot, -1))) > a + window_ticks


## The cues are done with (the job ended): forget them.
func forget(slot: int, cue_id: int) -> void:
	for d: Dictionary in [Variants.dict(cues.get(slot, {})), Variants.dict(reported.get(slot, {})), Variants.dict(estimated.get(slot, {}))]:
		d.erase(cue_id)


func write_state(writer: SimStateWriter) -> void:
	for table: Dictionary in [cues, reported, estimated]:
		var slots: Array = table.keys()
		slots.sort()
		writer.put_i64(slots.size())
		for s: Variant in slots:
			var inner: Dictionary = table[s]
			var ids: Array = inner.keys()
			ids.sort()
			writer.put_i64(int(Variants.number(s)))
			writer.put_i64(ids.size())
			for id: Variant in ids:
				writer.put_i64(int(Variants.number(id)))
				writer.put_f64(float(Variants.number(inner[id])))

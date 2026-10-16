class_name DraughtCycle
extends RefCounted
## DIR-01's cycle (Gameplay §10.2). BUILD, when creatures may choose to begin hunts, runs until
## the highest intensity among the tracked miners reaches director.peak_threshold: there is no
## build timer. PEAK holds while the encounter that caused it plays on, for a length rolled each
## cycle on the director.peak_hold stream (director.peak_hold_s, uniform, rounded to whole ticks).
## RELAX lasts depth.relax_s by the ring of the miner who peaked, read once at the peak (DIR-04).
## Then BUILD again, and PEAK at once if the maximum is still over. The cycle never forces a peak:
## only intensity starts one. Server-only.

signal peak_begun(peaker: int, ring: int)
signal relax_begun(length_ticks: int, ring: int)
signal relax_ended()

enum Phase { BUILD = 0, PEAK = 1, RELAX = 2 }

var phase: Phase = Phase.BUILD
## Ticks left in PEAK or RELAX.
var left: int = 0
## The miner who peaked, and their ring then.
var peaker: int = 0
var ring: int = 0
## FND-06's director.peak_hold stream (the run keeps its state for saves).
var rng: LbRng = null


func in_build() -> bool:
	return phase == Phase.BUILD


## CRT-01's relax provider: false in BUILD and (Proposed) PEAK, true in RELAX.
func in_relax() -> bool:
	return phase == Phase.RELAX


## One tick, once the intensities are up to date: `top` is the highest intensity in thousandths
## and `who` its miner (ties to the lowest id), 0 when nobody is tracked; `threshold` is
## director.peak_threshold in thousandths.
func step(run: RunState, top: int, who: int, threshold: int) -> void:
	if phase == Phase.PEAK:
		left -= 1
		if left <= 0:
			_relax(run)
	elif phase == Phase.RELAX:
		left -= 1
		if left <= 0:
			phase = Phase.BUILD
			left = 0
			relax_ended.emit()
	if phase == Phase.BUILD and who != 0 and top >= threshold:
		_peak(run, who)


func _peak(run: RunState, who: int) -> void:
	phase = Phase.PEAK
	peaker = who
	ring = Depth.ring_for_miner(run, who)
	var hold: Vector2 = Tuning.range_f(&"director.peak_hold_s")
	var seconds: float = lerpf(hold.x, hold.y, rng.unit_double()) if rng != null else hold.x
	left = maxi(1, roundi(seconds * Tuning.f(&"net.tick_hz")))
	peak_begun.emit(who, ring)
	if run != null:
		Log.info("telemetry draught_peak run_time=%.1f ring=%d" % [run.tick / Tuning.f(&"net.tick_hz"), ring])


func _relax(run: RunState) -> void:
	phase = Phase.RELAX
	left = maxi(1, roundi(Depth.relax_s(ring) * Tuning.f(&"net.tick_hz")))
	relax_begun.emit(left, ring)
	if run != null:
		Log.info("telemetry relax length_s=%.1f ring=%d run_time=%.1f" % [left / Tuning.f(&"net.tick_hz"), ring,
			run.tick / Tuning.f(&"net.tick_hz")])


func save() -> Dictionary:
	return {"phase": int(phase), "left": left, "peaker": peaker, "ring": ring}


func load(state: Dictionary) -> void:
	phase = int(Variants.number(state.get("phase", 0))) as Phase
	left = int(Variants.number(state.get("left", 0)))
	peaker = int(Variants.number(state.get("peaker", 0)))
	ring = int(Variants.number(state.get("ring", 0)))


func write_state(writer: SimStateWriter) -> void:
	writer.put_i64(int(phase))
	writer.put_i64(left)
	writer.put_i64(peaker)
	writer.put_i64(ring)

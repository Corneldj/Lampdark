class_name SimLoop
extends RefCounted
## The fixed-step driver (NET-01). The caller feeds it a monotonic clock in µs; it runs every
## tick that is due, at most net.tick_max_catchup back to back, then drops the rest of the
## debt and logs one overrun. Tests drive it with any clock, or step(n) with none.
##
## pause() works only offline (Night Shift, MOD-06); online, timers run on. freeze() works in
## any run (knock-off MOD-05, migration NET-10): ticks stop, the network stage keeps pumping. A
## system may freeze the run itself through run.frozen (RSC-06's Lamp Check, after the run's end).

signal overrun(late_ticks: int, dropped_ticks: int, worst_lateness_usec: int, worst_stage: String)

var run: RunState
var tick_usec: int = 50000
var max_catchup: int = 3
var late_threshold_usec: int = 5000
var paused: bool = false
var frozen: bool = false
var overruns: int = 0
var ticks_run: int = 0
## Stop after this many ticks (smoke tests); 0 means never.
var stop_after_ticks: int = 0
var _next_deadline: int = -1


func _init(run_state: RunState) -> void:
	run = run_state
	if Tuning.current.has_key(&"net.tick_hz"):
		tick_usec = roundi(1000000.0 / Tuning.f(&"net.tick_hz"))
		max_catchup = Tuning.i(&"net.tick_max_catchup")
		late_threshold_usec = roundi(Tuning.f(&"net.tick_overrun_late_ms") * 1000.0)


func start(now_usec: int) -> void:
	_next_deadline = now_usec


## Runs every tick due by now_usec. Returns the number of ticks run.
func pump(now_usec: int) -> int:
	if _next_deadline < 0:
		start(now_usec)
	if paused:
		return 0
	if frozen or run.frozen:
		while now_usec >= _next_deadline:
			run.run_frozen_pump()
			_next_deadline += tick_usec
		return 0
	var ran: int = 0
	var late_ticks: int = 0
	var worst_lateness: int = 0
	while now_usec >= _next_deadline and ran < max_catchup:
		var lateness: int = now_usec - _next_deadline
		if lateness > late_threshold_usec:
			late_ticks += 1
			worst_lateness = maxi(worst_lateness, lateness)
		Tuning.on_tick_boundary()
		run.run_tick()
		ran += 1
		ticks_run += 1
		_next_deadline += tick_usec
		if stop_after_ticks > 0 and ticks_run >= stop_after_ticks:
			break
	var dropped: int = 0
	if now_usec >= _next_deadline:
		dropped = (now_usec - _next_deadline) / tick_usec + 1
		_next_deadline += dropped * tick_usec
	if late_ticks > 0 or dropped > 0:
		overruns += 1
		var worst: String = run.worst_stage()
		Log.warn("tick_overrun: %d late ticks (worst %.1f ms late), %d dropped, worst stage %s" % [
			late_ticks, worst_lateness / 1000.0, dropped, worst])
		overrun.emit(late_ticks, dropped, worst_lateness, worst)
	return ran


## Runs n ticks now, ignoring the clock (scenario kit, FND-09).
func step(n: int) -> void:
	for _i: int in n:
		Tuning.on_tick_boundary()
		run.run_tick()
		ticks_run += 1


## µs until the next tick is due (0 if due now).
func usec_until_next(now_usec: int) -> int:
	return maxi(_next_deadline - now_usec, 0)


## Offline only. Returns false (and timers run on) in an online run.
func pause() -> bool:
	if not run.header.offline:
		Log.warn("pause refused: the run is online, so timers run on")
		return false
	paused = true
	return true


func resume(now_usec: int) -> void:
	paused = false
	_next_deadline = now_usec


func freeze() -> void:
	frozen = true
	run.frozen = true


## Continues from the same tick: no tick lost, none doubled.
func unfreeze(now_usec: int) -> void:
	frozen = false
	run.frozen = false
	_next_deadline = now_usec


func is_done() -> bool:
	return stop_after_ticks > 0 and ticks_run >= stop_after_ticks

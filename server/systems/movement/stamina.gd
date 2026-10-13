class_name Stamina
extends RefCounted
## MNR-02: one miner's hidden stamina. A 6 s pool drains 1 s a second on ticks the miner really
## runs and refills 0.6 s a second on every other tick; at zero the miner walks, and running
## restarts only on a fresh Run press with something in the pool (Proposed). Every run ends in
## 8 s of panting, 9 np at 0, 2, 4 and 6 s, moving or still. Integer milliseconds, so the 120,
## 200 and 40 tick figures are exact. Nothing about it is ever shown.

var pool_max_ms: int = 6000
var drain_ms: int = 50
var refill_ms: int = 30
var pant_ticks: int = 160
var pant_every: int = 40

var pool_ms: int = 6000
var running: bool = false
## Run is refused until it is released, after the pool ran dry under a held Run.
var latched_off: bool = false
## Tick the current panting began, or -1; the next panting event's tick.
var pant_start: int = -1
var pant_next: int = -1
var breath_hold: bool = false


func _init() -> void:
	var tick_ms: float = 1000.0 / Tuning.f(&"net.tick_hz")
	pool_max_ms = roundi(Tuning.f(&"movement.stamina_pool") * 1000.0)
	drain_ms = roundi(Tuning.f(&"movement.stamina_drain_rate") * tick_ms)
	refill_ms = roundi(Tuning.f(&"movement.stamina_refill_rate") * tick_ms)
	pant_ticks = roundi(Tuning.f(&"movement.panting_duration") * Tuning.f(&"net.tick_hz"))
	pant_every = roundi(Tuning.f(&"movement.panting_interval") * Tuning.f(&"net.tick_hz"))
	pool_ms = pool_max_ms


## Before MNR-01's step: whether this tick's input may run.
func allow_run(input: InputRecord) -> bool:
	var held: bool = input != null and input.gait == InputRecord.Gait.RUN and input.move_dir != InputRecord.NO_DIRECTION
	if latched_off and not held:
		latched_off = false
	return pool_ms > 0 and not latched_off


## After the step, with the gait actually used. Returns how many panting events are due now.
func after_step(ran: bool, run_held: bool, now: int) -> int:
	if ran:
		pool_ms = maxi(pool_ms - drain_ms, 0)
		if not running:
			pant_start = -1  # a new run ends the panting; running carries its own voice loss
		running = true
		if pool_ms == 0 and run_held:
			latched_off = true
		return 0
	pool_ms = mini(pool_ms + refill_ms, pool_max_ms)
	if running:
		running = false
		pant_start = now
		pant_next = now
	var due: int = 0
	if pant_start >= 0:
		if now >= pant_start + pant_ticks:
			pant_start = -1
		elif now >= pant_next:
			pant_next += pant_every
			due = 0 if breath_hold else 1
	return due


func panting() -> bool:
	return pant_start >= 0


## SND-08 drops a fifth of voice frames for listeners while this is true.
func voice_loss() -> bool:
	return running or panting()


## Falling unconscious or dying stops panting at once.
func stop() -> void:
	running = false
	pant_start = -1


## A revived miner comes round with a full pool (Proposed).
func refill() -> void:
	pool_ms = pool_max_ms
	latched_off = false


func write_state(writer: SimStateWriter) -> void:
	writer.put_i64(pool_ms)
	writer.put_bool(running)
	writer.put_bool(latched_off)
	writer.put_i64(pant_start)
	writer.put_i64(pant_next)
	writer.put_bool(breath_hold)

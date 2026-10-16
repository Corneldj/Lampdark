class_name FanRoll
extends RefCounted
## DIR-02's Fan roll (Gameplay §6.9, §10.3). At the start of a relax whose ring (the peaker's, read
## at the peak) is director.fan_min_ring or deeper, one roll on FND-06's director.fan_roll stream
## against director.fan_roll_chance; on success the Fan surges (SND-16's start_surge) for its full
## noise.fan_surge_duration_s, however short the relax. A relax in ring 0 is never rolled.
## Server-only.

## SND-16's start: () -> void. Until it lands, the stand-in below keeps the surge's last tick.
var start_surge: Callable = Callable()
## FND-06's director.fan_roll stream (the run keeps its state for saves).
var rng: LbRng = null
var rolls: int = 0
var surges: int = 0
## The stand-in surge: the first tick after it (-1: none yet).
var surge_until: int = -1


## A relax began at `ring`: roll, and surge on success.
func on_relax_begun(run: RunState, ring: int) -> void:
	if ring < Tuning.i(&"director.fan_min_ring") or rng == null:
		return
	if not roll():
		return
	surges += 1
	if start_surge.is_valid():
		start_surge.call()
	else:
		surge_until = run.tick + roundi(Tuning.f(&"noise.fan_surge_duration_s") * Tuning.f(&"net.tick_hz"))
	Log.info("telemetry fan_surge ring=%d run_time=%.1f" % [ring, run.tick / Tuning.f(&"net.tick_hz")])


## One roll on the stream against director.fan_roll_chance (counted in `rolls`).
func roll() -> bool:
	rolls += 1
	return rng.chance_ppm(roundi(Tuning.f(&"director.fan_roll_chance") * 1000000.0))


## The stand-in surge is running (SND-16 owns the real one).
func surging(run: RunState) -> bool:
	return run.tick < surge_until

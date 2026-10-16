class_name AloneWatch
extends SimSystem
## RSC-09 (stage RECORD, after DIR-05's crew census): `alone_changed(miner, on)` whenever a human
## miner's AloneRules.is_alone turns on or off (the predicate's API is unchanged), the span of each
## spell under the solo rules as telemetry (solo_rules_span), and whether a miner was ever alone this
## run (LFT-11 tags outcomes ended_under_solo_rules). Server-only.

signal alone_changed(miner: int, on: bool)

## miner -> whether alone at the last tick
var alone: Dictionary = {}
## miner -> the tick their spell began
var since: Dictionary = {}
## miners ever alone this run
var ever: Dictionary = {}


func stage() -> int:
	return StageTable.Stage.RECORD


func order() -> int:
	return 12


func system_name() -> String:
	return "alone_watch"


func tick(run: RunState) -> void:
	if run.crew == null:
		return
	for e: int in run.crew.humans(run):
		var on: bool = AloneRules.is_alone(run, e)
		if on == Variants.flag(alone.get(e, false)):
			continue
		alone[e] = on
		if on:
			since[e] = run.tick
			ever[e] = true
		else:
			var span: float = (run.tick - int(Variants.number(since.get(e, run.tick)))) / Tuning.f(&"net.tick_hz")
			Log.info("telemetry solo_rules_span seconds=%.1f miner=%d" % [span, e])
			since.erase(e)
		alone_changed.emit(e, on)


## LFT-11: whether a miner played under the solo rules at any time this run.
func ended_under_solo_rules(miner: int) -> bool:
	return Variants.flag(ever.get(miner, false))

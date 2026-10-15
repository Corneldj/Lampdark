class_name RetreatCounters
extends RefCounted
## MNR-16 (Gameplay §4.7, §7.6): each creature's revolver hits toward its own growing retreat
## threshold, for the whole run. The first retreat needs revolver.retreat_thresholds[0] hits (3),
## each next one more than the last by one more each time (3, 4, 6, 9, 13, 18, 24, 31, then on by
## the same rule). Below it a hit only flinches; partial hits reset after revolver.partial_hit_reset
## (60 s) without a hit on that creature; at it, the creature retreats and the next row starts from
## zero. Hits during a retreat count toward the next threshold, and reaching it restarts the 120 s
## (Proposed). Kept in the run state for NET-09's snapshots. Server-only.

## creature entity -> {retreats_done, partial_hits, last_hit_tick}.
var counters: Dictionary = {}


## Hits the n-th retreat (1-based) needs.
static func needed(n: int) -> int:
	var table: Array[int] = Tuning.current.list_i(&"revolver.retreat_thresholds")
	if n <= table.size():
		return table[n - 1]
	var need: int = table[table.size() - 1]
	for k: int in range(table.size() + 1, n + 1):
		need += k - 1
	return need


## One hit on `creature` now: true when it reaches its threshold (the creature retreats).
func hit(run: RunState, creature: int) -> bool:
	var c: Dictionary = counters.get(creature, {"retreats_done": 0, "partial_hits": 0, "last_hit_tick": -1})
	var reset: int = roundi(Tuning.f(&"revolver.partial_hit_reset") * Tuning.f(&"net.tick_hz"))
	var last: int = int(Variants.number(c["last_hit_tick"]))
	if last >= 0 and run.tick - last >= reset:
		c["partial_hits"] = 0
	c["partial_hits"] = int(Variants.number(c["partial_hits"])) + 1
	c["last_hit_tick"] = run.tick
	var over: bool = int(Variants.number(c["partial_hits"])) >= needed(int(Variants.number(c["retreats_done"])) + 1)
	if over:
		c["retreats_done"] = int(Variants.number(c["retreats_done"])) + 1
		c["partial_hits"] = 0
	counters[creature] = c
	return over


func write_state(writer: SimStateWriter) -> void:
	var ids: Array = counters.keys()
	ids.sort()
	writer.put_i64(ids.size())
	for raw: Variant in ids:
		var c: Dictionary = counters[raw]
		writer.put_i64(int(Variants.number(raw)))
		writer.put_i64(int(Variants.number(c["retreats_done"])))
		writer.put_i64(int(Variants.number(c["partial_hits"])))
		writer.put_i64(int(Variants.number(c["last_hit_tick"])))

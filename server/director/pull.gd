class_name Pull
extends SimSystem
## DIR-03: the Pull (Gameplay §10.5, §A.7; GDD §C.7). A hidden value, 0 to pull.max, for every
## conscious miner (the Director's miners: Upright, Caught or Grabbed, never a Hand), starting at
## pull.initial and starting again there for a miner who comes round; the unconscious and the dead
## hold none. Each tick it moves by a rate a minute ÷ 1,200 (at 20 Hz):
## - inside base camp with every gate shut, the operator included: pull.home_rate_per_min (−20);
## - else by the miner's group (PullGroups, recomputed at 4 Hz): alone pull.rate_alone_per_min × D,
##   a pair pull.rate_pair_per_min × D, three or more pull.rate_group_per_min; D is DIR-04's
##   depth.pull_factor at the miner's own ring (base camp, gates open, counts as ring 0);
## - solo, or a lone human (DIR-05's AloneRules): always alone, every rate × pull.solo_multiplier,
##   and home pull.home_rate_solo_per_min (−10).
## When any hunt on a miner ends (CRT-01's hunt_ended), whatever its outcome, the Pull ebbs by
## pull.ebb. Creatures read it through the hunt gate's pull_of to choose whom they prefer and where
## they drift; the Draught still decides when. A relax never pauses it. It never changes a sense,
## a reach, a speed or a wind-up, never starts a hunt, adds a creature or ends a run, and is never
## shown or sent: the Inquiry reads only alone_since. Stage 16 (RECORD), after movement and MNR-03's
## life changes. Server-only.

const THRESHOLDS: Array[StringName] = [&"pull.threshold_attend", &"pull.threshold_marked", &"pull.threshold_anywhere"]
## Groups are worked out every this many ticks (4 Hz at 20 Hz); rates apply every tick.
const GROUP_EVERY: int = 5


## One miner's Pull.
class Record:
	extends RefCounted
	var value: float = 0.0
	## The tick they were last in a group of two or more (or first tracked).
	var alone_since: int = 0
	## Threshold (Pull) -> the tick they crossed it upward, while still at or above it.
	var crossed: Dictionary = {}
	## Ticks at or above pull.threshold_marked, for telemetry (GDD §15.12).
	var marked_ticks: int = 0

	func save() -> Dictionary:
		var c: Dictionary = {}
		for raw: Variant in crossed.keys():
			c[str(raw)] = crossed[raw]
		return {"value": value, "alone_since": alone_since, "crossed": c, "marked_ticks": marked_ticks}

	static func from(state: Dictionary) -> Record:
		var r: Record = Record.new()
		r.value = float(Variants.number(state.get("value", 0.0)))
		r.alone_since = int(Variants.number(state.get("alone_since", 0)))
		r.marked_ticks = int(Variants.number(state.get("marked_ticks", 0)))
		var c: Dictionary = Variants.dict(state.get("crossed", {}))
		for raw: Variant in c.keys():
			r.crossed[float(str(raw))] = int(Variants.number(c[raw]))
		return r

## A scenario's stand-in for the miner's ring: (miner) -> int. Default: DIR-04's, from their tile.
var ring_of: Callable = Callable()
## Tracked miner -> Record.
var records: Dictionary = {}
## Tracked miner -> group size, from the last grouping.
var groups: Dictionary = {}
var _grouped_at: int = -1000000
var _grouped: Array[int] = []


func stage() -> int:
	return StageTable.Stage.RECORD


func order() -> int:
	return 27 # after the Draught (16/25)


func system_name() -> String:
	return "Pull"


func bind(run: RunState) -> void:
	if run.creatures != null:
		run.creatures.gate.pull_of = value_of
		run.creatures.gate.hunt_ended.connect(_on_hunt_ended)
	if run.lone != null:
		run.lone.register("pull_half", func(r: RunState, miner: int) -> bool: return AloneRules.is_alone(r, miner))


## The Pull of a miner (0 for anyone untracked): CRT-01's pull_of.
func value_of(miner: int) -> float:
	var r: Record = records.get(miner, null)
	return r.value if r != null else 0.0


func at_least(miner: int, threshold: float) -> bool:
	var r: Record = records.get(miner, null)
	return r != null and r.value >= threshold


## Miners at or above pull.threshold_marked, ascending.
func marked_miners() -> Array[int]:
	var out: Array[int] = []
	var t: float = Tuning.f(&"pull.threshold_marked")
	for raw: Variant in records.keys():
		var e: int = int(Variants.number(raw))
		if at_least(e, t):
			out.append(e)
	out.sort()
	return out


## The miner with the highest Pull at or above `threshold`, 0 if none. Ties go to the one above the
## threshold longer, then to the lowest id.
func highest_at_or_above(threshold: float) -> int:
	var best: int = 0
	var best_value: float = -1.0
	var best_since: int = 0
	var ids: Array = records.keys()
	ids.sort()
	for raw: Variant in ids:
		var e: int = int(Variants.number(raw))
		var r: Record = records[raw]
		if r.value < threshold:
			continue
		var since: int = int(Variants.number(r.crossed.get(threshold, 0)))
		if best == 0 or r.value > best_value or (is_equal_approx(r.value, best_value) and since < best_since):
			best = e
			best_value = r.value
			best_since = since
	return best


## RSC-07's 'Alone for…': the tick the miner was last in a group of two or more; -1 if untracked.
func alone_since(miner: int) -> int:
	var r: Record = records.get(miner, null)
	return r.alone_since if r != null else -1


## FND-08's set_pull: a tracked miner's Pull, held to its range. False if not tracked.
func set_value(miner: int, value: float) -> bool:
	var r: Record = records.get(miner, null)
	if r == null:
		return false
	r.value = clampf(value, 0.0, Tuning.f(&"pull.max"))
	return true


func tick(run: RunState) -> void:
	var miners: Array[int] = Draught.conscious_humans(run)
	var now: Dictionary = {}
	for e: int in miners:
		if records.has(e):
			now[e] = records[e]
		else:
			var fresh: Record = Record.new() # a new miner, or one come round: from the start
			fresh.value = Tuning.f(&"pull.initial")
			fresh.alone_since = run.tick
			now[e] = fresh
	records = now
	if miners != _grouped or run.tick - _grouped_at >= GROUP_EVERY:
		groups = PullGroups.sizes(run, miners)
		_grouped = miners
		_grouped_at = run.tick
	var per_tick: float = 1.0 / (60.0 * Tuning.f(&"net.tick_hz"))
	var top: float = Tuning.f(&"pull.max")
	for e: int in miners:
		var r: Record = records[e]
		var size: int = int(Variants.number(groups.get(e, 1)))
		r.value = clampf(r.value + _rate(run, e, size) * per_tick, 0.0, top)
		if size >= 2:
			r.alone_since = run.tick
		_note_thresholds(run, e, r)


## The miner's rate a minute now (Gameplay §10.5's table).
func _rate(run: RunState, miner: int, size: int) -> float:
	var lone: bool = AloneRules.is_alone(run, miner)
	if run.crew != null and Variants.flag(run.crew.is_sealed_inside.call(miner)):
		return Tuning.f(&"pull.home_rate_solo_per_min") if lone else Tuning.f(&"pull.home_rate_per_min")
	var d: float = Depth.pull_factor(_ring(run, miner))
	if lone:
		return Tuning.f(&"pull.rate_alone_per_min") * d * Tuning.f(&"pull.solo_multiplier")
	if size <= 1:
		return Tuning.f(&"pull.rate_alone_per_min") * d
	if size == 2:
		return Tuning.f(&"pull.rate_pair_per_min") * d
	return Tuning.f(&"pull.rate_group_per_min")


## The miner's own ring; base camp (its gates open) counts as ring 0.
func _ring(run: RunState, miner: int) -> int:
	if run.base_camp != null and run.base_camp.is_inside(miner):
		return 0
	if ring_of.is_valid():
		return int(Variants.number(ring_of.call(miner)))
	return Depth.ring_for_miner(run, miner)


func _note_thresholds(run: RunState, miner: int, r: Record) -> void:
	for key: StringName in THRESHOLDS:
		var t: float = Tuning.f(key)
		if r.value >= t and not r.crossed.has(t):
			r.crossed[t] = run.tick
			Log.info("telemetry pull_threshold_crossed miner=%d threshold=%d ring=%d run_time=%.1f" % [miner, roundi(t),
				_ring(run, miner), run.tick / Tuning.f(&"net.tick_hz")])
		elif r.value < t and r.crossed.has(t):
			r.crossed.erase(t)
	if r.value >= Tuning.f(&"pull.threshold_marked"):
		r.marked_ticks += 1


## CRT-01: a hunt on `miner` ended, whatever its outcome: the ebb.
func _on_hunt_ended(_creature: Creature, miner: int, _reason: String) -> void:
	var r: Record = records.get(miner, null)
	if r != null:
		r.value = maxf(0.0, r.value - Tuning.f(&"pull.ebb"))


## GDD §15.12: seconds each miner has spent marked this run.
func marked_seconds(miner: int) -> float:
	var r: Record = records.get(miner, null)
	return r.marked_ticks / Tuning.f(&"net.tick_hz") if r != null else 0.0


func write_state(writer: SimStateWriter) -> void:
	var ids: Array = records.keys()
	ids.sort()
	writer.put_i64(ids.size())
	for raw: Variant in ids:
		var r: Record = records[raw]
		writer.put_i64(int(Variants.number(raw)))
		writer.put_f64(r.value)
		writer.put_i64(r.alone_since)
		writer.put_i64(r.marked_ticks)
		var ts: Array = r.crossed.keys()
		ts.sort()
		writer.put_i64(ts.size())
		for t: Variant in ts:
			writer.put_f64(float(Variants.number(t)))
			writer.put_i64(int(Variants.number(r.crossed[t])))
	writer.put_i64(_grouped_at)


## NET-09: values, alone_since, the crossings and the last grouping.
func save_state() -> Dictionary:
	var miners: Dictionary = {}
	for raw: Variant in records.keys():
		var r: Record = records[raw]
		miners[str(raw)] = r.save()
	var g: Dictionary = {}
	for raw: Variant in groups.keys():
		g[str(raw)] = groups[raw]
	return {"miners": miners, "groups": g, "grouped_at": _grouped_at}


func load_state(_r: RunState, state: Dictionary) -> void:
	records.clear()
	var miners: Dictionary = Variants.dict(state.get("miners", {}))
	for raw: Variant in miners.keys():
		records[int(str(raw))] = Record.from(Variants.dict(miners[raw]))
	groups.clear()
	var g: Dictionary = Variants.dict(state.get("groups", {}))
	for raw: Variant in g.keys():
		groups[int(str(raw))] = int(Variants.number(g[raw]))
	_grouped_at = int(Variants.number(state.get("grouped_at", -1000000)))
	_grouped.clear()

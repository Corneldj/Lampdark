class_name ApexController
extends SimSystem
## LFT-09 (stage PACING): the pit wakes (Gameplay §3.6, §7.1-§7.4, §10.3, §10.8). The apex latches on
## the engine's first catch (LFT-08's engine_caught) and clears when the cage leaves (LFT-10 calls
## cage_departed); a dry engine does not end it, and a later catch does not restart it. Latched, it
## is CRT-01's apex provider: the hunt gate's apex_on, so the creatures' turn toward base camp and
## every hunt it brings ignore the relax, while DIR-05's cap still binds and illusions keep their
## relax check. Each creature not retreating then turns toward base camp:
## - the Moth wakes wherever it is (asleep, a stir that always wakes) and prowls toward base camp:
##   its apex_point is the gate mouth nearest it, so a shut gate does not stop it short;
## - the Tapper comes to the rock beyond the brick arches: its apex_point is the end of the arches
##   nearest it, basecamp.arch_length_tiles along a gate's road;
## - the Stythe, unless it keeps a body, lurks in the dark roads within stythe.apex_lurk_gate_tiles
##   of a gate by path (Proposed): its apex_region, refreshed every few seconds, and its apex_point
##   the gate mouth nearest it.
## A creature retreating at the catch joins when its retreat ends (CRT-01's handler reads apex_on).
## The latch is saved in snapshots and the creatures told again on a resume; it is logged in the
## creature log (NET-07's record). FND-08's `apex on|off` forces it on test and QA servers.
## Never sent: clients learn of it only by what they perceive.

signal apex_started(at_tick: int)
signal apex_ended(at_tick: int)

## Ticks between refreshes of the Stythe's region and the arch ends (cells load as miners move).
const REFRESH_TICKS: int = 100

var active: bool = false
var started_tick: int = -1
var ended_tick: int = -1
## The Stythe's region: road tile -> steps by path from the nearest gate's outer mouth.
var region: Dictionary = {}
## The end of each gate's brick arches (a point on its road), for the Tapper.
var arch_ends: Array[Vector2] = []
## Each gate's outer mouth (the middle of the road just outside it), for the Stythe.
var mouths: Array[Vector2] = []
var _refreshed_at: int = -1
var _renotify: bool = false
var _run: RunState = null


func stage() -> int:
	return StageTable.Stage.PACING


func order() -> int:
	return 30


func system_name() -> String:
	return "apex"


func bind(run: RunState) -> void:
	_run = run
	if run.engine != null:
		run.engine.engine_caught.connect(func(at_tick: int) -> void: _on_caught(run, at_tick))
	if run.creatures != null:
		run.creatures.gate.apex_on = is_active
		run.creatures.spawned.connect(func(c: Creature) -> void: _attach(run, c))
		for c: Creature in run.creatures.creatures:
			_attach(run, c)


## CRT-01's apex provider.
func is_active() -> bool:
	return active


## LFT-10: the cage has left. The apex ends; it never begins again this run.
func cage_departed(run: RunState) -> void:
	if not active:
		return
	active = false
	ended_tick = run.tick
	_log(run, &"apex_ended", {"lasted_s": (run.tick - started_tick) / Tuning.f(&"net.tick_hz")})
	apex_ended.emit(run.tick)
	if run.creatures != null:
		for c: Creature in run.creatures.creatures:
			c.on_apex_ended(run)


## FND-08's `apex on|off`: starts or ends it whatever the engine (test and QA servers).
func force(run: RunState, on: bool) -> void:
	if on and not active:
		ended_tick = -1
		_start(run, run.tick, "forced")
	elif not on and active:
		cage_departed(run)


func _on_caught(run: RunState, at_tick: int) -> void:
	if active or ended_tick >= 0:
		return
	_start(run, at_tick, "engine")


func _start(run: RunState, at_tick: int, why: String) -> void:
	active = true
	started_tick = at_tick
	refresh(run)
	_log(run, &"apex_started", {"why": why})
	apex_started.emit(at_tick)
	_notify(run)


func _notify(run: RunState) -> void:
	if run.creatures == null:
		return
	for c: Creature in run.creatures.creatures:
		if not c.is_retreating():
			c.on_apex_started(run)


func _attach(run: RunState, c: Creature) -> void:
	if c is Moth:
		var m: Moth = c as Moth
		m.apex_point = func() -> Variant: return _nearest(mouths, m.position(run)) if active else null
	elif c is Tapper:
		var t: Tapper = c as Tapper
		t.apex_point = func() -> Variant: return _nearest(arch_ends, t.position(run)) if active else null
	elif c is StytheCreature:
		var st: StytheCreature = c as StytheCreature
		st.apex_point = func() -> Variant: return _nearest(mouths, st.position(run)) if active else null
		st.apex_region = func(tile: Vector2i) -> bool: return region.has(tile)
	if active and not c.is_retreating():
		c.on_apex_started(run)


func tick(run: RunState) -> void:
	_run = run
	if not active:
		return
	if _renotify:
		_renotify = false
		refresh(run)
		_notify(run)
	elif run.tick - _refreshed_at >= REFRESH_TICKS:
		refresh(run)


## The arch ends, the gates' mouths and the Stythe's region, from the mine as loaded.
func refresh(run: RunState) -> void:
	_refreshed_at = run.tick
	arch_ends.clear()
	mouths.clear()
	region.clear()
	if run.base_camp == null or run.base_camp.gate_system == null or run.mine == null:
		return
	var inside: Dictionary = run.base_camp.inside_tiles
	var arch: int = roundi(Tuning.f(&"basecamp.arch_length_tiles"))
	var reach: int = roundi(Tuning.f(&"stythe.apex_lurk_gate_tiles"))
	for spec: Dictionary in run.base_camp.gates:
		var gate: Gate = run.base_camp.gate_system.gate(str(spec["side"]))
		if gate == null:
			continue
		var mouth: Vector2 = Vector2(gate.middle() + gate.outward) + Vector2(0.5, 0.5)
		mouths.append(mouth)
		var steps: Dictionary = _flood(run, gate, inside, maxi(arch, reach))
		var far: Array[Vector2i] = []
		for raw: Variant in steps.keys():
			var t: Vector2i = raw
			var d: int = int(Variants.number(steps[t]))
			if d == arch:
				far.append(t)
			if d <= reach and int(Variants.number(region.get(t, reach + 1))) > d:
				region[t] = d
		# The arches' end: the road tile `arch` steps out nearest the gate's straight line (straight
		# on, if not loaded), not a side road's.
		var ahead: Vector2 = Vector2(gate.middle() + gate.outward * arch) + Vector2(0.5, 0.5)
		var centres: Array[Vector2] = []
		for t: Vector2i in far:
			centres.append(Vector2(t) + Vector2(0.5, 0.5))
		var best: Variant = _nearest(centres, ahead)
		arch_ends.append(best if best != null else ahead)


## Steps by path over walkable floor (shut doors are walls) from a gate's outer tiles, never into
## base camp, up to `limit`.
func _flood(run: RunState, gate: Gate, inside: Dictionary, limit: int) -> Dictionary:
	var steps: Dictionary = {}
	var queue: Array[Vector2i] = []
	for t: Vector2i in gate.tiles:
		var first: Vector2i = t + gate.outward
		if not steps.has(first) and not inside.has(first) and run.mine.native.is_walkable(first, false):
			steps[first] = 1
			queue.append(first)
	var head: int = 0
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	while head < queue.size():
		var t: Vector2i = queue[head]
		head += 1
		var d: int = int(Variants.number(steps[t]))
		if d >= limit:
			continue
		for step: Vector2i in dirs:
			var n: Vector2i = t + step
			if steps.has(n) or inside.has(n) or not run.mine.native.is_walkable(n, false):
				continue
			steps[n] = d + 1
			queue.append(n)
	return steps


static func _nearest(points: Array[Vector2], from: Vector2) -> Variant:
	var best: Variant = null
	var best_d: float = INF
	for p: Vector2 in points:
		var d: float = p.distance_squared_to(from)
		if d < best_d:
			best_d = d
			best = p
	return best


func _log(run: RunState, what: StringName, fields: Dictionary) -> void:
	if run.creatures != null:
		run.creatures.log.add(run.tick, what, fields)
	Log.info("apex: %s %s" % [what, str(fields)])


func write_state(writer: SimStateWriter) -> void:
	writer.put_bool(active)
	writer.put_i64(started_tick)
	writer.put_i64(ended_tick)


## NET-09: the latch (a resume can land inside the apex).
func save_state() -> Dictionary:
	return {"active": active, "started_tick": started_tick, "ended_tick": ended_tick}


func load_state(_run_state: RunState, state: Dictionary) -> void:
	active = Variants.flag(state.get("active", false))
	started_tick = int(Variants.number(state.get("started_tick", -1)))
	ended_tick = int(Variants.number(state.get("ended_tick", -1)))
	_renotify = active

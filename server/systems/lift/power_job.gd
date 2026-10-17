class_name PowerJob
extends SimSystem
## LFT-05 (stage WORLD, after the jobs for two and the tank, before the engine): the Power job at
## the District Substation (Gameplay §3.3, §3.5, §3.9, §4.6, §12.4, §13.6, §A.6; GDD §14.2). Power
## is always on the list and is worked at the one substation, in three steps:
## 1. **The burnt links**: lift.power_links_s of held interact at the fuse board, standing still,
##    the wire cutters on the belt or in hand (Proposed: one action clears them all). The cutters
##    are never used up; let go early and nothing changes.
## 2. **A fuse**: lift.power_fuse_s each at the board (MNR-12's fit_action: the fuse is spent only
##    when the fit completes), refused before the links are cleared and after the
##    lift.power_fuses_required-th. Clearing and fitting are silent (Proposed).
## 3. **The main switch**: LFT-04's CuePress once the links are clear and every fuse is in. Taking
##    the trip lever catches it (an 8 np click: the cue each presser's client times); a throw at
##    the switch on 'Now!' within the window closes it: SND-02's 20 np clunk at the switch, power
##    on, LFT-03's Power done, `power_on` emitted once. A miss changes nothing; the trip is let go
##    and taken again for a new cue. Alone, the trip holds LFT-04's hold-over after its miner lets go.
## Power never goes off. It works base camp's relighter and battery rack (LFT-01) and releases the
## winder's brake (Start needs Power, LFT-03); the switchboard (LFT-13) and the pit phones' lines
## (LFT-12) read board_wakes() and lines_live(), which Dead Lines keeps false.
##
## **Where.** The fixtures are the substation template's poi_slot anchors (substation.fuse_board,
## substation.trip_lever and substation.main_switch, as base camp's fixtures are; GEN-16 authors
## them). Where no template fits the site, a stand-in round the floor nearest the middle of the
## plan's substation site (Proposed): the board there, the trip and the switch on the nearest floor
## at least two tiles from it and from each other. The fixtures are FIXTURE entities while their cell is
## loaded; the job's state is the run's, kept in every snapshot (NET-09).
##
## Hired Hands never clear, fit, hold or throw. Clients learn only what they see: the fixtures'
## look at 0.30 (FixtureKinds, NET-04) and the sounds; never the substation's place, power as data,
## or the board's state unseen. Server-only.

signal power_on(tick: int)

const FIXTURES: Array[String] = ["fuse_board", "trip_lever", "main_switch"]
## A substation template's anchor kinds -> fixture.
const ANCHOR_KINDS: Dictionary = {"substation.fuse_board": "fuse_board", "substation.trip_lever": "trip_lever",
	"substation.main_switch": "main_switch"}

var links_cleared: bool = false
var fuses_fitted: int = 0
var switch_closed: bool = false
## The tick power came on (-1: not yet).
var on_tick: int = -1
## MOD-10's Dead Lines: no board, no phones; the brake, the relighter and the rack still answer.
var dead_lines: bool = false
## Fixture name -> tile centre; fixture name -> its FIXTURE entity while its cell is loaded.
var anchors: Dictionary = {}
var fixtures: Dictionary = {}
## Where the anchors came from: "template", "stand_in" or "set" (a test's, or a fixed map's).
var anchors_from: String = ""
## The main switch while it can be thrown.
var main_switch: CuePress = null
## NET-07: {tick, what, ...} for each step, cue, throw and miss.
var log: Array[Dictionary] = []
var refused: Array[Dictionary] = []
var _drop_switch: bool = false
## The plan's substation site ({door, cells}), read once; {} with none.
var _site: Dictionary = {}
var _site_read: bool = false
var _run: RunState = null


func stage() -> int:
	return StageTable.Stage.WORLD


func order() -> int:
	return 37


func system_name() -> String:
	return "power"


func bind(run: RunState) -> void:
	_run = run
	if run.inventory != null:
		run.inventory.targets.providers.append(_targets)


#region Queries

func is_on() -> bool:
	return switch_closed


## LFT-13: the switchboard wakes with power, never under Dead Lines.
func board_wakes() -> bool:
	return switch_closed and not dead_lines


## LFT-12: the uncut lines are live with power, never under Dead Lines.
func lines_live() -> bool:
	return switch_closed and not dead_lines


func fuses_required() -> int:
	return roundi(Tuning.f(&"lift.power_fuses_required"))


## Why `miner` may not clear the links now, or "".
func why_not_clear(run: RunState, miner: int) -> String:
	if ToolsParts.is_hand(run, miner):
		return "a Hand"
	if links_cleared:
		return "cleared"
	if run.tools_parts == null or not run.tools_parts.has_tool(run, [miner], ItemKinds.Kind.WIRE_CUTTERS):
		return "no cutters"
	return ""


## Why `miner` may not fit a fuse now, or "".
func why_not_fit(run: RunState, miner: int) -> String:
	if ToolsParts.is_hand(run, miner):
		return "a Hand"
	if not links_cleared:
		return "links"
	if fuses_fitted >= fuses_required():
		return "full"
	if run.tools_parts == null or run.tools_parts.count_part(run, miner, ItemKinds.Kind.FUSE) < 1:
		return "no fuse"
	return ""

#endregion


#region Where

## The fixtures at these tiles (a test's, or a fixed map's), unless they have some already.
func set_anchors(fuse_board: Vector2i, trip_lever: Vector2i, main_switch_tile: Vector2i, from: String = "set") -> void:
	anchors = {"fuse_board": Vector2(fuse_board) + Vector2(0.5, 0.5), "trip_lever": Vector2(trip_lever) + Vector2(0.5, 0.5),
		"main_switch": Vector2(main_switch_tile) + Vector2(0.5, 0.5)}
	anchors_from = from
	_note(_run, "placed", {"from": from, "fuse_board": fuse_board})


## The plan's substation site, once: GEN-08's planned site of kind substation ({} with no plan).
func _substation_site(run: RunState) -> Dictionary:
	if _site_read:
		return _site
	_site_read = true
	if run.placed == null or run.placed.layouts == null:
		return _site
	var plan: Dictionary = run.placed.layouts.plan_dict()
	dead_lines = dead_lines or str(plan.get("hard_variant", "")) == "dead_lines"
	for raw: Variant in Variants.array(plan.get("sites", [])):
		var site: Dictionary = Variants.dict(raw)
		if str(site.get("kind", "")) == "substation":
			_site = site
			break
	return _site


## The anchors from the substation's template once its cells are loaded, else the stand-in once its
## door cell is.
func _find_anchors(run: RunState) -> void:
	if not anchors.is_empty() or run.mine == null:
		return
	var site: Dictionary = _substation_site(run)
	if site.is_empty():
		return
	var cells: Array[Vector2i] = []
	cells.assign(Variants.array(site.get("cells", [])))
	var found: Dictionary = {}
	for cell: Vector2i in cells:
		if not run.mine.native.is_loaded(cell):
			continue
		for raw: Variant in run.mine.native.anchors(cell):
			var a: Dictionary = raw
			var kind: String = str(a.get("kind", ""))
			if ANCHOR_KINDS.has(kind):
				found[ANCHOR_KINDS[kind]] = WorldCoords.tile_of(cell, Vector2i(int(Variants.number(a["x"])), int(Variants.number(a["y"]))))
	if found.size() == FIXTURES.size():
		var board: Vector2i = found["fuse_board"]
		var trip: Vector2i = found["trip_lever"]
		var throw: Vector2i = found["main_switch"]
		set_anchors(board, trip, throw, "template")
		return
	var door: Vector2i = site.get("door", cells[0] if not cells.is_empty() else Vector2i.ZERO)
	if run.mine.native.is_loaded(door):
		_stand_in(run, cells)


## The stand-in (Proposed): the board on the floor nearest the site's middle, the trip and the switch
## on the nearest floor at least two tiles (Chebyshev) from it and from each other.
func _stand_in(run: RunState, cells: Array[Vector2i]) -> void:
	var middle: Vector2 = Vector2.ZERO
	for cell: Vector2i in cells:
		middle += Vector2(cell * WorldIds.CELL_TILES) + Vector2(WorldIds.CELL_TILES, WorldIds.CELL_TILES) / 2.0
	middle /= float(maxi(1, cells.size()))
	var floor: Array[Vector2i] = []
	for cell: Vector2i in cells:
		if not run.mine.native.is_loaded(cell):
			continue
		for y: int in WorldIds.CELL_TILES:
			for x: int in WorldIds.CELL_TILES:
				var t: Vector2i = cell * WorldIds.CELL_TILES + Vector2i(x, y)
				if run.mine.native.is_walkable(t):
					floor.append(t)
	if floor.is_empty():
		return
	var by_middle: Callable = func(a: Vector2i, b: Vector2i) -> bool:
		var da: float = (Vector2(a) + Vector2(0.5, 0.5)).distance_squared_to(middle)
		var db: float = (Vector2(b) + Vector2(0.5, 0.5)).distance_squared_to(middle)
		return da < db if da != db else (a.y < b.y or (a.y == b.y and a.x < b.x))
	floor.sort_custom(by_middle)
	var board: Vector2i = floor[0]
	var picked: Array[Vector2i] = [board]
	for t: Vector2i in floor:
		var apart: bool = true
		for p: Vector2i in picked:
			apart = apart and maxi(absi(t.x - p.x), absi(t.y - p.y)) >= 2
		if apart:
			picked.append(t)
			if picked.size() == FIXTURES.size():
				break
	if picked.size() == FIXTURES.size():
		set_anchors(picked[0], picked[1], picked[2], "stand_in")


## The fixtures exist while their cell is loaded.
func _keep_fixtures(run: RunState) -> void:
	for name: String in FIXTURES:
		var at: Vector2 = anchors[name]
		var loaded: bool = run.mine == null or run.mine.native.is_loaded(WorldCoords.cell_of(Vector2i(floori(at.x), floori(at.y))))
		var e: int = int(Variants.number(fixtures.get(name, 0)))
		var exists: bool = e != 0 and run.registry.has(e)
		if loaded and not exists:
			fixtures[name] = run.registry.create(WorldIds.EntityKind.FIXTURE, at).id
		elif not loaded and exists:
			run.registry.destroy(e)
			fixtures.erase(name)
		elif not exists:
			fixtures.erase(name)

#endregion


#region The steps

## Clearing the burnt links: lift.power_links_s of held interact at the board, standing still.
func clear_action(run: RunState, miner: int) -> TimedAction:
	var a: TimedAction = TimedAction.make(miner, &"clear_links", Tuning.f(&"lift.power_links_s"), InputRecord.HOLD_INTERACT)
	a.needs_still = true
	a.target_point = anchors.get("fuse_board", Vector2.ZERO)
	a.reach = Tuning.f(&"vision.touch_range_tiles")
	a.valid = func() -> bool: return why_not_clear(run, miner).is_empty()
	a.effect = func() -> void: _cleared(run, miner)
	return a


## Fitting a fuse: lift.power_fuse_s at the board, the fuse spent on completion (MNR-12).
func fit_action(run: RunState, miner: int) -> TimedAction:
	var a: TimedAction = run.tools_parts.fit_action(run, miner, ItemKinds.Kind.FUSE, 1, Tuning.f(&"lift.power_fuse_s"),
		InputRecord.HOLD_INTERACT, func() -> void: _fitted(run, miner))
	if a == null:
		return null
	a.verb = &"fit_fuse"
	a.needs_still = true
	a.target_point = anchors.get("fuse_board", Vector2.ZERO)
	a.reach = Tuning.f(&"vision.touch_range_tiles")
	var parts_valid: Callable = a.valid
	a.valid = func() -> bool: return why_not_fit(run, miner).is_empty() and Variants.flag(parts_valid.call())
	return a


func _cleared(run: RunState, miner: int) -> void:
	links_cleared = true
	_note(run, "links_cleared", {"miner": miner})


func _fitted(run: RunState, miner: int) -> void:
	fuses_fitted += 1
	_note(run, "fuse_fitted", {"miner": miner, "fuses": fuses_fitted})
	if fuses_fitted >= fuses_required():
		_switch_on(run)


## The main switch as LFT-04's CuePress: H the trip lever (ready at once), P the switch.
func _switch_on(run: RunState) -> void:
	if main_switch != null or switch_closed or run.two_miner == null or anchors.is_empty():
		return
	var trip: Vector2 = anchors["trip_lever"]
	var cue: Callable = func(r: RunState, _job: CuePress) -> int:
		# The trip caught as it is taken: the cue every presser's client times.
		r.noise.emit(NoiseTypes.Type.TRIP_LEVER, Vector2i(floori(trip.x), floori(trip.y)))
		_note(r, "trip_held", {})
		return NoiseTypes.Type.TRIP_LEVER
	var ok: Callable = func(r: RunState, _job: CuePress, presser: int) -> void: _close(r, presser)
	var miss: Callable = func(r: RunState, _job: CuePress, why: String) -> void: _note(r, "miss", {"why": why})
	main_switch = CuePress.make({"name": "main_switch", "holder_anchor": trip, "presser_anchor": anchors["main_switch"],
		"hold_to_ready_s": 0.0, "on_cue": cue, "on_success": ok, "on_miss": miss})
	run.two_miner.add(main_switch)


## A throw on 'Now!': the clunk, power on (once), Power done.
func _close(run: RunState, presser: int) -> void:
	if switch_closed:
		return
	switch_closed = true
	on_tick = run.tick
	_drop_switch = true
	if run.noise != null:
		var at: Vector2 = anchors["main_switch"]
		run.noise.emit(NoiseTypes.Type.MAIN_SWITCH, Vector2i(floori(at.x), floori(at.y)))
	_note(run, "power_on", {"miner": presser})
	_power_effects(run)
	if run.repair != null:
		run.repair.mark_done(run, &"power")
	power_on.emit(run.tick)


## What power works at once: base camp's relighter and battery rack (LFT-01). The brake is Start's
## (LFT-03's can_start), the board and the lines read board_wakes() and lines_live().
func _power_effects(run: RunState) -> void:
	if run.base_camp != null:
		run.base_camp.powered = true

#endregion


func tick(run: RunState) -> void:
	_run = run
	_find_anchors(run)
	if anchors.is_empty():
		return
	_keep_fixtures(run)
	if _drop_switch:
		_drop_switch = false
		if main_switch != null and run.two_miner != null:
			run.two_miner.remove(main_switch)
		main_switch = null
	if not switch_closed and links_cleared and fuses_fitted >= fuses_required() and main_switch == null:
		_switch_on(run)
	_input(run)


## A fresh interact at the board starts its next step (or is refused).
func _input(run: RunState) -> void:
	if run.movement == null or run.inventory == null:
		return
	for slot: int in run.movement.miner_slots():
		var c: InputBuffer.Consumed = run.input_for(slot)
		var miner: int = run.movement.miner(slot).entity_id
		if c == null or run.inventory.actions.has(miner) or run.inventory.is_partner(miner) \
				or not run.inventory.is_fresh(miner, c.record.holds, InputRecord.HOLD_INTERACT):
			continue
		var target: Dictionary = run.inventory.targets.pick(run, miner, slot, run.inventory.world)
		if StringName(str(target.get("kind", ""))) != &"fuse_board":
			continue
		run.inventory.mark_spent(miner, InputRecord.HOLD_INTERACT)
		var why: String = why_not_clear(run, miner) if not links_cleared else why_not_fit(run, miner)
		if not why.is_empty():
			refused.append({"tick": run.tick, "miner": miner, "why": why})
			continue
		var a: TimedAction = clear_action(run, miner) if not links_cleared else fit_action(run, miner)
		if a != null:
			run.inventory.start_action(run, a)


## MNR-04's interaction targets: the board in touch range while it has a step left.
func _targets(_run_state: RunState, _actor: int, at: Vector2, reach: float) -> Array:
	if not anchors.has("fuse_board") or int(Variants.number(fixtures.get("fuse_board", 0))) == 0:
		return []
	if links_cleared and fuses_fitted >= fuses_required():
		return []
	var board: Vector2 = anchors["fuse_board"]
	if at.distance_to(board) > reach + 1e-9:
		return []
	return [{"kind": &"fuse_board", "id": int(Variants.number(fixtures["fuse_board"])), "point": board}]


## Each fixture's identity bits (FixtureKinds): the board's steps, the trip held, the switch closed.
func fixture_bits() -> Dictionary:
	var out: Dictionary = {}
	var board: int = int(Variants.number(fixtures.get("fuse_board", 0)))
	if board != 0:
		out[board] = FixtureKinds.fuse_board(links_cleared, fuses_fitted, fuses_fitted >= fuses_required())
	var trip: int = int(Variants.number(fixtures.get("trip_lever", 0)))
	if trip != 0:
		out[trip] = FixtureKinds.trip_lever(main_switch != null and main_switch.state == CuePress.State.READY)
	var switch_e: int = int(Variants.number(fixtures.get("main_switch", 0)))
	if switch_e != 0:
		out[switch_e] = FixtureKinds.main_switch(switch_closed)
	return out


func _note(run: RunState, what: String, fields: Dictionary) -> void:
	var entry: Dictionary = {"tick": run.tick if run != null else -1, "what": what}
	entry.merge(fields)
	log.append(entry)
	Log.info("power: %s %s" % [what, str(fields)])


func write_state(writer: SimStateWriter) -> void:
	writer.put_bool(links_cleared)
	writer.put_i64(fuses_fitted)
	writer.put_bool(switch_closed)
	writer.put_i64(on_tick)


## NET-09: the steps done, power, and the fixtures' entities (the restored registry keeps them).
func save_state() -> Dictionary:
	return {"links_cleared": links_cleared, "fuses_fitted": fuses_fitted, "switch_closed": switch_closed, "on_tick": on_tick,
		"dead_lines": dead_lines, "fixtures": fixtures.duplicate()}


func load_state(run: RunState, state: Dictionary) -> void:
	links_cleared = Variants.flag(state.get("links_cleared", false))
	fuses_fitted = int(Variants.number(state.get("fuses_fitted", 0)))
	switch_closed = Variants.flag(state.get("switch_closed", false))
	on_tick = int(Variants.number(state.get("on_tick", -1)))
	dead_lines = Variants.flag(state.get("dead_lines", dead_lines))
	if main_switch != null and run.two_miner != null:
		run.two_miner.remove(main_switch)
	main_switch = null
	fixtures = {}
	var saved: Dictionary = Variants.dict(state.get("fixtures", {}))
	for name: String in FIXTURES:
		var e: int = int(Variants.number(saved.get(name, 0)))
		if e != 0 and run.registry.has(e):
			fixtures[name] = e
	if switch_closed:
		_power_effects(run)

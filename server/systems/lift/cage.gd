class_name Cage
extends SimSystem
## LFT-10 (stage WORLD, after the engine): the cage, the signal cord and the ride (Gameplay §3.6,
## §3.8, §3.9, §7.3, §13.7, §13.9, §13.10; GDD §2.5). The cage stands askew in its guides on GEN-02's
## cage_deck, wedged fast only while Free the cage is drawn and not done. Once the engine has run up
## (LFT-08), the cord (SignalCord) counts the pulls of the conscious miners aboard; at a majority the
## hold bell (20 np, lift.hold_bell_s) rings at the cage and departure is committed, votes no longer
## mattering, unless the engine runs dry during it, which cancels departure. When the bell ends,
## everything aboard (miners in any state, Hands, Bess, bodies, loads and items: centres on a deck
## tile) moves with a fixed offset into the ride zone (ShaftRide's off-plane cell), the deck site
## becomes an open shaft that is never boarded again (base camp's OPEN_SHAFT_COLLAPSE), the cord is
## gone, and cage_departed(snapshot) tells LFT-08's engine, LFT-09's apex, LFT-14's map table and
## NET-07. There is one ride: lift.ride_s up the shaft, the first half bare rock. A Tapper not
## retreating follows into the shaft's rock when its straight-line distance to the deck at rock speed
## lets it (Proposed); there it hunts as anywhere, a strike's pin stopping the cage until it ends, and
## it drops back below when the walls turn to brick. At the top, cage_surfaced(snapshot) for LFT-11.
## Clients get the bell, the cage's look and the walls; never a count, a threshold, the bell's
## time or progress.

signal cage_departed(snapshot: Dictionary)
signal cage_surfaced(snapshot: Dictionary)

enum State { WAITING = 0, BELL = 1, RIDING = 2, SURFACED = 3 }

var state: State = State.WAITING
var cord: SignalCord = SignalCord.new()
var ride: ShaftRide = ShaftRide.new()
var bell_until: int = -1
## The deck (world tiles) and the cord's point.
var deck: Rect2i = Rect2i()
var cord_point: Vector2 = Vector2.ZERO
## FIXTURE entities: "cage", "cord" and, once it has left, "shaft".
var fixtures: Dictionary = {}
## The departure's snapshot: {tick, entities: [...], miners: [...]}.
var snapshot: Dictionary = {}
## NET-07: {tick, what, ...} for pulls, the bell, cancels, departure, stops and the surface.
var log: Array[Dictionary] = []
var refused: Array[Dictionary] = []
## The Tapper following into the shaft: the tick it reaches the shaft's rock (-1 none), and where it
## left from (to go back below).
var tapper_due: int = -1
var tapper_from: Vector2 = Vector2.ZERO
var tapper_in_shaft: bool = false
var _placed: bool = false


func stage() -> int:
	return StageTable.Stage.WORLD


func order() -> int:
	return 39


func system_name() -> String:
	return "cage"


func bind(run: RunState) -> void:
	if run.inventory != null:
		run.inventory.targets.providers.append(_targets)
	if run.holds != null:
		run.holds.grab_begun.connect(func(grab_id: int, kind: GrabHold.Kind, _creature: int, victim: int) -> void:
			if kind == GrabHold.Kind.TAPPER_PIN and state == State.RIDING and snapshot_has(victim):
				ride.stop_for_pin(grab_id)
				_note(run, "stopped", {"pin": grab_id, "miner": victim}))
		run.holds.grab_ended.connect(func(grab_id: int, _outcome: GrabHold.Outcome) -> void:
			if ride.resume(grab_id):
				_note(run, "resumed", {"pin": grab_id}))


#region Queries

## Wedged fast only while Free the cage is drawn and not done (LFT-07 frees it).
func is_wedged(run: RunState) -> bool:
	return run.repair != null and run.repair.list != null and run.repair.list.jobs.has(&"free_cage") and not run.repair.is_done(&"free_cage")


func is_departed() -> bool:
	return state == State.RIDING or state == State.SURFACED


## The entities that left aboard.
func riders() -> Array[int]:
	var out: Array[int] = []
	for raw: Variant in Variants.array(snapshot.get("entities", [])):
		out.append(int(Variants.number(raw)))
	return out


func snapshot_has(entity: int) -> bool:
	return riders().has(entity)


## CRT-09: whether the shaft about the cage is bare rock now.
func is_bare_rock() -> bool:
	return state == State.RIDING and ride.is_bare_rock()


## GEN-11: the ride zone's cells (none before departure): no window there, never evicted.
func ride_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if is_departed():
		out.append(ShaftRide.RIDE_CELL)
	return out


func is_ride_cell(cell: Vector2i) -> bool:
	return is_departed() and cell == ShaftRide.RIDE_CELL


## The cage's look: standing askew, wedged fast, riding or stopped in the dark.
func look(run: RunState) -> int:
	if state == State.RIDING:
		return FixtureKinds.CageLook.RIDING if ride.is_moving() else FixtureKinds.CageLook.STOPPED
	return FixtureKinds.CageLook.WEDGED if is_wedged(run) else FixtureKinds.CageLook.STANDING

#endregion


func tick(run: RunState) -> void:
	_place(run)
	if not _placed:
		return
	match state:
		State.WAITING:
			cord.prune(run, deck)
			_input(run)
			if not is_wedged(run) and run.engine != null and run.engine.run_up_complete(run) and cord.majority(run, deck):
				_ring(run)
		State.BELL:
			if run.engine == null or not run.engine.is_running():
				_cancel(run, "dry")
			elif run.tick >= bell_until:
				_depart(run)
		State.RIDING:
			_tapper_follow(run)
			var was_bare: bool = ride.is_bare_rock()
			if ride.step(run.tick):
				_surface(run)
			elif was_bare and not ride.is_bare_rock():
				_line_with_brick(run)


#region The cord and the bell

## A fresh interact on the cord: a pull, or a refusal (a pull before the run-up is not stored).
func _input(run: RunState) -> void:
	if run.movement == null or run.inventory == null:
		return
	for slot: int in run.movement.miner_slots():
		var c: InputBuffer.Consumed = run.input_for(slot)
		var miner: int = run.movement.miner(slot).entity_id
		if c == null or run.inventory.actions.has(miner) or not run.inventory.is_fresh(miner, c.record.holds, InputRecord.HOLD_INTERACT):
			continue
		var target: Dictionary = run.inventory.targets.pick(run, miner, slot, run.inventory.world)
		if StringName(str(target.get("kind", ""))) != &"signal_cord":
			continue
		run.inventory.mark_spent(miner, InputRecord.HOLD_INTERACT)
		var why: String = cord.why_not(run, miner, deck)
		if is_wedged(run):
			why = "wedged"
		if not why.is_empty():
			refused.append({"tick": run.tick, "miner": miner, "why": why})
			continue
		cord.pull(run, miner)
		_note(run, "pull", {"miner": miner})


func _ring(run: RunState) -> void:
	state = State.BELL
	bell_until = run.tick + roundi(Tuning.f(&"lift.hold_bell_s") * Tuning.f(&"net.tick_hz"))
	if run.noise != null:
		run.noise.emit(NoiseTypes.Type.HOLD_BELL, _deck_tile(), {"duration_s": Tuning.f(&"lift.hold_bell_s"), "source": _fixture("cage")})
	_note(run, "bell", {"pullers": cord.pullers(), "required": SignalCord.required(run, deck)})


## The engine ran dry during the bell: no departure; the cord waits for a new start and run-up.
func _cancel(run: RunState, why: String) -> void:
	state = State.WAITING
	bell_until = -1
	cord.clear()
	_note(run, "cancelled", {"why": why})

#endregion


#region Departure and the ride

func _depart(run: RunState) -> void:
	var entities: Array[int] = _aboard_now(run)
	var miners: Array[int] = []
	for e: int in entities:
		if run.registry.get_entity(e).kind == WorldIds.EntityKind.MINER:
			miners.append(e)
			if run.loads != null and run.loads.carrying(e):
				run.loads.set_down(run, e, &"departure")
	snapshot = {"tick": run.tick, "entities": entities, "miners": miners}
	# The ride zone, then everything aboard into it with one offset.
	if run.mine != null and not run.mine.native.is_loaded(ShaftRide.RIDE_CELL):
		run.mine.native.commit(ShaftRide.cell_data(deck.size, false))
		if run.light != null:
			run.light.grid.on_cell_loaded(ShaftRide.RIDE_CELL)
	var offset: Vector2 = Vector2(ShaftRide.deck_origin() - deck.position)
	for e: int in entities:
		_move(run, e, run.registry.get_entity(e).position + offset)
	var cage_fixture: int = _fixture("cage")
	if cage_fixture != 0 and run.registry.has(cage_fixture):
		run.registry.move(cage_fixture, Vector2(ShaftRide.deck_origin()) + Vector2(deck.size) / 2.0)
	# The deck site: an open shaft, the cord gone.
	if run.mine != null:
		run.mine.native.set_collapse(Vector2i.ZERO, Basecamp.OPEN_SHAFT_COLLAPSE, true)
	var cord_fixture: int = _fixture("cord")
	if cord_fixture != 0 and run.registry.has(cord_fixture):
		run.registry.destroy(cord_fixture)
	fixtures.erase("cord")
	cord.clear()
	fixtures["shaft"] = run.registry.create(WorldIds.EntityKind.FIXTURE, Vector2(deck.get_center()) + Vector2(0.5, 0.5)).id
	state = State.RIDING
	ride.departed_at = run.tick
	_note(run, "departed", {"miners": miners, "entities": entities.size()})
	if run.engine != null:
		run.engine.depart(run)
	if run.apex != null:
		run.apex.cage_departed(run)
	if run.sheets != null and run.sheets.table != null:
		run.sheets.table.freeze(run, "cage_departed")
	_plan_tapper(run)
	cage_departed.emit(snapshot)


## Everything whose centre lies on the deck now: miners in any state (Hands and bodies among them),
## Bess, items and loads; never a creature or a fixture.
func _aboard_now(run: RunState) -> Array[int]:
	var out: Array[int] = []
	var ids: Array = Array(run.registry.ids())
	ids.sort()
	for raw: Variant in ids:
		var id: int = int(Variants.number(raw))
		var e: SimEntity = run.registry.get_entity(id)
		if e == null or not [WorldIds.EntityKind.MINER, WorldIds.EntityKind.BESS, WorldIds.EntityKind.ITEM].has(e.kind):
			continue
		if SignalCord.aboard(run, id, deck):
			out.append(id)
	return out


func _move(run: RunState, entity: int, at: Vector2) -> void:
	var e: SimEntity = run.registry.get_entity(entity)
	if e.kind == WorldIds.EntityKind.MINER and run.movement != null:
		run.movement.place(run, entity, at)
	else:
		run.registry.move(entity, at)
		if e.kind == WorldIds.EntityKind.ITEM and run.inventory != null:
			run.inventory.world.moved(run, entity)  # GEN-13's diff follows it up the shaft


func _line_with_brick(run: RunState) -> void:
	if run.mine != null:
		run.mine.native.set_collapse(ShaftRide.RIDE_CELL, ShaftRide.WALL_COLLAPSE, true)
	_note(run, "brick", {"progress_s": ride.progress_ticks / Tuning.f(&"net.tick_hz")})
	# The Tapper cannot be in brick: back below.
	var t: Tapper = _tapper(run)
	if t != null and tapper_in_shaft:
		tapper_in_shaft = false
		run.creatures.relocate(run, t, tapper_from)
	tapper_due = -1


func _surface(run: RunState) -> void:
	state = State.SURFACED
	var aboard: Array[int] = []
	for e: int in riders():
		if run.registry.has(e):
			aboard.append(e)
	var top: Dictionary = {"tick": run.tick, "entities": aboard, "miners": snapshot.get("miners", []), "departed": ride.departed_at}
	_note(run, "surfaced", {"after_s": (run.tick - ride.departed_at) / Tuning.f(&"net.tick_hz")})
	cage_surfaced.emit(top)


## The Tapper follows into the shaft's rock after its straight-line distance to the deck at rock
## speed, if that lands within the bare rock and it is not retreating or busy below (Proposed).
func _plan_tapper(run: RunState) -> void:
	var t: Tapper = _tapper(run)
	if t == null or t.is_retreating():
		return
	var d: float = t.position(run).distance_to(Vector2(deck.get_center()))
	var due: int = run.tick + ceili(d / maxf(Tuning.f(&"tapper.rock_speed"), 1e-3) * Tuning.f(&"net.tick_hz"))
	tapper_from = t.position(run)
	tapper_due = due


func _tapper_follow(run: RunState) -> void:
	if tapper_due < 0 or tapper_in_shaft or run.tick < tapper_due:
		return
	var t: Tapper = _tapper(run)
	tapper_due = -1
	if t == null or t.is_retreating() or TapperHunt.busy(t) or not ride.is_bare_rock():
		return
	var faces: Array[Vector2i] = ShaftRide.wall_faces(deck.size)
	var at: Vector2i = faces[ride.departed_at % faces.size()] if not faces.is_empty() else ShaftRide.deck_origin()
	tapper_in_shaft = true
	run.creatures.relocate(run, t, Vector2(at) + Vector2(0.5, 0.5))
	_note(run, "tapper_in_shaft", {"face": at})


func _tapper(run: RunState) -> Tapper:
	if run.creatures == null:
		return null
	return run.creatures.creature_of_kind(WorldIds.EntityKind.TAPPER) as Tapper

#endregion


## The deck and cord from GEN-02's anchors, and the fixtures, once base camp is known.
func _place(run: RunState) -> void:
	if _placed or run.base_camp == null:
		return
	deck = Basecamp.deck_rect(run.base_camp.seed_value, run.base_camp.side)
	var cords: Array[Dictionary] = Basecamp.fixture(run.base_camp.seed_value, "signal_cord", run.base_camp.side)
	if cords.is_empty():
		return
	var cord_tile: Vector2i = cords[0]["position"]
	cord_point = Vector2(cord_tile) + Vector2(0.5, 0.5)
	if not is_departed():
		if _fixture("cage") == 0:
			fixtures["cage"] = run.registry.create(WorldIds.EntityKind.FIXTURE, Vector2(deck.position) + Vector2(deck.size) / 2.0).id
		if _fixture("cord") == 0:
			fixtures["cord"] = run.registry.create(WorldIds.EntityKind.FIXTURE, cord_point).id
	_placed = true


func _deck_tile() -> Vector2i:
	return deck.get_center()


func _fixture(name: String) -> int:
	return int(Variants.number(fixtures.get(name, 0)))


## Each fixture's identity bits (FixtureKinds): the cage with its look, the cord, the open shaft.
func fixture_bits(run: RunState) -> Dictionary:
	var out: Dictionary = {}
	if _fixture("cage") != 0:
		out[_fixture("cage")] = FixtureKinds.cage(look(run))
	if _fixture("cord") != 0:
		out[_fixture("cord")] = FixtureKinds.Kind.CAGE_CORD
	if _fixture("shaft") != 0:
		out[_fixture("shaft")] = FixtureKinds.Kind.OPEN_SHAFT
	return out


## MNR-04's interaction targets: the cord within reach while the cage waits.
func _targets(_run_state: RunState, _actor: int, at: Vector2, reach: float) -> Array:
	if state != State.WAITING or _fixture("cord") == 0 or at.distance_to(cord_point) > reach + 1e-9:
		return []
	return [{"kind": &"signal_cord", "id": _fixture("cord"), "point": cord_point}]


func _note(run: RunState, what: String, fields: Dictionary) -> void:
	var entry: Dictionary = {"tick": run.tick, "what": what}
	entry.merge(fields)
	log.append(entry)
	Log.info("cage: %s %s" % [what, str(fields)])


func write_state(writer: SimStateWriter) -> void:
	writer.put_i64(state)
	writer.put_i64(cord.votes.size())
	writer.put_i64(bell_until)
	writer.put_i64(ride.progress_ticks)
	writer.put_i64(ride.stopped_by)


## NET-09: the state, the votes, the bell, the ride, the snapshot, the fixtures and the Tapper's shaft.
func save_state() -> Dictionary:
	return {"state": state, "votes": cord.save_state(), "bell_until": bell_until, "ride": ride.save_state(), "snapshot": snapshot,
		"fixtures": fixtures.duplicate(), "tapper_due": tapper_due, "tapper_from": [tapper_from.x, tapper_from.y],
		"tapper_in_shaft": tapper_in_shaft, "deck": [deck.position.x, deck.position.y, deck.size.x, deck.size.y]}


func load_state(run: RunState, state_dict: Dictionary) -> void:
	state = int(Variants.number(state_dict.get("state", State.WAITING))) as State
	cord.load_state(Variants.dict(state_dict.get("votes", {})))
	bell_until = int(Variants.number(state_dict.get("bell_until", -1)))
	ride.load_state(Variants.dict(state_dict.get("ride", {})))
	snapshot = Variants.dict(state_dict.get("snapshot", {}))
	fixtures = {}
	var saved: Dictionary = Variants.dict(state_dict.get("fixtures", {}))
	for name: Variant in saved.keys():
		var e: int = int(Variants.number(saved[name]))
		if e != 0 and run.registry.has(e):
			fixtures[str(name)] = e
	tapper_due = int(Variants.number(state_dict.get("tapper_due", -1)))
	var from: Array = Variants.array(state_dict.get("tapper_from", [0.0, 0.0]))
	tapper_from = Vector2(float(Variants.number(from[0])), float(Variants.number(from[1]))) if from.size() == 2 else Vector2.ZERO
	tapper_in_shaft = Variants.flag(state_dict.get("tapper_in_shaft", false))
	var d: Array = Variants.array(state_dict.get("deck", []))
	if d.size() == 4:
		deck = Rect2i(int(Variants.number(d[0])), int(Variants.number(d[1])), int(Variants.number(d[2])), int(Variants.number(d[3])))
	# Departed: the ride zone again (already brick above the lining's change) and the open shaft.
	if is_departed() and run.mine != null:
		if not run.mine.native.is_loaded(ShaftRide.RIDE_CELL):
			run.mine.native.commit(ShaftRide.cell_data(deck.size, state == State.RIDING and not ride.is_bare_rock()))
		run.mine.native.set_collapse(Vector2i.ZERO, Basecamp.OPEN_SHAFT_COLLAPSE, true)

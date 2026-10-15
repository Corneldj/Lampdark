class_name CloseupState
extends SimSystem
## UI-02 (stage INPUTS, just after NET-03's consumption): which close-up each miner reads (Gameplay
## §14.3). The map table and the Manual open from an interact at their fixture, the board from a
## 2 s sit (an MNR-04 TimedAction, phones.seat_s), the Pocket Book anywhere on request.
##
## While one is open the miner stands where they are: this tick's input loses its movement, holds
## and mine actions, and keeps its facing and lamp wants as they were at the open (Proposed), so a
## client that sends more changes nothing. Voice, sound and every timer run on. The reader's view
## goes black (VIS-03's blinding, Proposed): their seen set is empty, so there is nothing to pass on
## to anyone watching, and it returns with the first frame after the close.
##
## Opening is refused while carrying two-handed, Grabbed, unconscious or dead (Caught may read,
## Proposed). A close-up shuts at once when its reader is Grabbed, falls unconscious, dies, escapes
## or is left below (Proposed). Esc or B closes; at the board B starts the 2 s stand, which A
## cancels. Each miner's client alone is told (Protocol.Msg.CLOSE_UP). Server-only.

## The fixtures that open close-ups (GEN-02's base camp anchors), and their interaction kinds.
const FIXTURES: Dictionary = {&"map_table": CloseupKind.Kind.MAP_TABLE, &"manual_lectern": CloseupKind.Kind.MANUAL,
	&"switchboard_seat": CloseupKind.Kind.SWITCHBOARD}
const OPEN_LIVES: Array[int] = [MinerTransitions.Life.UPRIGHT, MinerTransitions.Life.CAUGHT]

## entity -> {kind, facing, desired}: who reads what, and the wants they stand with.
var open: Dictionary = {}
## entity -> the tick the board's stand completes.
var standing: Dictionary = {}
## Every open and close, for tests and the log: {tick, entity, kind, open, cause}.
var history: Array[Dictionary] = []
var _net: ServerNet = null
## slot -> the [kind, seat] last told to that client.
var _told: Dictionary = {}
var _fixtures: Dictionary = {}
var _run: RunState = null


func stage() -> int:
	return StageTable.Stage.INPUTS


func order() -> int:
	return 10


func system_name() -> String:
	return "closeups"


func bind(run: RunState, net: ServerNet) -> void:
	_run = run
	_net = net
	if run.inventory != null:
		run.inventory.targets.providers.append(_fixture_targets)
	if run.miner_state != null:
		run.miner_state.state_changed.connect(_on_state_changed)
		run.miner_state.outcome_set.connect(func(entity: int, _outcome: int, cause: String) -> void: close(entity, "outcome:" + cause))


func kind_of(entity: int) -> CloseupKind.Kind:
	if not open.has(entity):
		return CloseupKind.Kind.NONE
	var k: int = Variants.dict(open[entity])["kind"]
	return k as CloseupKind.Kind


## Who sits at the board (reading it or standing up), or 0.
func operator() -> int:
	for raw: Variant in open.keys():
		var entity: int = raw
		if kind_of(entity) == CloseupKind.Kind.SWITCHBOARD:
			return entity
	return 0


## Opening rules: refused while carrying two-handed, Grabbed, unconscious or dead, or already reading.
func may_open(run: RunState, entity: int) -> bool:
	if open.has(entity) or run.miner_state == null or run.miner_state.miner(entity) == null:
		return false
	if not OPEN_LIVES.has(run.miner_state.life(entity)) or run.miner_state.miner(entity).outcome != MinerTransitions.Outcome.NONE:
		return false
	return run.inventory == null or not run.inventory.hands_of(entity).two_handed


## Opens `kind` for `entity` (the checks are the caller's).
func open_for(run: RunState, entity: int, kind: CloseupKind.Kind, cause: String) -> void:
	var slot: int = _slot_of(run, entity)
	var c: InputBuffer.Consumed = run.input_for(slot) if slot >= 0 else null
	var facing: int = run.movement.facing_of(slot) if slot >= 0 and run.movement != null else 0
	var desired: int = c.record.desired if c != null else InputRecord.new().desired
	open[entity] = {"kind": kind, "facing": facing, "desired": desired}
	if run.inventory != null:
		run.inventory.mark_spent(entity, InputRecord.HOLD_INTERACT)
	if slot >= 0 and run.vision != null:
		run.vision.set_blind(slot, &"close_up", true)
	history.append({"tick": run.tick, "entity": entity, "kind": kind, "open": true, "cause": cause})


## Shuts whatever `entity` reads, at once.
func close(entity: int, cause: String) -> void:
	if not open.has(entity) or _run == null:
		return
	var kind: CloseupKind.Kind = kind_of(entity)
	open.erase(entity)
	standing.erase(entity)
	var slot: int = _slot_of(_run, entity)
	if slot >= 0 and _run.vision != null:
		_run.vision.set_blind(slot, &"close_up", false)
	history.append({"tick": _run.tick, "entity": entity, "kind": kind, "open": false, "cause": cause})


func tick(run: RunState) -> void:
	_run = run
	if run.movement == null:
		return
	for slot: int in run.movement.miner_slots():
		var entity: int = run.movement.miner(slot).entity_id
		var c: InputBuffer.Consumed = run.input_for(slot)
		if c != null:
			_asks(run, entity, c)
			if not open.has(entity):
				_fixture_interact(run, slot, entity, c)
		var stood_at: int = standing.get(entity, -1)
		if stood_at >= 0 and run.tick >= stood_at:
			close(entity, "stood up")
		if open.has(entity) and c != null:
			_stand_still(entity, c)
	_tell(run)


## The client's asks (ActionRecord.Kind.CLOSE_UP), in order.
func _asks(run: RunState, entity: int, c: InputBuffer.Consumed) -> void:
	for a: ActionRecord in c.actions:
		if a.kind != ActionRecord.Kind.CLOSE_UP:
			continue
		match a.arg:
			CloseupKind.Ask.OPEN_POCKET_BOOK:
				if may_open(run, entity):
					open_for(run, entity, CloseupKind.Kind.POCKET_BOOK, "asked")
			CloseupKind.Ask.CLOSE:
				if kind_of(entity) == CloseupKind.Kind.SWITCHBOARD:
					if not standing.has(entity):
						standing[entity] = run.tick + roundi(Tuning.f(&"phones.seat_s") * Tuning.f(&"net.tick_hz"))
				else:
					close(entity, "asked")
			CloseupKind.Ask.STAY_SEATED:
				standing.erase(entity)


## A fresh interact aimed at a fixture: the table and the Manual open at once; the board starts
## the 2 s sit, which opens it if held to the end with the seat still free.
func _fixture_interact(run: RunState, slot: int, entity: int, c: InputBuffer.Consumed) -> void:
	if run.inventory == null or run.inventory.actions.has(entity) or not run.inventory.is_fresh(entity, c.record.holds, InputRecord.HOLD_INTERACT):
		return
	var target: Dictionary = run.inventory.targets.pick(run, entity, slot, run.inventory.world)
	var kind_name: StringName = StringName(str(target.get("kind", "")))
	if not FIXTURES.has(kind_name) or not may_open(run, entity):
		return
	var kind: CloseupKind.Kind = FIXTURES[kind_name]
	if kind != CloseupKind.Kind.SWITCHBOARD:
		open_for(run, entity, kind, "fixture")
		return
	if operator() != 0:
		return
	var sit: TimedAction = TimedAction.make(entity, &"sit_at_board", Tuning.f(&"phones.seat_s"), InputRecord.HOLD_INTERACT)
	sit.needs_still = true
	sit.target_point = target["point"]
	sit.reach = Tuning.f(&"vision.touch_range_tiles")
	sit.valid = func() -> bool: return operator() == 0 and may_open(run, entity)
	sit.effect = func() -> void: open_for(run, entity, CloseupKind.Kind.SWITCHBOARD, "sat")
	run.inventory.start_action(run, sit)


## While open the miner stands: no movement, holds or mine actions; facing and lamp wants as at
## the open. A fresh copy, so the input log and the buffer keep what the client sent.
func _stand_still(entity: int, c: InputBuffer.Consumed) -> void:
	var held: Dictionary = open[entity]
	var r: InputRecord = c.record.duplicate_record()
	r.move_dir = InputRecord.NO_DIRECTION
	r.holds = 0
	r.facing = held["facing"]
	r.desired = held["desired"]
	c.record = r
	var kept: Array[ActionRecord] = []
	for a: ActionRecord in c.actions:
		if a.kind == ActionRecord.Kind.CLOSE_UP:
			kept.append(a)
	c.actions = kept


func _on_state_changed(entity: int, _old: int, new: int, _cause: String) -> void:
	if new == MinerTransitions.Life.GRABBED or new == MinerTransitions.Life.UNCONSCIOUS or new == MinerTransitions.Life.DEAD:
		var names: Array = MinerTransitions.Life.keys()
		var life: String = names[new]
		close(entity, "forced:" + life.to_lower())


## Each client hears its own close-up and seat when they change (and once on joining).
func _tell(run: RunState) -> void:
	if _net == null:
		return
	for session: Sessions.Session in _net.sessions.welcomed():
		var m: MovementSystem.Miner = run.movement.miner(session.slot)
		if m == null:
			continue
		var kind: CloseupKind.Kind = kind_of(m.entity_id)
		var seat: CloseupKind.Seat = CloseupKind.Seat.NONE
		if standing.has(m.entity_id):
			seat = CloseupKind.Seat.STANDING
		elif run.inventory != null and run.inventory.actions.has(m.entity_id):
			var a: TimedAction = run.inventory.actions[m.entity_id]
			if a.verb == &"sit_at_board":
				seat = CloseupKind.Seat.SITTING
		var now: Array = [kind, seat, session.peer]
		if Variants.array(_told.get(session.slot, [])) == now:
			continue
		_told[session.slot] = now
		_net.transport.send(session.peer, Lane.Id.CONTROL, Protocol.frame(Protocol.Msg.CLOSE_UP, CloseupKind.encode(kind, seat)))


## MNR-04's interaction targets: the table, the lectern and the board's seat in touch range.
func _fixture_targets(run: RunState, _actor: int, at: Vector2, reach: float) -> Array:
	var out: Array = []
	if run.base_camp == null:
		return out
	if _fixtures.is_empty():
		for raw: Variant in FIXTURES.keys():
			var name: StringName = raw
			var tiles: Array[Vector2i] = []
			for a: Dictionary in Basecamp.fixture(run.base_camp.seed_value, String(name), run.base_camp.side):
				tiles.append(a["position"])
			_fixtures[name] = tiles
	for raw: Variant in FIXTURES.keys():
		var name: StringName = raw
		var tiles: Array[Vector2i] = _fixtures[name]
		for i: int in tiles.size():
			var centre: Vector2 = Vector2(tiles[i]) + Vector2(0.5, 0.5)
			if at.distance_to(centre) <= reach:
				out.append({"kind": name, "id": i, "point": centre})
	return out


func _slot_of(run: RunState, entity: int) -> int:
	if run.movement == null:
		return -1
	for slot: int in run.movement.miner_slots():
		if run.movement.miner(slot).entity_id == entity:
			return slot
	return -1


func write_state(writer: SimStateWriter) -> void:
	var ids: Array = open.keys()
	ids.sort()
	writer.put_i64(ids.size())
	for raw: Variant in ids:
		var held: Dictionary = open[raw]
		var entity: int = raw
		writer.put_i64(entity)
		writer.put_i32(int(Variants.number(held["kind"])))
		writer.put_i32(int(Variants.number(held["facing"])))
		writer.put_i32(int(Variants.number(held["desired"])))
		writer.put_i64(int(Variants.number(standing.get(raw, -1))))


func read_state(reader: SimStateReader) -> void:
	open.clear()
	standing.clear()
	for _i: int in reader.get_i64():
		var entity: int = reader.get_i64()
		open[entity] = {"kind": reader.get_i32(), "facing": reader.get_i32(), "desired": reader.get_i32()}
		var until: int = reader.get_i64()
		if until >= 0:
			standing[entity] = until

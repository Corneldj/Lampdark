class_name Chalk
extends SimSystem
## MNR-10 (stage MINERS, after the tools): chalk (Gameplay §4.5, §4.8, §12.7). Every miner carries
## chalk, in no slot, never used up (HandsAndBelt.chalk). A pick from the chalk wheel
## (ActionRecord.Kind.CHALK, or a chalk slice of the pad's combined wheel, after SND-12's five lamp
## signals) starts a 2 s mark (items.chalk_time), silent (0 np: no Road Graph event). It is made
## only if the 2 s complete at a crouch's pace or slower, with no change of state (Proposed);
## nothing is made otherwise.
##
## Placement (Proposed): a rib face within items.chalk_rib_reach in the facing direction takes the
## mark, else the floor tile under the miner. A floor arrow points along the facing at the start,
## quantised to items.chalk_arrow_directions (8); a rib arrow points along the rib, to the side
## nearer the facing. Chalk needs the free hand: never carrying two-handed, Grabbed, unconscious,
## or with the revolver, a can or a flare in it; a Caught miner may. Under No Chalk (MOD-10 sets
## `no_chalk`) nothing is made, and the client's wheel stays shut (HandsAndBelt.chalk false).
## Server-only.

## MOD-10's RunRules.no_chalk: () -> bool.
var no_chalk: Callable = func() -> bool: return false
var store: ChalkStore = ChalkStore.new()
## Every mark made: {tick, miner, tile, surface, kind, direction}.
var made: Array[Dictionary] = []
## Every refusal: {tick, miner, why}.
var refused: Array[Dictionary] = []


func stage() -> int:
	return StageTable.Stage.MINERS


func order() -> int:
	return 36


func system_name() -> String:
	return "chalk"


func bind(run: RunState) -> void:
	store.bind(run)


func tick(run: RunState) -> void:
	if run.movement == null or run.inventory == null:
		return
	for slot: int in run.movement.miner_slots():
		var c: InputBuffer.Consumed = run.input_for(slot)
		if c == null:
			continue
		var miner: int = run.movement.miner(slot).entity_id
		for a: ActionRecord in c.actions:
			var kind: int = pick(a)
			if kind >= 0:
				start(run, miner, slot, kind)


## The chalk kind an action picks, or -1: the chalk wheel's 13 slices, or the combined wheel's
## slices after the lamp signals.
static func pick(a: ActionRecord) -> int:
	var angle: float = float(a.aim) / 65536.0 * 360.0
	if a.kind == ActionRecord.Kind.CHALK:
		return ChalkMarks.of_slice(CalloutLines.slice(angle, ChalkMarks.COUNT))
	if a.kind == ActionRecord.Kind.LAMP_SIGNAL and Variants.flag(Intents.decode_wheel_arg(a.arg).get("combined", false)):
		var signals: int = LampSignalKind.WHEEL.size()
		var index: int = CalloutLines.slice(angle, signals + ChalkMarks.COUNT)
		return ChalkMarks.of_slice(index - signals) if index >= signals else -1
	return -1


## Why `miner` may not chalk now ("" if it may).
func refusal(run: RunState, miner: int) -> String:
	if Variants.flag(no_chalk.call()) or not run.inventory.hands_of(miner).chalk:
		return "no chalk"
	if run.miner_state != null and run.miner_state.miner(miner) != null:
		var life: int = run.miner_state.life(miner)
		if life != MinerTransitions.Life.UPRIGHT and life != MinerTransitions.Life.CAUGHT:
			return "grabbed, unconscious or dead"
	if run.inventory.free_hand_blocked(miner, &"chalk"):
		return "the free hand is not free"
	if run.inventory.actions.has(miner):
		return "busy"
	return ""


## Starts the 2 s mark of `kind`; "" when started, else why not.
func start(run: RunState, miner: int, slot: int, kind: int) -> String:
	var why: String = refusal(run, miner)
	if not why.is_empty():
		refused.append({"tick": run.tick, "miner": miner, "why": why})
		return why
	var place: Dictionary = placement(run, miner, slot, kind)
	var a: TimedAction = TimedAction.make(miner, &"chalk", Tuning.f(&"items.chalk_time"), 0)
	a.capability = &"belt"
	a.needs_crouch = true
	a.valid = func() -> bool: return refusal_while(run, miner).is_empty()
	a.effect = func() -> void:
		var tile: Vector2i = place["tile"]
		var surface: int = int(Variants.number(place["surface"]))
		var direction: int = int(Variants.number(place["direction"]))
		store.put(run, tile, surface, ChalkMarks.glyph(kind, direction), miner)
		made.append({"tick": run.tick, "miner": miner, "tile": tile, "surface": surface, "kind": kind, "direction": direction})
	run.inventory.start_action(run, a)
	return ""


## The constraints that hold all along (the action itself checks pace, state and capability).
func refusal_while(run: RunState, miner: int) -> String:
	if Variants.flag(no_chalk.call()):
		return "no chalk"
	if run.inventory.free_hand_blocked(miner, &"chalk"):
		return "the free hand is not free"
	return ""


## Where the mark goes: {tile (the floor tile), surface, direction}. A wall within
## items.chalk_rib_reach straight ahead (the facing's dominant axis) takes it on the face toward the
## miner's tile; else the floor under the miner.
func placement(run: RunState, miner: int, slot: int, kind: int) -> Dictionary:
	var e: SimEntity = run.registry.get_entity(miner)
	var here: Vector2i = e.tile()
	var turns: float = float(run.movement.facing_of(slot)) / 65536.0
	var u: PackedFloat64Array = LbDetMath.unit(turns)
	var facing: Vector2 = Vector2(u[0], u[1])
	var step: Vector2i = Vector2i(signi(roundi(facing.x * 1000.0)), 0) if absf(facing.x) >= absf(facing.y) else Vector2i(0, signi(roundi(facing.y * 1000.0)))
	var surface: int = ChalkMarks.Surface.FLOOR
	if run.mine != null and step != Vector2i.ZERO and not run.mine.native.is_walkable(here + step, false):
		# The face is within reach: its plane lies half a tile from the tile's centre along the step.
		var to_face: float = 0.5 - Vector2(step).dot(e.position - (Vector2(here) + Vector2(0.5, 0.5)))
		if to_face <= Tuning.f(&"items.chalk_rib_reach") + 1e-9:
			for s: int in ChalkMarks.FACE_STEP.keys():
				if ChalkMarks.FACE_STEP[s] == step:
					surface = s
	var direction: int = 0
	if kind == ChalkMarks.Kind.ARROW:
		if surface == ChalkMarks.Surface.FLOOR:
			var steps: int = roundi(Tuning.f(&"items.chalk_arrow_directions"))
			direction = posmod(roundi(turns * steps), steps) * (8 / maxi(1, steps))
		elif surface == ChalkMarks.Surface.NORTH or surface == ChalkMarks.Surface.SOUTH:
			direction = 0 if facing.x >= 0.0 else 4  # along an east-west rib
		else:
			direction = 2 if facing.y >= 0.0 else 6  # along a north-south rib
	return {"tile": here, "surface": surface, "direction": direction}


func write_state(writer: SimStateWriter) -> void:
	var tiles: Array = store.marks.keys()
	tiles.sort()
	writer.put_i64(tiles.size())
	for raw: Variant in tiles:
		var t: Vector2i = raw
		writer.put_i64(t.x)
		writer.put_i64(t.y)
		var glyphs: PackedByteArray = store.marks[raw]
		writer.put_i64(ChalkMarks.pack(glyphs))

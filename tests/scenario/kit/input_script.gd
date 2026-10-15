extends RefCounted
## One miner's scripted inputs by tick (FND-09). Changes are per field, so helpers compose:
## a hold can run while a move does. move, hold and wait advance the cursor; at(tick) sets it.
## Every tick the kit asks for the held record (record_at) and the one-shot actions due.
##
##   miner.inputs.at(10).move(90.0, InputRecord.Gait.WALK, 20).face(180.0).press(ActionRecord.Kind.CHALK, 3)

const Self = preload("res://tests/scenario/kit/input_script.gd")

## tick -> Array of [field, value]; fields: "move", "gait", "facing", "hold_on", "hold_off",
## "desired", "record"
var _changes: Dictionary = {}
## tick -> Array of [kind, arg, aim]
var _actions: Dictionary = {}
## tick -> Array of [band, ticks] (voice) and ["disconnect"] / ["reconnect"] events
var _events: Dictionary = {}
## [from_tick, target tile, gait] while a walk_to is pending or under way.
var _walks: Array[Array] = []
var cursor: int = 0
var held: InputRecord = InputRecord.new()
var _applied_through: int = -1


func at(tick: int) -> Self:
	cursor = tick
	return self


## A whole record from the cursor on (it replaces every held field).
func input(record: InputRecord) -> Self:
	_change(cursor, "record", record.duplicate_record())
	return self


## Moves toward a compass bearing (0 = +x, 90 = +y) for some ticks, then stops.
func move(dir_deg: float, gait: InputRecord.Gait, ticks: int) -> Self:
	_change(cursor, "move", direction_byte(dir_deg))
	_change(cursor, "gait", gait)
	_change(cursor + ticks, "move", InputRecord.NO_DIRECTION)
	cursor += ticks
	return self


func face(deg: float) -> Self:
	_change(cursor, "facing", facing_u16(deg))
	return self


## A one-shot action at the cursor: a callout, signal, chalk mark, ring choice or trigger.
func press(kind: ActionRecord.Kind, arg: int = 0, aim_deg: float = 0.0) -> Self:
	var list: Array = _actions.get(cursor, [])
	list.append([kind, arg, facing_u16(aim_deg)])
	_actions[cursor] = list
	return self


## Holds a control (InputRecord.HOLD_*) for some ticks.
func hold(bit: int, ticks: int) -> Self:
	_change(cursor, "hold_on", bit)
	_change(cursor + ticks, "hold_off", bit)
	cursor += ticks
	return self


func wait(ticks: int) -> Self:
	cursor += ticks
	return self


## Wanted lamp state from the cursor on: shutter closed, wick step 0 (down) to 2 (up).
func lamp(shutter_closed: bool, wick_step: int) -> Self:
	_change(cursor, "desired", (1 if shutter_closed else 0) | (clampi(wick_step, 0, 2) << 1))
	return self


## The selected belt slot (0-3) from the cursor on (MNR-04).
func select_slot(slot: int) -> Self:
	_change(cursor, "slot", slot)
	return self


## Walks to a tile with a deterministic follower over GEN-01's path queries.
func walk_to(tile: Vector2i, gait: InputRecord.Gait = InputRecord.Gait.WALK) -> Self:
	_walks.append([cursor, tile, gait])
	return self


## Band-only voice frames with a dummy payload for some ticks (no microphone).
func say(band: int, ticks: int) -> Self:
	for t: int in ticks:
		_event(cursor + t, ["voice", band])
	return self


## A callout: SND-13's line id (CalloutLines.WHEEL or JOB_PAGE) at a band (1 whisper, 2 talk, 3
## shout), picked as the wheel does: the slice's centre angle and the middle of the band's ring.
func callout(line: String, band: int) -> Self:
	var job: bool = CalloutLines.JOB_PAGE.has(line)
	var lines: Array[String] = CalloutLines.JOB_PAGE if job else CalloutLines.WHEEL
	var angle: float = fposmod(lines.find(line) * 360.0 / lines.size() - 90.0, 360.0)
	var list: Array = _actions.get(cursor, [])
	list.append([ActionRecord.Kind.CALLOUT, Intents.wheel_arg_distance(CalloutLines.ring_distance(band)), Intents.facing_u16(angle)])
	_actions[cursor] = list
	return self


func disconnect_at() -> Self:
	_event(cursor, ["disconnect"])
	return self


func reconnect_at() -> Self:
	_event(cursor, ["reconnect"])
	return self


## The held record for a tick. Ticks must be asked for in order.
func record_at(tick: int) -> InputRecord:
	for t: int in range(_applied_through + 1, tick + 1):
		for change: Variant in Variants.array(_changes.get(t, [])):
			_apply(Variants.array(change))
	_applied_through = maxi(_applied_through, tick)
	return held


## The one-shot actions due at a tick, as [kind, arg, aim].
func actions_at(tick: int) -> Array:
	return Variants.array(_actions.get(tick, []))


func events_at(tick: int) -> Array:
	return Variants.array(_events.get(tick, []))


## The walk_to under way at a tick, or [] (the kit steers it from the miner's position).
func walk_at(tick: int) -> Array:
	for walk: Array in _walks:
		var from: int = walk[0]
		if from <= tick:
			return walk
	return []


func finish_walk(walk: Array) -> void:
	_walks.erase(walk)
	held.move_dir = InputRecord.NO_DIRECTION


static func direction_byte(dir_deg: float) -> int:
	return posmod(roundi(fposmod(dir_deg, 360.0) / 360.0 * InputRecord.DIRECTIONS), InputRecord.DIRECTIONS)


static func facing_u16(deg: float) -> int:
	return posmod(roundi(fposmod(deg, 360.0) / 360.0 * 65536.0), 65536)


func _change(tick: int, field: String, value: Variant) -> void:
	if tick <= _applied_through:
		push_error("InputScript: tick %d has already been sent" % tick)
		return
	var list: Array = _changes.get(tick, [])
	list.append([field, value])
	_changes[tick] = list


func _event(tick: int, event: Array) -> void:
	var list: Array = _events.get(tick, [])
	list.append(event)
	_events[tick] = list


func _apply(change: Array) -> void:
	var field: String = change[0]
	var value: Variant = change[1]
	match field:
		"record":
			var record: InputRecord = value
			held = record.duplicate_record()
		"move":
			held.move_dir = int(Variants.number(value))
		"gait":
			held.gait = int(Variants.number(value)) as InputRecord.Gait
		"facing":
			held.facing = int(Variants.number(value))
		"hold_on":
			held.holds |= int(Variants.number(value))
		"hold_off":
			held.holds &= ~int(Variants.number(value))
		"desired":
			held.desired = (held.desired & ~InputRecord.DESIRED_LAMP_MASK) | int(Variants.number(value))
		"slot":
			held.set_selected_slot(int(Variants.number(value)))

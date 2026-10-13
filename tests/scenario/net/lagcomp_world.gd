extends RefCounted
## Helpers for NET-06's scenarios: an open room, a stub creature whose wind-up ends at tick E
## and asks the defender rule, and a stub lamp whose shutter closes 0.2 s after the server
## applies the wanted state (MNR-06 replaces it). Until CRT-01 the wind-ups are stubs.

const FixtureMap = preload("res://tests/scenario/kit/fixture_map.gd")


## 24 x 9, walls round it; Ann at (8, 4), Bob at (3, 1). A wall at x = 14, rows 1-3.
static func room() -> FixtureMap:
	var rows: PackedStringArray = PackedStringArray()
	rows.append("#".repeat(24))
	for y: int in 7:
		rows.append("#" + ".".repeat(22) + "#")
	rows.append("#".repeat(24))
	rows[4] = "#" + ".".repeat(7) + "a" + ".".repeat(14) + "#"
	rows[1] = "#.." + "b" + ".".repeat(10) + "#" + ".".repeat(8) + "#"
	rows[2] = "#" + ".".repeat(13) + "#" + ".".repeat(8) + "#"
	rows[3] = "#" + ".".repeat(13) + "#" + ".".repeat(8) + "#"
	return FixtureMap.from_ascii(rows)


## A creature's wind-up ending at `end`: asks the rule then (stage 7, after movement).
class StubWindUp:
	extends SimSystem
	var windup: DefenderRule.WindUp
	var end: int
	var outcome_at_end: DefenderRule.Outcome = DefenderRule.Outcome.PENDING

	func _init(w: DefenderRule.WindUp, end_tick: int) -> void:
		windup = w
		end = end_tick

	func stage() -> int:
		return StageTable.Stage.CREATURES

	func order() -> int:
		return 10

	func system_name() -> String:
		return "StubWindUp"

	func tick(run: RunState) -> void:
		if run.tick == end:
			windup.end_tick = end
			outcome_at_end = run.defender.resolve(run, windup)


## The defender's lamp: open until 4 ticks (lamp.shutter_time) after the server applies a closed
## shutter, and opening the same way.
class StubLamp:
	extends SimSystem
	var slot: int
	var open: bool = true
	var _wanted_closed: bool = false
	var _changed: int = -1
	var _steps: int = 4

	func _init(miner_slot: int, start_open: bool) -> void:
		slot = miner_slot
		open = start_open
		_wanted_closed = not start_open
		_steps = roundi(Tuning.f(&"lamp.shutter_time") * Tuning.f(&"net.tick_hz"))

	func stage() -> int:
		return StageTable.Stage.MINERS

	func order() -> int:
		return 90

	func system_name() -> String:
		return "StubLamp"

	func tick(run: RunState) -> void:
		var c: InputBuffer.Consumed = run.inputs.input_for(slot)
		if c != null and c.real and ((c.record.desired & 1) != 0) != _wanted_closed:
			_wanted_closed = (c.record.desired & 1) != 0
			_changed = run.tick
		if _changed >= 0 and run.tick - _changed >= _steps:
			open = not _wanted_closed


## The first real input of a slot that satisfies `test` (consumed: InputBuffer.Consumed) -> bool:
## its stamp and the tick the server applied it. Hook with Scenario.on_tick.
class FirstInput:
	extends RefCounted
	var slot: int
	var test: Callable
	var stamp: int = -1
	var applied: int = -1

	func _init(miner_slot: int, predicate: Callable) -> void:
		slot = miner_slot
		test = predicate

	func watch(run: RunState) -> void:
		if applied >= 0:
			return
		var c: InputBuffer.Consumed = run.inputs.input_for(slot)
		if c != null and c.real and Variants.flag(test.call(c)):
			stamp = c.shown_tick
			# Scenario.on_tick runs after the tick: the tick that applied it is the one before.
			applied = run.tick - 1


## Runs `body(run)` inside each tick at stage 4 (WORLD), where interactions are judged, so
## run.tick is the tick being processed (Scenario.on_tick runs after the counter has moved on).
class Probe:
	extends SimSystem
	var body: Callable

	func _init(each_tick: Callable) -> void:
		body = each_tick

	func stage() -> int:
		return StageTable.Stage.WORLD

	func order() -> int:
		return 95

	func system_name() -> String:
		return "Probe"

	func tick(run: RunState) -> void:
		body.call(run)

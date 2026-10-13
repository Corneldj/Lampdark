extends GutTest
## NET-03: with inputs cut, the miner repeats its last input for exactly 200 ms (4 ticks), then
## stops; a 3 s oil pour in progress is cancelled with no oil moved, and a held feel is let go.
## The pour here is a stand-in for MNR-04, which cancels on the same input_starved signal.

const Rig = preload("res://tests/support/input_rig.gd")


## A stand-in for MNR-04's timed oil pour: holding interact runs a 3 s pour (60 ticks) that
## moves its oil only on completion; input_starved cancels it with nothing spent.
class PourStub:
	extends SimSystem
	var slot: int = 0
	var progress: int = -1
	var oil_moved: int = 0
	var cancelled_at: int = -1
	var completed: int = 0

	func stage() -> int:
		return StageTable.Stage.MINERS

	func order() -> int:
		return 90

	func system_name() -> String:
		return "pour_stub"

	func tick(run: RunState) -> void:
		var c: InputBuffer.Consumed = run.input_for(slot)
		if c == null:
			return
		var holding: bool = (c.record.holds & InputRecord.HOLD_INTERACT) != 0
		if progress < 0 and holding:
			progress = 0
		elif progress >= 0:
			progress += 1
			if progress >= 60:
				oil_moved += 1
				completed += 1
				progress = -1

	func on_starved(starved_slot: int, at_tick: int) -> void:
		if starved_slot == slot and progress >= 0:
			progress = -1
			cancelled_at = at_tick


## What one tick consumed, for the feel test's log.
class Seen:
	extends RefCounted
	var real: bool
	var starved: bool
	var holds: int
	var move_dir: int
	var facing: int

	func _init(c: InputBuffer.Consumed) -> void:
		real = c.real
		starved = c.starved
		holds = c.record.holds
		move_dir = c.record.move_dir
		facing = c.record.facing


func before_all() -> void:
	assert_true(Tuning.load_server())


func _rig(pour: PourStub = null) -> Rig:
	var systems: Array[SimSystem] = []
	if pour != null:
		systems.append(pour)
	var rig: Rig = Rig.new(0x57A7, systems)
	assert_true(rig.connect_and_settle())
	return rig


func test_pour_cut_mid_way_is_cancelled_with_nothing_moved() -> void:
	var pour: PourStub = PourStub.new()
	var rig: Rig = _rig(pour)
	pour.slot = rig.connection.welcome.slot
	rig.run.inputs.input_starved.connect(func(slot: int) -> void: pour.on_starved(slot, rig.run.tick))
	var sending: Array[bool] = [true]
	rig.make_input = func() -> Variant:
		if not sending[0]:
			return null
		var r: InputRecord = InputRecord.new()
		r.holds = InputRecord.HOLD_INTERACT
		return r
	var last_real: Array[int] = [-1]
	var repeats: Array[int] = [0]
	rig.on_tick = func(r: Rig) -> void:
		var c: InputBuffer.Consumed = r.consumed()
		if c == null:
			return
		if c.real:
			last_real[0] = r.run.tick - 1
		elif not c.starved:
			repeats[0] += 1
	rig.ticks(25)
	assert_gt(pour.progress, 10, "the pour is under way")
	repeats[0] = 0
	sending[0] = false
	rig.ticks(20)
	assert_eq(repeats[0], 4, "the last input repeats for exactly 200 ms")
	assert_eq(pour.cancelled_at, last_real[0] + 5, "cancelled on the tick after the fourth repeat")
	assert_eq(pour.oil_moved, 0, "nothing spent")
	assert_eq(pour.progress, -1)
	rig.ticks(80)
	assert_eq(pour.completed, 0, "a stopped miner does not pour")


func test_feel_cut_mid_hold_is_let_go_and_resumes() -> void:
	var rig: Rig = _rig()
	var starved: Array[int] = [0]
	var resumed: Array[int] = [0]
	rig.run.inputs.input_starved.connect(func(_slot: int) -> void: starved[0] += 1)
	rig.run.inputs.input_resumed.connect(func(_slot: int) -> void: resumed[0] += 1)
	var sending: Array[bool] = [true]
	var marker: Array[int] = [0]
	rig.make_input = func() -> Variant:
		if not sending[0]:
			return null
		var r: InputRecord = InputRecord.new()
		r.holds = InputRecord.HOLD_FEEL
		r.move_dir = 64
		r.gait = InputRecord.Gait.CROUCH
		r.facing = marker[0]
		marker[0] += 1
		return r
	var log: Array[Seen] = []
	rig.on_tick = func(r: Rig) -> void:
		var c: InputBuffer.Consumed = r.consumed()
		if c != null:
			log.append(Seen.new(c))
	rig.ticks(20)
	sending[0] = false
	log.clear()
	rig.ticks(12)
	# Up to two inputs were still in flight when sending stopped.
	var first_repeat: int = log.find_custom(func(e: Seen) -> bool: return not e.real)
	assert_gte(first_repeat, 0)
	for i: int in 4:
		var e: Seen = log[first_repeat + i]
		assert_false(e.starved, "repeat %d still holds" % (i + 1))
		assert_eq(e.holds, InputRecord.HOLD_FEEL, "feel stays held while repeating")
		assert_eq(e.move_dir, 64)
	var stop: Seen = log[first_repeat + 4]
	assert_true(stop.starved, "stopped after four repeats")
	assert_eq(stop.holds, 0, "feel is let go")
	assert_eq(stop.move_dir, InputRecord.NO_DIRECTION, "movement zeroed")
	assert_eq(starved[0], 1, "input_starved fired once")
	sending[0] = true
	log.clear()
	rig.ticks(6)
	assert_eq(resumed[0], 1, "input_resumed fired once")
	var first_back: int = log.find_custom(func(e: Seen) -> bool: return e.real)
	assert_gte(first_back, 0)
	assert_eq(log[first_back].holds, InputRecord.HOLD_FEEL)
	assert_gt(log[first_back].facing, stop.facing, "resumes from a fresh input, not the one held at the stop")

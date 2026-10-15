extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-10: each of the 13 marks is made after exactly 40 ticks (items.chalk_time), silently; moving
## above a crouch's pace or a change of state leaves nothing. The pad's combined wheel picks chalk
## from the slices after the five lamp signals.

const C = preload("res://tests/unit/mnr/chalk_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_each_mark_in_exactly_forty_ticks_silently() -> void:
	var s: Scenario = make({"seed": 1001, "fixture": C.B.room()})
	C.B.light(s)
	var ann: MinerHandle = C.miner(s, "ann", Vector2i(6, 3))
	s.step(3)
	var need: int = roundi(Tuning.f(&"items.chalk_time") * Tuning.f(&"net.tick_hz"))
	assert_eq(need, 40)
	var events: int = s.run.noise.event_log.size()
	var lag: int = -1
	for kind: int in ChalkMarks.COUNT:
		C.chalk(s, ann, kind)
		var took: int = C.ticks_to_mark(s, 80)
		assert_gt(took, 0, "mark %d made" % kind)
		if lag < 0:
			lag = took - need
			assert_gte(lag, 0, "the pick reaches the server after its input delay")
		assert_eq(took - lag, need, "mark %d: 40 ticks" % kind)
		var row: Dictionary = s.run.chalk.made[s.run.chalk.made.size() - 1]
		assert_eq(int(Variants.number(row["kind"])), kind)
		assert_eq(ChalkMarks.kind_of(s.run.chalk.store.glyph_at(Vector2i(6, 3), ChalkMarks.Surface.FLOOR)), kind, "on the floor")
	assert_eq(s.run.noise.event_log.size(), events, "0 np: no Road Graph event")


func test_moving_fast_or_a_state_change_leaves_nothing() -> void:
	var s: Scenario = make({"seed": 1002, "fixture": C.B.room()})
	C.B.light(s)
	var ann: MinerHandle = C.miner(s, "ann", Vector2i(3, 3))
	s.step(3)
	C.chalk(s, ann, ChalkMarks.Kind.CROSS)
	ann.at(s.run.tick + 8).move(0.0, InputRecord.Gait.WALK, 30)
	assert_eq(C.ticks_to_mark(s, 70), -1, "walking: nothing")
	assert_eq(s.run.chalk.store.marks.size(), 0)
	s.step(30)
	C.chalk(s, ann, ChalkMarks.Kind.CROSS)
	ann.at(s.run.tick + 8).move(0.0, InputRecord.Gait.CROUCH, 30)
	assert_gt(C.ticks_to_mark(s, 70), 0, "at a crouch's pace it is made")
	s.step(10)
	var marks_before: int = s.run.chalk.made.size()
	C.chalk(s, ann, ChalkMarks.Kind.BANG)
	s.step(15)
	assert_true(s.run.falls.fall_unconscious(s.run, ann.entity_id, FallCause.Cause.MOTH_SMOTHER))
	s.step(60)
	assert_eq(s.run.chalk.made.size(), marks_before, "a fall cancels it: nothing")


func test_the_combined_wheel_picks_chalk_after_the_signals() -> void:
	var signals: int = LampSignalKind.WHEEL.size()
	var count: int = signals + ChalkMarks.COUNT
	for kind: int in ChalkMarks.COUNT:
		var a: ActionRecord = ActionRecord.new()
		a.kind = ActionRecord.Kind.LAMP_SIGNAL
		a.arg = Intents.wheel_arg_distance(0.8) | Intents.COMBINED_FLAG
		a.aim = roundi(C.slice_angle(signals + kind, count) / 360.0 * 65536.0) & 0xFFFF
		assert_eq(Chalk.pick(a), kind, "combined slice %d" % (signals + kind))
	var sig: ActionRecord = ActionRecord.new()
	sig.kind = ActionRecord.Kind.LAMP_SIGNAL
	sig.arg = Intents.wheel_arg_distance(0.8) | Intents.COMBINED_FLAG
	sig.aim = roundi(C.slice_angle(1, count) / 360.0 * 65536.0) & 0xFFFF
	assert_eq(Chalk.pick(sig), -1, "a signal slice is not chalk")
	sig.arg = Intents.wheel_arg_distance(0.8)
	assert_eq(Chalk.pick(sig), -1, "the plain signal wheel holds no chalk")
	assert_eq(ChalkMarks.direction_of(ChalkMarks.glyph(ChalkMarks.Kind.ARROW, 5)), 5)
	assert_eq(ChalkMarks.pack(PackedByteArray([0x80, 0, 0, 0, 0x81])), 0x8100000080)

extends GutTest
## FND-09's input scripts: per-field changes that compose, one-shot actions, events.

const InputScript = preload("res://tests/scenario/kit/input_script.gd")


func _records(s: InputScript, ticks: int) -> Array[InputRecord]:
	var out: Array[InputRecord] = []
	for t: int in ticks:
		out.append(s.record_at(t).duplicate_record())
	return out


func test_move_hold_and_face_compose() -> void:
	var s: InputScript = InputScript.new()
	s.at(2).move(90.0, InputRecord.Gait.RUN, 4)
	s.at(3).hold(InputRecord.HOLD_FEEL, 2).face(180.0)
	var r: Array[InputRecord] = _records(s, 8)
	assert_eq(r[1].move_dir, InputRecord.NO_DIRECTION)
	assert_eq(r[2].move_dir, InputScript.direction_byte(90.0))
	assert_eq(r[2].gait, InputRecord.Gait.RUN)
	assert_eq(r[5].move_dir, InputScript.direction_byte(90.0), "four ticks of movement: 2, 3, 4, 5")
	assert_eq(r[6].move_dir, InputRecord.NO_DIRECTION)
	assert_eq([r[2].holds, r[3].holds, r[4].holds, r[5].holds], [0, InputRecord.HOLD_FEEL, InputRecord.HOLD_FEEL, 0])
	assert_eq(r[4].facing, 0)
	assert_eq(r[5].facing, 32768, "face() applies at the cursor after the hold")


func test_actions_and_events_by_tick() -> void:
	var s: InputScript = InputScript.new()
	s.at(4).press(ActionRecord.Kind.TRIGGER, 0, 90.0).callout(11, 2).say(1, 3)
	s.at(9).disconnect_at().wait(5).reconnect_at()
	assert_eq(s.actions_at(4), [[ActionRecord.Kind.TRIGGER, 0, 16384], [ActionRecord.Kind.CALLOUT, 11, 2]])
	assert_eq(s.actions_at(5), [])
	assert_eq(s.events_at(6), [["voice", 1]])
	assert_eq(s.events_at(7), [])
	assert_eq(s.events_at(9), [["disconnect"]])
	assert_eq(s.events_at(14), [["reconnect"]])


func test_whole_records_and_the_lamp() -> void:
	var s: InputScript = InputScript.new()
	var r: InputRecord = InputRecord.new()
	r.move_dir = 40
	r.holds = InputRecord.HOLD_AIM
	s.at(1).input(r).lamp(true, 0)
	assert_eq(s.record_at(0).move_dir, InputRecord.NO_DIRECTION)
	assert_eq(s.record_at(1).move_dir, 40)
	assert_eq(s.record_at(1).desired, 1, "shutter closed, wick down")


func test_a_change_in_the_past_is_refused() -> void:
	var s: InputScript = InputScript.new()
	s.record_at(10)
	s.at(5).face(90.0)
	assert_push_error("already been sent")


func test_bearings_wrap() -> void:
	assert_eq(InputScript.direction_byte(0.0), 0)
	assert_eq(InputScript.direction_byte(360.0), 0)
	assert_eq(InputScript.direction_byte(-90.0), InputScript.direction_byte(270.0))
	assert_eq(InputScript.facing_u16(359.999), 0)

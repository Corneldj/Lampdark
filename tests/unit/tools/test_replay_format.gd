extends GutTest
## FND-09's replay format (InputLog): header, entries, setup steps and the end line round-trip;
## a tampered log no longer reaches the recorded hash.

const Scenario = preload("res://tests/scenario/kit/scenario.gd")
const Sample = preload("res://tests/scenario/kit/sample.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_round_trip() -> void:
	var run: RunState = RunState.create(-2, ServerConfig.Mode.PUBLIC, false)
	var log: InputLog = InputLog.begin(run, "named:test", "", "design_baseline")
	var c: InputBuffer.Consumed = InputBuffer.Consumed.new()
	c.record = InputRecord.new()
	c.record.move_dir = 77
	c.record.holds = InputRecord.HOLD_FEEL
	c.real = true
	c.starved_now = true
	c.shown_tick = 41
	var a: ActionRecord = ActionRecord.new()
	a.action_seq = 9
	a.kind = ActionRecord.Kind.TRIGGER
	a.aim = 1234
	c.actions.append(a)
	log.append(42, 3, c)
	log.append_op(40, {"op": "set_gate", "id": 2, "open": true})
	log.end_tick = 50
	log.end_hash = "abc"
	var path: String = "user://fnd09_format.jsonl"
	assert_eq(log.save(path), OK)
	var back: InputLog = InputLog.load_file(path)
	assert_not_null(back)
	assert_eq(back.run_seed, -2, "u64 seeds survive as their bits")
	assert_eq(back.mode, "public")
	assert_eq(back.map_name, "named:test")
	assert_eq(back.tuning_profile, "design_baseline")
	assert_eq(back.tuning_hash, run.header.tuning_hash)
	assert_eq([back.end_tick, back.end_hash], [50, "abc"])
	var ops: Array = Variants.array(back.ops_by_tick[40])
	assert_eq(ops, [{"op": "set_gate", "id": 2.0, "open": true}])
	var entry: Array = Variants.array(back.by_tick[42])[0]
	var slot: int = entry[0]
	assert_eq(slot, 3)
	var got: InputBuffer.Consumed = entry[1]
	assert_eq([got.record.move_dir, got.record.holds, got.real, got.starved_now, got.shown_tick], [77, InputRecord.HOLD_FEEL, true, true, 41])
	assert_eq([got.actions[0].action_seq, got.actions[0].kind, got.actions[0].aim], [9, ActionRecord.Kind.TRIGGER, 1234])


func test_not_a_log_is_refused() -> void:
	var file: FileAccess = FileAccess.open("user://fnd09_not_a_log.jsonl", FileAccess.WRITE)
	file.store_line("{\"format\": \"something else\"}")
	file.close()
	assert_null(InputLog.load_file("user://fnd09_not_a_log.jsonl"))
	assert_push_error("not a version 2 input log")


func test_a_tampered_log_misses_the_hash() -> void:
	var s: Scenario = Sample.build()
	s.step(30)
	var path: String = "user://fnd09_tamper.jsonl"
	s.save_replay(path)
	var live: String = s.state_hash()
	s.close()
	var lines: PackedStringArray = FileAccess.get_file_as_string(path).split("\n", false)
	var tampered: bool = false
	for i: int in lines.size():
		var entry: Dictionary = Variants.dict(JSON.parse_string(lines[i]))
		if int(Variants.number(entry.get("t", -1))) == 20 and entry.has("r"):
			var record: String = str(entry["r"])
			entry["r"] = ("01" if record.begins_with("00") else "00") + record.substr(2)
			lines[i] = JSON.stringify(entry)
			tampered = true
			break
	assert_true(tampered, "an applied input at tick 20 was changed")
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string("\n".join(lines) + "\n")
	file.close()
	var r: Scenario = Scenario.replay(path)
	assert_ne(r.state_hash(), live, "one changed input changes the final state hash")
	r.close()


func test_script_rolls_force_the_next_draws() -> void:
	var run: RunState = RunState.create(77, ServerConfig.Mode.FRIENDS, false)
	var keys: PackedInt64Array = PackedInt64Array([5])
	var plain: int = LbRng.from_seed(LbHash.sub_seed(77, 8, keys, 0)).next_u64()
	assert_true(run.script_rolls(8, keys, PackedInt64Array([111, 222])), "pending for a stream not yet handed out")
	var rng: LbRng = run.stream(8, keys)
	assert_eq([rng.next_u64(), rng.next_u64()], [111, 222])
	assert_eq(rng.next_u64(), plain, "then the stream resumes where it was")
	assert_true(run.script_rolls(8, keys, PackedInt64Array([9])), "and a live stream takes them at once")
	assert_eq(rng.range(0, 1000), 9)
	assert_true(ClassDB.class_has_method(&"LbRng", &"script_values"), "present in this debug build")

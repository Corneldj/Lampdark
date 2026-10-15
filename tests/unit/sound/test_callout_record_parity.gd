extends "res://tests/scenario/kit/scenario_test.gd"
## SND-11: a real callout's record and one CRT-10's illusion stage would build carry the same fields,
## encode alike and decode to themselves; no field names a speaker, an entity or a name.

const N = preload("res://tests/scenario/net/net04_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_real_and_illusion_records_are_one_type() -> void:
	var s: Scenario = make({"seed": 411, "fixture": N.road()})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	var bob: MinerHandle = s.add_miner("bob", s.fixture.spot("a") + Vector2i(5, 0))
	s.step(3)
	assert_gt(s.run.callouts.speak(s.run, ann.slot, "is_that_you", 2), 0)
	s.step(4)
	assert_false(bob.connection.callouts.is_empty())
	var real: CalloutRecord = bob.connection.callouts[0]
	var fake: CalloutRecord = CalloutRecord.new()
	fake.voice = real.voice
	fake.line = real.line
	fake.band = real.band
	fake.apparent = real.apparent
	fake.gain_db = real.gain_db
	fake.muffle = real.muffle
	fake.flags = real.flags
	fake.mask = real.mask.duplicate()
	assert_eq(real.to_dict().keys(), CalloutRecord.FIELDS as Array, "exactly the reviewed fields")
	assert_eq(fake.to_dict().keys(), real.to_dict().keys())
	assert_eq(fake.encode(), real.encode(), "byte for byte")
	assert_eq(CalloutRecord.decode(real.encode()).encode(), real.encode())
	var forbidden: RegEx = RegEx.create_from_string("entity|speaker|name|slot|lamp|token|id$")
	for field: String in CalloutRecord.FIELDS:
		assert_null(forbidden.search(field), "%s names no one" % field)


func test_nothing_parses_speech_or_marks_anything() -> void:
	for path: String in ["res://server/systems/sound/callout_system.gd", "res://client/audio/callout_player.gd", "res://client/ui/callout_wheel.gd",
			"res://shared/sound/callout_lines.gd", "res://shared/protocol/callout_record.gd"]:
		var text: String = FileAccess.get_file_as_string(path).to_lower()
		for word: String in ["speech_to_text", "transcri[a-z]*", "recogni[a-z]*", "markers?", "pings?", "waypoints?", "highlight[a-z]*",
				"persona"]:
			assert_null(RegEx.create_from_string("\\b%s\\b" % word).search(text), "%s never names %s" % [path, word])

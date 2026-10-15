extends "res://tests/scenario/kit/scenario_test.gd"
## SND-12: a miner's taps with gaps of 1.5 s or less form one rhythm; when it ends, rhythm_tapped
## gives the scripted intervals (50 ms steps) and the taps' events. No tap record names anyone.

const W = preload("res://tests/unit/sound/signal_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_scripted_rhythm() -> void:
	var s: Scenario = make({"seed": 1141, "fixture": W.road(30)})
	var ann: MinerHandle = W.miner(s, "ann", s.fixture.spot("a") + Vector2i(0, -1), 270.0, false)
	s.step(2)
	var got: Array = []
	s.run.rock_taps.rhythm_tapped.connect(func(miner: int, intervals: PackedInt32Array, events: PackedInt64Array) -> void:
		got.append([miner, intervals, events]))
	var t0: int = s.run.tick + 2
	for at: int in [0, 10, 20, 40]:
		W.tap_press(s, ann, t0 + at)
	s.step(45)
	assert_eq(got.size(), 0, "still going: the last gap is under 1.5 s")
	s.step(40)
	assert_eq(got.size(), 1, "ended after a 1.5 s silence")
	var r: Array = got[0]
	var who: int = r[0]
	var intervals: PackedInt32Array = r[1]
	var events: PackedInt64Array = r[2]
	assert_eq(who, ann.entity_id)
	assert_eq(intervals, PackedInt32Array([500, 500, 1000]), "the scripted gaps")
	assert_eq(events.size(), 4, "four taps' events")
	# A second rhythm after the silence is its own.
	W.tap_press(s, ann, s.run.tick + 1)
	W.tap_press(s, ann, s.run.tick + 6)
	s.step(45)
	assert_eq(got.size(), 2)
	var second: PackedInt32Array = Variants.array(got[1])[1]
	assert_eq(second, PackedInt32Array([250]))
	# No tap record carries an entity: the record's fields are the sound's only.
	var names: Array[String] = []
	for p: Dictionary in AudioRecord.new().get_property_list():
		names.append(str(p["name"]))
	for word: String in ["entity", "source", "miner", "tapper", "slot"]:
		assert_false(names.has(word), "no %s on a tap record" % word)

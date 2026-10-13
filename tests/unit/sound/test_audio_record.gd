extends "res://tests/scenario/kit/scenario_test.gd"
## SND-03: an AudioRecord has exactly the client fields (type, timing, apparent position or points,
## level and remaining level, duration, voice, flags, mask gain) and nothing that can hold an entity,
## a token, an event id or a true source; the record crosses the wire whole (NET-04's frame events)
## and decodes to the same values.

const A = preload("res://tests/unit/sound/audio_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_fields() -> void:
	var names: Array[String] = []
	for p: Dictionary in AudioRecord.new().get_property_list():
		if (int(Variants.number(p["usage"])) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0:
			names.append(str(p["name"]))
	names.sort()
	var want: Array[String] = AudioRecord.FIELDS.duplicate()
	want.sort()
	assert_eq(names, want, "exactly the client fields")
	for bad: String in ["entity", "token", "event_id", "source", "true_source", "origin", "id"]:
		assert_false(names.has(bad), "no %s" % bad)


func test_from_delivery_strips_the_server_side() -> void:
	var r: AudioRecord = AudioRecord.from_delivery({"event_id": 99, "type": NoiseTypes.Type.SHOT, "tick": 7, "apparent": Vector2(3.5, 4.5),
		"remaining_np": 22.0, "level_np": 40.0, "duration_s": 0.5, "muffled": true, "path_tiles": 9.0, "via": 3, "true_source": Vector2i(1, 1)})
	assert_eq(r.to_event().keys(), ["type", "start_tick", "apparent", "remaining_np", "level_np", "duration_s", "voice", "flags", "gain_db", "points"])
	assert_eq(r.flags, AudioRecord.MUFFLED)
	assert_eq([r.level_np, r.remaining_np], [40.0, 22.0])


func test_round_trip_through_the_frame() -> void:
	var s: Scenario = make({"seed": 5, "fixture": A.hall()})
	var ann: MinerHandle = s.add_miner("ann", Vector2i(5, 3))
	s.step(2)
	var r: AudioRecord = AudioRecord.new()
	r.type = LocalSounds.Type.MOTH_STIR
	r.start_tick = s.run.tick
	r.apparent = Vector2(9.0, 3.5)
	r.points = [Vector2(8.0, 1.5), Vector2(10.25, 4.0), Vector2(7.5, 5.5)] as Array[Vector2]
	r.level_np = 13.25
	r.remaining_np = 7.5
	r.duration_s = 1.5
	r.flags = AudioRecord.DIFFUSE
	r.gain_db = -9
	s.run.audio.deliver(ann.slot, r)
	s.step(3)
	var got: Array[Dictionary] = []
	for e: Dictionary in ann.connection.events:
		if int(Variants.number(e["type"])) == LocalSounds.Type.MOTH_STIR:
			got.append(e)
	assert_eq(got.size(), 1, "arrived once")
	var back: AudioRecord = AudioRecord.from_event(got[0])
	assert_eq(back.apparent, r.apparent)
	assert_eq(back.points, r.points, "the points, to a sixteenth of a tile")
	assert_eq([back.level_np, back.remaining_np, back.duration_s, back.flags, back.gain_db], [13.25, 7.5, 1.5, AudioRecord.DIFFUSE, -9])

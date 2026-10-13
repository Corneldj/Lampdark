extends "res://tests/scenario/kit/scenario_test.gd"
## VIS-07: bumping a wall the miner cannot see sends its material's caption and one rumble per
## contact; a shut gate is '[steel]'; a seen wall sends nothing; no bump makes a sound.

const W = preload("res://tests/unit/mnr/belt_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _bumps(s: Scenario, h: MinerHandle) -> Array[String]:
	var out: Array[String] = []
	for a: Dictionary in s.run.feel.answers:
		if a.has("bump") and int(Variants.number(a["miner"])) == h.entity_id:
			out.append(str(a["caption_key"]))
	return out


func test_unseen_wall_and_gate() -> void:
	# A shut gate (G) between the two halves of a hall.
	var rows: PackedStringArray = PackedStringArray(["#########", "#...#...#", "#.a.G...#", "#...#...#", "#########"])
	var s: Scenario = make({"seed": 1, "fixture": FixtureMap.from_ascii(rows)})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	s.step(2)
	var noise_before: int = s.run.noise.event_log.size()
	ann.at(s.run.tick).move(0.0, InputRecord.Gait.CROUCH, 60)
	s.step(70)
	assert_eq(_bumps(s, ann), ["caption.bump.steel"] as Array[String], "one caption for one contact: a shut gate is steel")
	assert_eq(ann.connection.feel.bumps, 1)
	assert_eq(ann.connection.feel.rumbles, 1, "one rumble")
	assert_eq(str(ann.connection.feel.last_bump["caption_key"]), "caption.bump.steel")
	var noises: Array = s.run.noise.event_log.slice(noise_before)
	for e: NoiseSystem.Event in noises:
		assert_true(NoiseTypes.id_of(e.type).begins_with("step"), "no sound but her steps: %s" % NoiseTypes.id_of(e.type))
	ann.at(s.run.tick).move(270.0, InputRecord.Gait.CROUCH, 60)
	s.step(70)
	var all: Array[String] = _bumps(s, ann)
	assert_eq(all, ["caption.bump.steel", "caption.bump.rock"] as Array[String], "then the rock")
	assert_eq(ann.connection.feel.rumbles, 2)


func test_seen_wall_sends_nothing() -> void:
	var s: Scenario = make({"seed": 2, "fixture": W.room()})
	W.light(s)
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	ann.at(0).face(270.0)
	s.step(4)
	ann.at(s.run.tick).move(270.0, InputRecord.Gait.CROUCH, 60)
	s.step(70)
	assert_eq(_bumps(s, ann).size(), 0, "she sees the wall she walks into")

extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-09 with SND-01 (fixed with SND-04): the Tapper's taps sound from wall faces, which are rock.
## A sound made in the rock enters the air at the open floor beside it, so a miner near the taps
## hears them (before the fix, the Road Graph started nowhere and nobody heard a tap).

const A = preload("res://tests/unit/sound/audio_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_taps_on_wall_faces_are_heard() -> void:
	var s: Scenario = make({"seed": 309, "fixture": A.hall()})
	var ann: MinerHandle = s.add_miner("ann", Vector2i(14, 3))
	s.step(2)
	var faces: Array[Vector2i] = [Vector2i(14, 0), Vector2i(16, 0), Vector2i(12, 0)]
	for f: Vector2i in faces:
		assert_false(s.mine.native.is_walkable(f), "a wall face is rock")
	var id: int = s.run.noise.emit(NoiseTypes.Type.ROCK_TAP, faces[0], {"origins": faces, "level_np": Tuning.f(&"tapper.tap_np")})
	s.step(4)
	var taps: Array[Dictionary] = []
	for e: Dictionary in ann.connection.events:
		if int(Variants.number(e["type"])) == NoiseTypes.Type.ROCK_TAP:
			taps.append(e)
	assert_eq(taps.size(), 1, "Ann hears the taps")
	var event: NoiseSystem.Event = null
	for e: NoiseSystem.Event in s.run.noise.event_log:
		if e.id == id:
			event = e
	assert_eq(event.origins, [Vector2i(14, 1), Vector2i(16, 1), Vector2i(12, 1)] as Array[Vector2i], "from the floor beside each face")
	var apparent: Vector2 = taps[0]["apparent"]
	assert_lt(apparent.y, 2.0, "heard from along the wall")


func test_the_tappers_own_tapping_reaches_miners() -> void:
	var s: Scenario = make({"seed": 310, "fixture": A.hall()})
	var ann: MinerHandle = s.add_miner("ann", Vector2i(14, 3))
	s.step(2)
	var faces: Array[Vector2i] = [Vector2i(13, 0)]
	s.run.noise.emit(NoiseTypes.Type.ROCK_TAP, faces[0], {"level_np": Tuning.f(&"tapper.tap_np"), "source": 999})
	s.step(4)
	var heard: int = 0
	for e: Dictionary in ann.connection.events:
		if int(Variants.number(e["type"])) == NoiseTypes.Type.ROCK_TAP:
			heard += 1
	assert_eq(heard, 1, "a double tap at the face (TapperHunt) is heard too")

extends "res://tests/scenario/kit/scenario_test.gd"
## SND-04 (Gameplay §4.7, §7.6): miners stand 2, 3 and 4 tiles from a shot. The first two (within
## revolver.deafen_radius) are deafened with the shooter; the third is not. A Tapper's taps (a rock-tap
## event, CRT-09) reach the third but not the first two; a hammer reaches the first two 20 dB down.
## MNR-16's real shot deafens them.

const A = preload("res://tests/unit/sound/audio_world.gd")
## The tap's three points (the open floor beside three wall faces; NoiseSystem.emit now does this
## itself for rock origins).
const TAP_FLOOR: Array[Vector2i] = [Vector2i(14, 1), Vector2i(16, 1), Vector2i(12, 1)]


func before_all() -> void:
	assert_true(Tuning.load_server())


func _of(h: MinerHandle, type: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in h.connection.events:
		if int(Variants.number(e["type"])) == type:
			out.append(e)
	return out


func test_shot_deafens_within_three() -> void:
	var s: Scenario = make({"seed": 304, "fixture": A.hall()})
	var shot: Vector2i = Vector2i(10, 3)
	var shooter: MinerHandle = s.add_miner("shooter", shot, {"facing_deg": 90.0})
	shooter.brain = null
	shooter.at(0).face(90.0)
	var two: MinerHandle = s.add_miner("two", shot + Vector2i(2, 0))
	var three: MinerHandle = s.add_miner("three", shot + Vector2i(3, 0))
	var four: MinerHandle = s.add_miner("four", shot + Vector2i(4, 0))
	s.step(2)
	# MNR-16's real shot: drawn, aimed, the trigger (aimed away from everyone).
	s.run.inventory.hands_of(shooter.entity_id).free_hand = Revolver.make(s.run)
	shooter.at(s.run.tick).hold(InputRecord.HOLD_AIM, 30)
	s.step(3)
	shooter.at(s.run.tick).press(ActionRecord.Kind.TRIGGER, 0, 90.0)
	assert_true(s.run_until(func(sc: Scenario) -> bool: return not sc.run.revolver.shots.is_empty(), 10), "the shot")
	assert_true(s.run.deafen.is_deafened(shooter.slot), "the shooter")
	assert_true(s.run.deafen.is_deafened(two.slot), "2 tiles")
	assert_true(s.run.deafen.is_deafened(three.slot), "3 tiles")
	assert_false(s.run.deafen.is_deafened(four.slot), "4 tiles: hears on")
	s.step(2)
	# The Tapper's taps (CRT-09): one rock-tap event from wall points near them.
	s.run.noise.emit(NoiseTypes.Type.ROCK_TAP, Vector2i(14, 1), {"origins": TAP_FLOOR,
		"level_np": Tuning.f(&"tapper.tap_np")})
	s.run.noise.emit(NoiseTypes.Type.HAMMER, Vector2i(13, 5), {})
	s.step(4)
	assert_eq(_of(two, NoiseTypes.Type.ROCK_TAP).size(), 0, "no taps for the deafened at 2")
	assert_eq(_of(three, NoiseTypes.Type.ROCK_TAP).size(), 0, "nor at 3")
	assert_eq(_of(four, NoiseTypes.Type.ROCK_TAP).size(), 1, "4 tiles off hears the taps")
	var dip: int = -roundi(Tuning.f(&"noise.deafen_dip_db"))
	for h: MinerHandle in [two, three]:
		var hammers: Array[Dictionary] = _of(h, NoiseTypes.Type.HAMMER)
		assert_eq(hammers.size(), 1)
		assert_eq(int(Variants.number(hammers[0]["gain_db"])), dip, "%s hears the hammer 20 dB down" % h.name)
		assert_eq(h.connection.deafened.size(), 1, "%s's client rings" % h.name)
	var clear: Array[Dictionary] = _of(four, NoiseTypes.Type.HAMMER)
	assert_eq(int(Variants.number(clear[0]["gain_db"])), 0, "full level at 4")
	assert_eq(four.connection.deafened.size(), 0)
	# 5 s on, the taps reach everyone again.
	s.step(roundi(Tuning.f(&"noise.deafen_duration_s") * Tuning.f(&"net.tick_hz")))
	s.run.noise.emit(NoiseTypes.Type.ROCK_TAP, Vector2i(14, 1), {"origins": TAP_FLOOR,
		"level_np": Tuning.f(&"tapper.tap_np")})
	s.step(4)
	assert_eq(_of(two, NoiseTypes.Type.ROCK_TAP).size(), 1, "the ringing over, the taps return")

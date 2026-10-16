extends "res://tests/scenario/kit/scenario_test.gd"
## DIR-01: the Draught reads the true world only (Gameplay §9.2, §10.1, §10.4). A stand-in for
## CRT-10's illusion stage (stage 14) plays every kind of sound at Ann, every tick, from a fake face
## beside her; and real cries come up the road, as the cold open's screams will (MOD-04): it is not
## a fall, so it adds nothing. No intensity moves.

const D = preload("res://tests/scenario/director/draught_world.gd")


## Every tick, one illusion of every sound kind for one client.
class IllusionStub:
	extends SimSystem
	var slot: int = -1
	var played: int = 0

	func stage() -> int:
		return StageTable.Stage.ILLUSIONS

	func order() -> int:
		return 0

	func system_name() -> String:
		return "illusion_stub"

	func tick(run: RunState) -> void:
		if slot < 0:
			return
		for raw: Variant in NoiseTypes.Type.values():
			var t: int = int(Variants.number(raw))
			if t == NoiseTypes.Type.NONE:
				continue
			run.replication.append_illusion_event(slot, {"type": t, "start_tick": run.tick,
				"apparent": Vector2(2.5, 1.5), "remaining_np": 6.0, "duration_s": 0.5})
			played += 1


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_no_illusion_and_no_scream_moves_any_intensity() -> void:
	var stub: IllusionStub = IllusionStub.new()
	var s: Scenario = make({"seed": 701, "fixture": D.hall(), "director": true, "systems": [stub]})
	var ids: Array[int] = D.crew(s, ["ann", "ben"] as Array[String], ["a", "e"] as Array[String])
	# Ann in neutral light at 40; Ben alone in the dark, his 30 already gathered.
	D.stand_in(s, {ids[1]: 0.05})
	s.step(2)
	D.set_value(s, ids[0], 40.0)
	s.step(roundi(7.0 * Tuning.f(&"net.tick_hz")))
	assert_almost_eq(D.value(s, ids[1]), 30.0, 1e-6, "Ben's dark is gathered")
	stub.slot = s.run.vision.slot_of(ids[0])
	var cry_at: Vector2i = s.fixture.spot("c")
	for i: int in 200:
		if i % 20 == 0:
			s.run.noise.emit(NoiseTypes.Type.TRAPPED_CRY, cry_at)
		s.step(1)
	assert_gt(stub.played, 1000, "the illusions played")
	assert_almost_eq(D.value(s, ids[0]), 40.0, 1e-6, "no illusion and no scream moved Ann")
	assert_almost_eq(D.value(s, ids[1]), 30.0, 1e-6, "nor Ben")
	assert_eq(s.run.draught.cycle.phase, DraughtCycle.Phase.BUILD, "and nothing peaked")

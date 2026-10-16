extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-08 (Gameplay §3.6): two miners start the engine. One primes and holds the crank to its top;
## the other throttles half a second after the clank, and it catches: Start is done, and from the
## catch it knocks at 24 np every 40 ticks. The client sees the winder only by its look; nothing
## it receives names the fuel, the run-up or the window.

const E = preload("res://tests/unit/lift/engine_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_two_miners_start_the_engine() -> void:
	var s: Scenario = make({"seed": 7201, "fixture": E.T.C.scenario_fixture()})
	E.ready(s)
	var ann: MinerHandle = E.at(s, "ann", "engine_prime")
	var engine: WinderEngine = s.run.engine
	E.prime(s, ann)
	assert_eq(engine.state, WinderEngine.State.PRIMED)
	# Ann crosses to the crank; Bob takes the throttle.
	E.move_to(s, ann, "engine_crank")
	var bob: MinerHandle = E.at(s, "bob", "engine_throttle")
	var from: int = s.run.noise.event_log.size()
	E.hold(s, ann, 200)
	assert_true(E.throttle_after_cue(s, bob, 0.5), "Bob saw the clank")
	assert_eq(engine.state, WinderEngine.State.RUNNING, "it caught")
	assert_true(s.run.repair.is_done(&"start"))
	s.step(130)
	var beats: Array[NoiseSystem.Event] = E.events(s, NoiseTypes.Type.ENGINE_RUNNING, from)
	assert_gte(beats.size(), 3)
	for i: int in beats.size():
		assert_eq(beats[i].level_np, 24.0)
		if i > 0:
			assert_eq(beats[i].tick - beats[i - 1].tick, 40, "a beat every 2 s")
	assert_eq(beats[0].tick, engine.caught_at, "the first on the catch")
	# Ann's client, beside the crank: its fixture with the winder running, and nothing else of the engine.
	var look: int = -1
	for raw: Variant in ann.connection.view.entities.values():
		var e: Dictionary = raw
		var held: int = int(Variants.number(e.get("in_hand", 0)))
		if int(Variants.number(e.get("size_or_kind", 0))) == SeenKind.Kind.FIXTURE and FixtureKinds.kind_of(held) == FixtureKinds.Kind.ENGINE_CRANK:
			look = FixtureKinds.look_of(held)
	assert_eq(look, FixtureKinds.Look.RUNNING, "the winder looks like it runs")


## Never sent: the fuel, the run-up, the state as data or the window. Through a start and past the
## run-up, both clients get only the usual messages; the engine's fixtures carry their kind and, on
## the crank, the winder's look, nothing more; and the client's tuning names neither the run-up, the
## burn nor the window.
func test_a_client_gets_only_the_look_and_the_sounds() -> void:
	var s: Scenario = make({"seed": 7202, "fixture": E.T.C.scenario_fixture()})
	E.ready(s)
	var ann: MinerHandle = E.at(s, "ann", "engine_prime")
	var engine: WinderEngine = s.run.engine
	E.prime(s, ann)
	E.move_to(s, ann, "engine_crank")
	var bob: MinerHandle = E.at(s, "bob", "engine_throttle")
	E.hold(s, ann, 200)
	assert_true(E.throttle_after_cue(s, bob, 0.5))
	s.step(1250)
	assert_true(engine.run_up_complete(s.run), "past the run-up")
	var wrong: Array[String] = []
	var looks: Dictionary = {}
	for h: MinerHandle in [ann, bob]:
		for m: Dictionary in h.capture.messages:
			var type: int = int(Variants.number(m["type"]))
			if not type in [Protocol.Msg.FRAME, Protocol.Msg.STATUS, Protocol.Msg.INVENTORY, Protocol.Msg.PONG,
					Protocol.Msg.WELCOME, Protocol.Msg.SHEET, Protocol.Msg.CLOSE_UP, Protocol.Msg.AMBIENT]:
				wrong.append("%s got a %s" % [h.name, Protocol.Msg.find_key(type)])
		for raw_view: Variant in h.capture.views.values():
			var view: ReceivedView = raw_view
			for raw: Variant in view.entities.values():
				var e: Dictionary = raw
				if int(Variants.number(e.get("size_or_kind", 0))) != SeenKind.Kind.FIXTURE:
					continue
				var held: int = int(Variants.number(e.get("in_hand", 0)))
				var kind: FixtureKinds.Kind = FixtureKinds.kind_of(held)
				var bare: int = FixtureKinds.engine(FixtureKinds.look_of(held)) if kind == FixtureKinds.Kind.ENGINE_CRANK else kind
				if kind in [FixtureKinds.Kind.ENGINE_PRIME, FixtureKinds.Kind.ENGINE_CRANK, FixtureKinds.Kind.ENGINE_THROTTLE] and held != bare:
					wrong.append("%s saw %d on a %s" % [h.name, held, FixtureKinds.Kind.find_key(kind)])
				if kind == FixtureKinds.Kind.ENGINE_CRANK:
					looks[FixtureKinds.look_of(held)] = true
	assert_eq(wrong, [] as Array[String], "nothing but the kind and the look")
	assert_true(looks.has(FixtureKinds.Look.RUNNING), "the winder seen running")
	var table: Dictionary = Variants.dict(JSON.parse_string(FileAccess.get_file_as_string("res://data/tuning/_client.json")))
	var keys: Dictionary = Variants.dict(table.get("keys", table))
	for key: String in ["lift.clutch_run_up_s", "lift.engine_s_per_can", "lift.now_window_s", "lift.tank_unit_fills"]:
		assert_false(keys.has(key), "%s is server-only" % key)

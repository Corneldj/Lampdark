extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-08 (Gameplay §6.1): the running engine's beat is carried to every gate. A listener on the road
## just past each gate hears it at 24 np less the tiles from the gate's inner face when the gate is
## open, and 12 np less when it is shut (SND-01's closed portal); one event, from the winder and
## every gate at once.

const E = preload("res://tests/unit/lift/engine_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


## What `listener` (a tile) hears of the next beat, -1 if nothing.
func _heard(s: Scenario, listener: Vector2i) -> float:
	var heard: Array[float] = []
	var hook: Callable = func(id: int, record: Dictionary, _audit: Dictionary = {}) -> void:
		if id == 77 and int(Variants.number(record.get("type", 0))) == NoiseTypes.Type.ENGINE_RUNNING:
			heard.append(float(Variants.number(record["remaining_np"])))
	s.run.noise.player_hooks.append(hook)
	s.run.noise.set_player_listener(77, listener)
	s.step(42)
	s.run.noise.player_hooks.erase(hook)
	return heard[0] if not heard.is_empty() else -1.0


func test_the_beat_beyond_open_and_shut_gates() -> void:
	var s: Scenario = make({"seed": 7401, "fixture": E.T.C.scenario_fixture()})
	E.ready(s)
	var engine: WinderEngine = s.run.engine
	engine.state = WinderEngine.State.RUNNING
	engine.caught_at = s.run.tick + 1
	s.step(2)
	var checked: int = 0
	for raw: Variant in s.run.base_camp.gates:
		var spec: Dictionary = raw
		var gate: Gate = s.run.base_camp.gate_system.gate(str(spec["side"]))
		var inner: Vector2i = gate.middle() - gate.outward
		var past: Vector2i = gate.middle() + gate.outward
		E.T.C.shut_all(s, false)
		var path: float = s.run.road_graph.graph.path_cost(inner, past, RoadGraphService.MODE_AIR, 50.0)
		var open: float = _heard(s, past)
		E.T.C.shut_all(s, true)
		var shut: float = _heard(s, past)
		gut.p("%s gate: open %.1f, shut %.1f (%.0f tiles past its inner face)" % [spec["side"], open, shut, path])
		assert_almost_eq(open, 24.0 - path, 1e-6, "%s: 24 np through the open gate" % spec["side"])
		assert_almost_eq(shut, 12.0 - path, 1e-6, "%s: 12 np through the shut one" % spec["side"])
		checked += 1
	assert_eq(checked, 3, "every gate")
	var last: NoiseSystem.Event = E.events(s, NoiseTypes.Type.ENGINE_RUNNING).back()
	assert_eq(last.origins.size(), 4, "one event: the winder and three gates")

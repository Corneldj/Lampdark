extends "res://tests/scenario/kit/scenario_test.gd"
## VIS-06 with NET-05: Ann steps her wick up. On the very next client frame, before any server frame
## answers, the drawn pool reaches further (held floor under the predicted lamp, provisional); when the
## server's frames confirm the new radius, no tile changes by more than one quantisation step.

const FW = preload("res://tests/scenario/vis/flame_world.gd")
const L = preload("res://tests/unit/mnr/lamp_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _reach(lights: Dictionary, at: Vector2) -> float:
	var best: float = 0.0
	for raw: Variant in lights.keys():
		var t: Vector2i = raw
		if float(Variants.number(lights[raw])) >= Tuning.f(&"vision.seen_light_min"):
			best = maxf(best, (Vector2(t) + Vector2(0.5, 0.5)).distance_to(at))
	return best


func _frame(ann: MinerHandle, at: Vector2, radius: float) -> Dictionary:
	var view: ReceivedView = ann.connection.view
	var predicted: Dictionary = {"position": at, "facing": Intents.facing_u16(0.0), "lamp": {"position": at, "radius": radius}}
	var drawn: DrawnSet = DrawnSet.new()
	drawn.build(view, predicted, ann.connection.last_input_ack, -1)
	var server_lamp: Dictionary = {"position": view.own["position"], "radius": float(Variants.number(view.own["lamp_radius"]))}
	return OwnLampBlend.lights(drawn, view, server_lamp, {"position": at, "radius": radius})


func test_larger_pool_before_confirmation() -> void:
	var s: Scenario = make({"seed": 91, "fixture": FW.hall(40)})
	var ann: MinerHandle = s.add_miner("ann", Vector2i(10, 3), {"facing_deg": 0.0})
	ann.at(0).face(0.0).lamp(false, LampRules.WICK_NORMAL)
	s.step(1)
	L.lit_in_hand(s, ann)
	s.step(8)
	var at: Vector2 = s.run.registry.get_entity(ann.entity_id).position
	var normal: float = LampRules.hand_radius(2)
	var up: float = LampRules.hand_radius(4)
	var before: Dictionary = _frame(ann, at, normal)
	# The wick goes up on the client: drawn at once, the server not yet told.
	var predicted: Dictionary = _frame(ann, at, up)
	assert_gt(_reach(predicted, at), _reach(before, at) + 0.9, "the larger pool on the next frame")
	# The input reaches the server; its frames confirm the new radius.
	ann.at(s.run.tick).lamp(false, LampRules.WICK_UP)
	s.step(LampRules.step_ticks() + 8)
	assert_almost_eq(float(Variants.number(ann.connection.view.own["lamp_radius"])), up, 0.07, "confirmed")
	var confirmed: Dictionary = _frame(ann, at, up)
	var jumps: Array[String] = []
	for raw: Variant in predicted.keys():
		if confirmed.has(raw) and absf(float(Variants.number(confirmed[raw])) - float(Variants.number(predicted[raw]))) > 1.0 / 255.0 + 1e-6:
			jumps.append("%s: %.4f -> %.4f" % [raw, predicted[raw], confirmed[raw]])
	assert_eq(jumps.slice(0, 5), [] as Array[String], "no tile moves by more than one quantisation step")

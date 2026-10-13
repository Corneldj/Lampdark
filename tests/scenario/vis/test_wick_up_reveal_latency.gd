extends "res://tests/scenario/kit/scenario_test.gd"
## VIS-04: stepping the wick from normal to up at an emulated 120 ms round trip shows entities
## between 4 and 5 tiles before the 0.2 s step ends; 200 ms is reported for Q11. Ann holds a real
## gauze lamp (MNR-06), whose server pool ramps over the 0.2 s step from the tick it applies the
## press, as NET-05 predicts it.

const M = preload("res://tests/scenario/vis/margin_world.gd")
const L = preload("res://tests/unit/mnr/lamp_world.gd")
const LAMP_AT: Vector2 = Vector2(8.5, 4.5)
const SPOTS: Array[Vector2] = [Vector2(12.5, 5.5), Vector2(11.5, 7.5), Vector2(12.5, 6.5), Vector2(13.5, 4.5)]


func before_all() -> void:
	assert_true(Tuning.load_server())


func _run(rtt_ms: int, seed_value: int) -> Array[int]:
	var s: Scenario = make({"seed": seed_value, "fixture": M.room()})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"), {"facing_deg": 0.0})
	ann.at(0).face(0.0)
	ann.link(rtt_ms, 0.0)
	s.enable_prediction(ann)
	s.step(1)
	var lamp_held: GauzeLamp = L.lit_in_hand(s, ann)
	assert_eq(s.run.registry.get_entity(ann.entity_id).position, LAMP_AT)
	for p: Vector2 in SPOTS:
		s.run.registry.create(WorldIds.EntityKind.MOTH, p)
	s.step(30)
	var reveal: MarginReveal = MarginReveal.new()
	assert_eq(_shown(ann, reveal).size(), 0, "before the step, all four are held hidden")
	var change: int = s.run.tick
	ann.at(change).lamp(false, 2)
	var first: Array[int] = [-1, -1, -1, -1]
	var lit: Array[int] = [-1, -1, -1, -1]
	for i: int in 12:
		s.step(1)
		# Ticks since the client sampled and predicted the input (it does so inside step `change`).
		var since: int = s.run.tick - 1 - change
		var shown: Dictionary = _shown(ann, reveal)
		var lamp: Dictionary = ann.prediction.lamp()
		for j: int in SPOTS.size():
			if lit[j] < 0 and Variants.number(lamp["radius"]) >= LAMP_AT.distance_to(SPOTS[j]):
				lit[j] = since
			if first[j] < 0 and shown.has(SPOTS[j]):
				first[j] = since
				assert_gte(lit[j], 0, "never shown before the predicted light reaches it")
	var tick_ms: float = 1000.0 / Tuning.f(&"net.tick_hz")
	for j: int in SPOTS.size():
		gut.p("%d ms RTT: entity at %.2f tiles lit by the predicted pool at +%d ms, shown at +%d ms (step %d ms)" % [
			rtt_ms, LAMP_AT.distance_to(SPOTS[j]), lit[j] * tick_ms, first[j] * tick_ms, LampRules.step_ticks() * tick_ms])
	assert_eq(lamp_held.wick, LampRules.WICK_UP, "the real lamp stepped up")
	return first


## Positions the client draws: seen records, and hidden ones its predicted light has revealed.
func _shown(ann: MinerHandle, reveal: MarginReveal) -> Dictionary:
	var out: Dictionary = {}
	var view: ReceivedView = ann.connection.view
	if view == null:
		return out
	var revealed: Array[int] = reveal.revealed(view, ann.prediction.lamp(), Vector2(ann.prediction.state.x, ann.prediction.state.y), ann.prediction.state.facing)
	for raw: Variant in view.entities.keys():
		var e: Dictionary = view.entities[raw]
		var p: Vector2 = e["position"]
		if int(Variants.number(e["level"])) != MarginReveal.HIDDEN or revealed.has(int(Variants.number(raw))):
			out[p.snapped(Vector2(0.01, 0.01))] = true
	return out


func test_at_120_ms_before_the_step_ends() -> void:
	var first: Array[int] = _run(120, 51)
	var steps: int = roundi(Tuning.f(&"lamp.shutter_time") * Tuning.f(&"net.tick_hz"))
	for j: int in first.size():
		assert_between(first[j], 0, steps - 1, "shown before the 0.2 s step ends: %s" % SPOTS[j])


func test_at_200_ms_for_q11() -> void:
	var first: Array[int] = _run(200, 52)
	var steps: int = roundi(Tuning.f(&"lamp.shutter_time") * Tuning.f(&"net.tick_hz"))
	for j: int in first.size():
		assert_between(first[j], 0, steps - 1, "200 ms: shown before the step ends too: %s" % SPOTS[j])

extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-06 with NET-05: at a 120 ms round trip, the owner's own shutter is predicted at once and
## confirmed by the server without a visible snap: the predicted pool falls steadily to 0 and the
## server's confirmation never pushes it back up or changes its scale.

const W = preload("res://tests/unit/mnr/belt_world.gd")
const L = preload("res://tests/unit/mnr/lamp_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_own_shutter_predicted_then_confirmed() -> void:
	var s: Scenario = make({"seed": 43, "fixture": W.room()})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	ann.link(120, 0.0)
	s.enable_prediction(ann)
	s.step(1)
	L.lit_in_hand(s, ann)
	s.step(30)
	assert_almost_eq(ann.prediction.radius_mult, 1.0, 1e-3, "server and prediction agree before the press")
	var press: int = s.run.tick
	ann.at(press).lamp(true, 1)
	var predicted: Array[float] = []
	var mults: Array[float] = []
	for _i: int in 30:
		s.step(1)
		predicted.append(Variants.number(ann.prediction.lamp()["radius"]))
		mults.append(ann.prediction.radius_mult)
	var steps: int = LampRules.step_ticks()
	assert_almost_eq(predicted[steps], 0.0, 1e-6, "predicted shut within the step, before any confirmation")
	for i: int in range(1, predicted.size()):
		assert_lte(predicted[i], predicted[i - 1] + 1e-6, "never pushed back up (tick %d)" % i)
		assert_lte(predicted[i - 1] - predicted[i], 1.0 + 1e-6, "no jump bigger than one tick of the ramp")
	for m: float in mults:
		assert_almost_eq(m, 1.0, 1e-3, "the confirmation never rescales the pool")
	assert_eq(s.run.light.grid.owned_radius(ann.entity_id), 0.0, "the server agrees")

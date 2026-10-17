extends "res://tests/scenario/kit/scenario_test.gd"
## HAZ-03 (Gameplay §12.5, §6.9): a shot within 6 tiles by path (MNR-16's 40 np, stubbed as its
## event) and a firedamp blast within 7 in a straight line (HAZ-04's, stubbed the same way) each start
## the creak, and a running step still does in a Fan surge: the roof is not a creature. A shot 7
## tiles off, or a blast 8 off, does not. A second trigger mid-creak changes nothing.

const W = preload("res://tests/unit/hazards/collapse_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _point(run_seed: int) -> Array:
	var s: Scenario = make(W.cfg(run_seed))
	var p: CollapsePoints.Point = W.arm(s)
	return [s, p]


func _emit(s: Scenario, type: NoiseTypes.Type, tile: Vector2i) -> void:
	s.run.noise.emit(type, tile)
	s.step(2)


func test_a_shot_within_six_by_path() -> void:
	var w: Array = _point(3501)
	var s: Scenario = w[0]
	var p: CollapsePoints.Point = w[1]
	_emit(s, NoiseTypes.Type.SHOT, Vector2i(W.WEST - 7, 2))
	assert_eq(p.state, CollapsePoints.State.STANDING, "a shot 7 tiles off does not")
	_emit(s, NoiseTypes.Type.SHOT, Vector2i(W.WEST - 6, 2))
	assert_eq(p.state, CollapsePoints.State.CREAKING, "a shot 6 tiles off does")
	var fall: int = p.fall_tick
	_emit(s, NoiseTypes.Type.FIREDAMP_BLAST, Vector2i(W.EAST + 1, 2))
	assert_eq(p.fall_tick, fall, "a second trigger mid-creak changes nothing")
	assert_gt(W.until_fallen(s, p.id), 0, "and it falls on time")


func test_a_blast_within_seven_in_a_straight_line() -> void:
	var w: Array = _point(3502)
	var s: Scenario = w[0]
	var p: CollapsePoints.Point = w[1]
	_emit(s, NoiseTypes.Type.FIREDAMP_BLAST, Vector2i(W.WEST - 8, 2))
	assert_eq(p.state, CollapsePoints.State.STANDING, "a blast 8 tiles off does not")
	_emit(s, NoiseTypes.Type.FIREDAMP_BLAST, Vector2i(W.WEST - 7, 2))
	assert_eq(p.state, CollapsePoints.State.CREAKING, "a blast 7 tiles off does")


func test_a_fan_surge_never_stops_it() -> void:
	var w: Array = _point(3503)
	var s: Scenario = w[0]
	var p: CollapsePoints.Point = w[1]
	# SND-11's surge: the creatures lose every event under 22 np; the roof still hears 18.
	s.run.noise.creature_filter = func(event: NoiseSystem.Event, _d: Dictionary) -> bool: return event.level_np >= 22.0
	_emit(s, NoiseTypes.Type.STEP_RUN, Vector2i(W.WEST - 4, 2))
	assert_eq(p.state, CollapsePoints.State.CREAKING, "the roof is not a creature")

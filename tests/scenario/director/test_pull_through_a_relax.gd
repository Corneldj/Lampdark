extends "res://tests/scenario/kit/scenario_test.gd"
## DIR-03 and DIR-02 (Gameplay §10.3, §10.5): a relax never pauses the Pull. Two runs with the same
## miners, moves and rings, one through a 45 s relax, the other with none: every Pull moves the same,
## tick for tick, and is equal at the relax's end.

const D = preload("res://tests/scenario/director/draught_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


## Ann alone, Ben and Cat a pair; [value of each, every 20 ticks] over 45 s, with or without a relax.
func _run(relax: bool) -> Array:
	var s: Scenario = make({"seed": 2601, "fixture": D.hall(), "director": true})
	var ids: Array[int] = D.crew(s, ["ann", "ben", "cat"] as Array[String], ["a", "d", "e"] as Array[String])
	D.stand_in(s)
	s.run.pull.ring_of = func(_m: int) -> int: return 2
	s.step(2)
	s.run.movement.place(s.run, ids[2], Vector2(22.5, 1.5)) # Cat beside Ben
	for e: int in ids:
		s.run.pull.set_value(e, 40.0)
	if relax:
		D.force_relax(s, true)
	var samples: Array = []
	for i: int in 45 * 20:
		s.step(1)
		if i % 20 == 19:
			var row: Array[float] = []
			for e: int in ids:
				row.append(s.run.pull.value_of(e))
			samples.append(row)
	assert_eq(s.run.draught.cycle.in_relax(), relax, "the relax %s" % ("held throughout" if relax else "never came"))
	return samples


func test_the_pull_moves_the_same_in_a_relax() -> void:
	var calm: Array = _run(false)
	var quiet: Array = _run(true)
	assert_eq(quiet.size(), calm.size())
	for i: int in calm.size():
		var with_relax: Array = quiet[i]
		var without: Array = calm[i]
		assert_eq(with_relax, without, "second %d: the same Pull, relax or not" % (i + 1))
	var last: Array = calm[calm.size() - 1]
	assert_gt(float(Variants.number(last[0])), 40.0, "the alone gained")
	assert_gt(float(Variants.number(last[1])), 40.0, "the pair gained")

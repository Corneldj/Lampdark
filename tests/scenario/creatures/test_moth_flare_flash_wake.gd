extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-03: a flare or muzzle flash in its line of sight within 30 tiles wakes it at the stir's
## end; one at 31 tiles, or behind a wall, does not.

const W = preload("res://tests/scenario/creatures/moth_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _flash(kind: String, at: Vector2, wall: bool) -> StringName:
	var rows: PackedStringArray = W.road().rows
	var fixture: FixtureMap = W.road()
	if wall:
		var r: String = rows[2]
		rows[2] = r.substr(0, 25) + "#" + r.substr(26)
		fixture = FixtureMap.from_ascii(rows)
	var s: Scenario = make({"seed": 14, "fixture": fixture})
	var m: Moth = W.moth(s)
	s.step(2)
	s.run.light.grid.add_point(kind, 2, 0, 0, 0.5, 0.2, at, 5)
	s.step(40)
	# Awake, CRT-04 hunts on from Frenzy (the waker is known for 10 s): what counts is the wake.
	for e: Dictionary in s.run.creatures.log.of_type(&"state"):
		if Variants.dict(e.get("fields", e)).get("to", &"") == &"frenzy":
			return &"frenzy"
	return m.state.name


func test_flare_and_flash() -> void:
	assert_eq(_flash("flare", Vector2(40.5, 2.5), false), &"frenzy", "a flare 30 tiles off in sight")
	assert_eq(_flash("muzzle_flash", Vector2(40.5, 2.5), false), &"frenzy", "a flash 30 tiles off")
	assert_eq(_flash("flare", Vector2(41.5, 2.5), false), &"asleep", "31 tiles: nothing")
	assert_eq(_flash("flare", Vector2(35.5, 2.5), true), &"asleep", "behind a wall: nothing")
	assert_eq(_flash("gauze_lamp", Vector2(35.5, 2.5), false), &"asleep", "an ordinary lamp far off: nothing")

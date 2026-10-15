extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-16: the shot hits the first body on its line within 20 tiles, seen or not; rock, a closed
## air door and a shut gate stop it; the Tapper is a target only by its arm, in WindUp, Pin and
## ReStrike.

const R = preload("res://tests/unit/mnr/revolver_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _shoot(s: Scenario, ann: MinerHandle) -> Dictionary:
	R.trigger(s, ann)
	s.step(8)
	return s.run.revolver.shots[s.run.revolver.shots.size() - 1]


func test_the_first_body_within_twenty_seen_or_not() -> void:
	var s: Scenario = make({"seed": 1221, "fixture": R.hall(40)})
	var ann: MinerHandle = R.miner(s, "ann", Vector2i(2, 2))
	var near: int = s.run.registry.create(WorldIds.EntityKind.MINER, Vector2(12.5, 2.5)).id
	var far: int = s.run.registry.create(WorldIds.EntityKind.MINER, Vector2(16.5, 2.5)).id
	s.step(2)
	R.armed(s, ann)
	R.aim(s, ann)
	s.step(3)
	var shot: Dictionary = _shoot(s, ann)
	assert_eq(int(Variants.number(shot["hit"])), near, "the nearer body, in the dark (nothing lit)")
	s.run.registry.destroy(near)
	s.run.registry.destroy(far)
	var beyond: int = s.run.registry.create(WorldIds.EntityKind.MINER, Vector2(24.0, 2.5)).id
	s.step(12)
	shot = _shoot(s, ann)
	assert_eq(int(Variants.number(shot["hit"])), 0, "21.5 tiles off: beyond its 20")
	assert_true(s.run.registry.has(beyond))


func test_rock_doors_and_gates_stop_it() -> void:
	var picture: PackedStringArray = PackedStringArray(["#" .repeat(30), "#....#....D....G....#.......#", "#" .repeat(30)])
	var s: Scenario = make({"seed": 1222, "fixture": FixtureMap.from_ascii(picture)})
	var ann: MinerHandle = R.miner(s, "ann", Vector2i(2, 1))
	var behind_rock: int = s.run.registry.create(WorldIds.EntityKind.MINER, Vector2(7.5, 1.5)).id
	s.step(2)
	R.armed(s, ann)
	R.aim(s, ann)
	s.step(3)
	var shot: Dictionary = _shoot(s, ann)
	assert_eq(int(Variants.number(shot["hit"])), 0, "rock stops it")
	assert_eq(StringName(str(shot["outcome"])), &"wall")
	assert_true(s.run.registry.has(behind_rock))
	s.run.mine.native.unload(Vector2i(0, 0))
	picture[1] = "#.........D....G....#.......#"
	var s2: Scenario = make({"seed": 1223, "fixture": FixtureMap.from_ascii(picture)})
	var bob: MinerHandle = R.miner(s2, "bob", Vector2i(2, 1))
	var past_door: int = s2.run.registry.create(WorldIds.EntityKind.MINER, Vector2(12.5, 1.5)).id
	s2.step(2)
	R.armed(s2, bob)
	R.aim(s2, bob)
	s2.step(3)
	assert_eq(StringName(str(_shoot(s2, bob)["outcome"])), &"wall", "a closed air door stops it")
	assert_ne(s2.run.miner_state.life(past_door) if s2.run.miner_state.miner(past_door) != null else 0, MinerTransitions.Life.DEAD)
	s2.run.mine.native.set_barrier(Vector2i(0, 0), s2.run.air_doors.door_at(Vector2i(10, 1)).barrier, true)
	s2.step(12)
	var through: Dictionary = _shoot(s2, bob)
	assert_eq(int(Variants.number(through["hit"])), past_door, "opened, it passes")
	s2.run.registry.destroy(past_door)
	var past_gate: int = s2.run.registry.create(WorldIds.EntityKind.MINER, Vector2(17.5, 1.5)).id
	s2.step(12)
	assert_true(s2.set_gate(1, false))
	s2.step(2)
	assert_eq(StringName(str(_shoot(s2, bob)["outcome"])), &"wall", "a shut gate stops it")
	assert_true(s2.run.registry.has(past_gate))


func test_the_tapper_only_by_its_arm_in_windup_pin_and_restrike() -> void:
	var hittable: Array[String] = []
	var t: Tapper = Tapper.new()
	for st: CreatureState in t.define_states():
		if st.hittable:
			hittable.append(str(st.name))
	hittable.sort()
	assert_eq(hittable, ["pin", "restrike", "windup"] as Array[String], "only these states")
	assert_eq(t.hit_body(), 0.0, "in the rock: no body to hit")

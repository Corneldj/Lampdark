extends "res://tests/scenario/kit/scenario_test.gd"
## VIS-08 (Clause 4; the nightly soak's assertion, run short here): over a minute of a stirring Moth,
## a stand-in Stythe's tell switching on and off, firedamp and blackdamp patches, every flame state on
## every lamp agrees each tick with the causes then in force, and every change is logged with one.

const FW = preload("res://tests/scenario/vis/flame_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_never_a_state_without_its_cause() -> void:
	var s: Scenario = make({"seed": 64, "fixture": FW.hall(60)})
	s.step(1)
	var lamps: Array[GauzeLamp] = []
	for x: int in [3, 12, 21, 30, 39, 48, 57]:
		lamps.append(FW.lamp(s, Vector2i(x, 1 + x % 3)))
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 64
	var active: Array[bool] = [false]
	var stythe_at: Vector2 = Vector2(25.5, 3.5)
	FW.stythe(s, stythe_at, active)
	s.run.flame_states.firedamp_at = func(tile: Vector2i) -> bool: return tile.x >= 45
	s.run.flame_states.blackdamp_s = func(_id: int, tile: Vector2i) -> float: return 2.0 if tile.x < 6 else 0.0
	s.place_creature(WorldIds.EntityKind.MOTH, Vector2i(40, 3))
	var m: Moth = s.run.creatures.creature_of_kind(WorldIds.EntityKind.MOTH)
	var reach_m: float = Tuning.f(&"moth.tell_reach_tiles")
	var reach_s: float = Tuning.f(&"stythe.tell_reach_tiles")
	var mismatches: Array[String] = []
	for i: int in 1200:
		if i % 97 == 0:
			active[0] = rng.randf() < 0.5
		if i % 300 == 50 and m.state.name == &"sleeping":
			m._stir(s.run, MothSleep.Cause.CLOCK)
		s.step(1)
		for l: GauzeLamp in lamps:
			var at: Vector2 = l.at
			var tile: Vector2i = Vector2i(floori(at.x), floori(at.y))
			var want: int = 0
			if m.tell_active() and m.position(s.run).distance_to(at) <= reach_m:
				want |= FlameFlags.TREMBLE
			if active[0] and stythe_at.distance_to(at) <= reach_s:
				want |= FlameFlags.GUTTER
			if tile.x >= 45:
				want |= FlameFlags.CAP
			if tile.x < 6:
				want |= FlameFlags.SHRINK
			var got: int = s.run.flame_states.flags_of(l.source) if l.source != 0 else 0
			if l.source != 0 and got != want:
				mismatches.append("tick %d lamp at %s: got %d, causes give %d" % [s.run.tick, tile, got, want])
	assert_eq(mismatches.slice(0, 5), [] as Array[String], "every state has its cause, every cause its state")
	assert_gt(s.run.flame_states.changes.size(), 10, "states came and went")
	for c: Dictionary in s.run.flame_states.changes:
		assert_false(str(c["cause"]).is_empty(), "a logged cause for %s at %d" % [c["state"], c["tick"]])

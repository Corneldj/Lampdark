extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-15: keeping a body, the Stythe never goes more than 50 tiles by path from its lair; it
## ignores a Pull-80 miner outside its territory; with no laid body left on the lair's tiles it goes
## from Keep to Lurk.

const H = preload("res://tests/scenario/creatures/stythe_hunt_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_keeping_it_stays_in_its_territory() -> void:
	var s: Scenario = make({"seed": 1511, "fixture": H.road(150), "overrides": H.W.ON})
	var h: H = H.new()
	h.build(s, 110, 107, 145)
	assert_true(h.until_state(&"keep", 1600), "it took Ann home and keeps her")
	var bob: MinerHandle = H.W.miner(s, "bob", Vector2i(60, 2), 0.0)
	h.pulls[bob.entity_id] = 80.0
	var territory: float = Tuning.f(&"stythe.territory_tiles")
	var worst: float = 0.0
	for _i: int in 2400:
		s.step(1)
		var d: float = h.st.senses.lair_distance(s.run, h.st, h.st.tile(s.run))
		worst = maxf(worst, d)
		assert_ne(h.st.hunt.target, bob.entity_id, "never hunts Bob at Pull 80 outside its territory")
	gut.p("farthest from the lair while keeping: %.1f tiles by path" % worst)
	assert_lte(worst, territory + 1e-3, "never more than 50 tiles by path from the lair")
	assert_true(h.st.keeps())


func test_with_no_body_left_it_lurks() -> void:
	var s: Scenario = make({"seed": 1512, "fixture": H.road(), "overrides": H.W.ON})
	var h: H = H.new()
	h.build(s, 40, 37, 95)
	assert_true(h.until_state(&"keep", 1600))
	var ann: int = h.ann.entity_id
	s.run.movement.place(s.run, ann, Vector2(70.5, 2.5))  # carried off the lair's tiles
	s.step(2)
	assert_false(h.st.keeps(), "nobody kept")
	assert_false(s.run.falls.body_of(ann).kept_in_lair)
	assert_ne(h.st.state.name, &"keep", "Keep gives way")
	assert_eq(h.st.home.next_slot(), 0, "her slot is free again")

extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-01 with CRT-02's dark walker (CRT-13 re-runs it with the real Stythe): at 0.6 every inside
## tile is a wall to the Stythe, even the Thin (0.50); no dark path reaches inside.

const C = preload("res://tests/scenario/basecamp/camp_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_walled_out() -> void:
	var s: Scenario = make({"seed": 9, "fixture": C.scenario_fixture()})
	var camp: BaseCampState = C.load_camp(s, 0)
	s.step(2)
	var nav: CreatureNav = s.run.creatures.nav
	for thin: bool in [false, true]:
		for t: Vector2i in camp.inside_tiles.keys():
			assert_false(nav.native.passable(NavModes.Mode.DARK, t, NavModes.dark(thin)), "a wall even to the Thin")
	var g: Dictionary = camp.gates[0]
	var outward: Vector2i = g["outward"]
	var tiles: Array = g["tiles"]
	var mid: Vector2i = tiles[1]
	var deck: Rect2i = Basecamp.deck_rect(C.SEED, 0)
	var r: Dictionary = nav.native.path(NavModes.Mode.DARK, mid + outward * 8, deck.position, NavModes.dark(true))
	assert_false(Variants.flag(r["found"]), "no dark path in, even for the Thin")


## CRT-13 re-runs it with the real Stythe: a Thin Stythe chasing a miner on the cage deck from
## beyond the gates never sets foot inside.
func test_the_real_thin_stythe_stays_out() -> void:
	var s: Scenario = make({"seed": 10, "fixture": C.scenario_fixture(),
		"overrides": {"creatures.enabled": {"moth": 1, "tapper": 1, "stythe": 1}}})
	var camp: BaseCampState = C.load_camp(s, 0)
	s.step(2)
	var g: Dictionary = camp.gates[0]
	var outward: Vector2i = g["outward"]
	var tiles: Array = g["tiles"]
	var mid: Vector2i = tiles[1]
	var id: int = s.place_creature(WorldIds.EntityKind.STYTHE, mid + outward * 8)
	assert_ne(id, 0, "placed outside")
	var st: StytheCreature = s.run.creatures.creature_of(id) as StytheCreature
	st.thin = true
	var deck: Rect2i = Basecamp.deck_rect(C.SEED, 0)
	var ann: MinerHandle = s.add_miner("ann", deck.position)
	ann.brain = null
	for _i: int in 400:
		st.chase(s.run, ann.entity_id)
		s.step(1)
		assert_false(camp.inside_tiles.has(st.tile(s.run)), "never inside base camp, tick %d" % s.run.tick)


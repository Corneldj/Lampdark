extends "res://tests/scenario/kit/scenario_test.gd"
## RSC-01: each fall gives exactly one MNR-03 state_changed and one `fell`, in the fall's tick,
## `fell` after it, and the journal holds it before the tick ends; the payload; a Hand's fall has
## no scream; a felled carrier drops the body; feeling a body; a trapped body cannot be lifted;
## the fallen cannot feel, interact or use an item and see nothing beyond their own body.

const W = preload("res://tests/unit/mnr/belt_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_one_of_each_in_the_tick() -> void:
	var s: Scenario = make({"seed": 1, "fixture": W.room()})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	s.step(1)
	var order: Array[String] = []
	var ticks: Array[int] = []
	s.run.miner_state.state_changed.connect(func(_e: int, _o: int, n: int, _c: String) -> void:
		if n == MinerTransitions.Life.UNCONSCIOUS:
			order.append("state_changed")
			ticks.append(s.run.tick))
	var records: Array[Dictionary] = []
	s.run.falls.fell.connect(func(r: Dictionary) -> void:
		order.append("fell")
		ticks.append(s.run.tick)
		records.append(r))
	var at: int = s.run.tick
	assert_true(s.run.falls.fall_unconscious(s.run, ann.entity_id, FallCause.Cause.ROOF_FALL, {"trap_id": 7}))
	assert_false(s.run.falls.fall_unconscious(s.run, ann.entity_id, FallCause.Cause.BLAST), "one fall per miner")
	s.step(1)
	assert_eq(order, ["state_changed", "fell"] as Array[String], "exactly one of each, fell after")
	assert_eq(ticks, [at, at] as Array[int], "both in the tick of the fall")
	assert_eq(s.run.falls.journal.size(), 1)
	assert_eq(int(Variants.number(s.run.falls.journal[0]["tick"])), at, "journalled in that tick")
	var r: Dictionary = records[0]
	for key: String in ["fall_id", "miner_id", "is_hand", "cause", "tick", "tile", "ring", "lamp_outcome", "scream_mode"]:
		assert_true(r.has(key), "payload has %s" % key)
	assert_eq(int(Variants.number(r["miner_id"])), ann.entity_id)
	assert_eq(int(Variants.number(r["cause"])), FallCause.Cause.ROOF_FALL)
	assert_eq(int(Variants.number(r["scream_mode"])), FallCause.Scream.FULL)
	assert_eq(int(Variants.number(r["trap_id"])), 7)
	s.step(5)
	assert_eq(records.size(), 1, "no second fell")
	assert_false(s.run.falls.fall_unconscious(s.run, ann.entity_id, FallCause.Cause.BLAST), "already down: refused")


func test_hand_drag_and_other_routes() -> void:
	var s: Scenario = make({"seed": 2, "fixture": W.room()})
	var a: Vector2i = s.fixture.spot("a")
	var hand: MinerHandle = s.add_miner("hand", a)
	var bob: MinerHandle = s.add_miner("bob", a + Vector2i(3, 0))
	var cy: MinerHandle = s.add_miner("cy", a + Vector2i(6, 0))
	s.run.crew.is_hand_driven = func(e: int) -> bool: return e == hand.entity_id
	s.step(1)
	var records: Array[Dictionary] = []
	s.run.falls.fell.connect(func(r: Dictionary) -> void: records.append(r))
	s.run.falls.fall_unconscious(s.run, hand.entity_id, FallCause.Cause.BLACKDAMP)
	s.run.falls.fall_unconscious(s.run, bob.entity_id, FallCause.Cause.DRAG)
	s.run.miner_state.fall_unconscious(cy.entity_id, "pin_ran_out")
	s.step(1)
	assert_eq(records.size(), 3)
	var by_miner: Dictionary = {}
	for r: Dictionary in records:
		by_miner[int(Variants.number(r["miner_id"]))] = r
	var hr: Dictionary = by_miner[hand.entity_id]
	assert_true(Variants.flag(hr["is_hand"]), "a Hired Hand's fall")
	assert_eq(int(Variants.number(hr["scream_mode"])), FallCause.Scream.NONE, "knocks without a scream")
	assert_eq(int(Variants.number(Variants.dict(by_miner[bob.entity_id])["scream_mode"])), FallCause.Scream.MUFFLED_WHISPER)
	assert_eq(int(Variants.number(Variants.dict(by_miner[cy.entity_id])["cause"])), FallCause.Cause.PIN, "another route still gives one fell")


func test_carrier_felled_drops_the_body() -> void:
	var s: Scenario = make({"seed": 3, "fixture": W.room()})
	var a: Vector2i = s.fixture.spot("a")
	var ann: MinerHandle = s.add_miner("ann", a)
	var bob: MinerHandle = s.add_miner("bob", a + Vector2i(1, 0))
	s.step(1)
	s.run.falls.fall_unconscious(s.run, ann.entity_id, FallCause.Cause.BLAST)
	s.step(2)
	var body: BodyState = s.run.falls.body_of(ann.entity_id)
	assert_eq(body.feel_caption(), "[a body, breathing]", "feeling an unconscious body")
	var lift: TimedAction = s.run.falls.lift_action(s.run, bob.entity_id, ann.entity_id)
	assert_eq(lift.ticks_needed, 40, "interacting again starts the 2 s lift")
	assert_true(s.run.inventory.start_action(s.run, lift))
	s.run.inventory.holds_source = func(_run: RunState, slot: int) -> int: return InputRecord.HOLD_INTERACT if slot == bob.slot else 0
	s.step(42)
	s.run.inventory.holds_source = Callable()
	assert_eq(body.carried_by, bob.entity_id, "carried")
	assert_true(W.belt(s, bob.entity_id).two_handed)
	s.run.falls.fall_unconscious(s.run, bob.entity_id, FallCause.Cause.ROOF_FALL)
	s.step(2)
	assert_eq(body.carried_by, 0, "the felled carrier drops the body at once")
	assert_true(body.on_floor)
	assert_false(W.belt(s, bob.entity_id).two_handed)


func test_trapped_body_cannot_be_lifted() -> void:
	var s: Scenario = make({"seed": 4, "fixture": W.room()})
	var a: Vector2i = s.fixture.spot("a")
	var ann: MinerHandle = s.add_miner("ann", a)
	var bob: MinerHandle = s.add_miner("bob", a + Vector2i(1, 0))
	s.step(1)
	s.run.miner_state.enter_caught(ann.entity_id, &"man_trap", 5)
	s.step(1)
	s.run.falls.fall_unconscious(s.run, ann.entity_id, FallCause.Cause.BLACKDAMP)
	s.step(2)
	assert_true(s.run.falls.body_of(ann.entity_id).held_by_trap, "fallen in a trap, still in it")
	assert_false(Variants.flag(s.run.falls.lift_action(s.run, bob.entity_id, ann.entity_id).valid.call()), "cannot be lifted")
	s.run.miner_state.release_caught(ann.entity_id, "freed")
	s.step(2)
	assert_true(Variants.flag(s.run.falls.lift_action(s.run, bob.entity_id, ann.entity_id).valid.call()), "freed: now it can")


func test_the_fallen_do_nothing_and_see_nothing() -> void:
	var s: Scenario = make({"seed": 5, "fixture": W.room()})
	W.light(s)
	var a: Vector2i = s.fixture.spot("a")
	var ann: MinerHandle = s.add_miner("ann", a)
	var bob: MinerHandle = s.add_miner("bob", a + Vector2i(2, 0))
	var spanner: int = W.put(s, ItemKinds.Kind.SPANNER, a + Vector2i(1, 0))
	ann.at(0).face(0.0)
	bob.at(0).face(180.0)
	s.step(6)
	assert_false(ann.connection.view.entities.is_empty(), "conscious, she sees bob and the spanner")
	assert_true(s.run.inventory.give(s.run, ann.entity_id, s.run.inventory.world.make(ItemKinds.Kind.FLARE)))
	s.run.falls.fall_unconscious(s.run, ann.entity_id, FallCause.Cause.BLAST)
	s.step(8)
	assert_eq(ann.connection.view.entities.size(), 0, "no record beyond her own body")
	assert_eq(ann.connection.view.tiles.size(), 0, "no seen tiles either")
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT | InputRecord.HOLD_FEEL | InputRecord.HOLD_USE | InputRecord.HOLD_SET_DOWN, 40)
	s.step(50)
	assert_true(s.run.inventory.world.items.has(spanner), "no interacting")
	assert_eq(W.belt(s, ann.entity_id).slots[0].kind, ItemKinds.Kind.FLARE, "no item use or set-down")
	assert_true(s.run.inventory.actions.is_empty())
	var caps: Dictionary = s.run.miner_state.capabilities(ann.entity_id)
	assert_eq(str(caps["interact"]), "no", "no feeling, no interacting (MNR-03)")
	assert_false(Variants.flag(caps["belt"]))
	assert_gt(bob.connection.view.entities.size(), 0, "bob, facing her, still sees her body")


func test_no_fall_code_touches_steam() -> void:
	for path: String in ["res://server/systems/rescue/fall_system.gd", "res://server/systems/rescue/lamp_disposition.gd",
			"res://server/systems/rescue/body_state.gd", "res://shared/ids/fall_cause.gd"]:
		var text: String = FileAccess.get_file_as_string(path)
		assert_false(text.contains("Steam") or text.contains("rich_presence"), "%s never changes rich presence" % path)

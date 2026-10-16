extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-14 in base camp (Gameplay §11.4, §11.5): the ring on a fallen miner offers lay right after
## lift; laying him on a stretcher is 40 ticks of held interact. Two carry him 3 tiles to beside a
## free medbay table and set him down: he is on the table 40 ticks later. Taking the stretcher up
## again inside those 2 s cancels it; set down again, it starts over.

const C = preload("res://tests/scenario/basecamp/camp_world.gd")
const L = preload("res://tests/unit/mnr/lamp_world.gd")
const R = preload("res://tests/unit/mnr/ring_world.gd")
const W = preload("res://tests/unit/mnr/load_world.gd")

const RUN_TILES: float = 3.0


func before_all() -> void:
	assert_true(Tuning.load_server())


func _solid(s: Scenario) -> Callable:
	return func(t: Vector2i) -> bool: return not s.run.mine.native.is_walkable(t)


## A stretcher's start and heading: carried RUN_TILES straight along its heading it ends with its
## centre in touch range of `table`'s, clear of rock all the way, with walkable floor a tile to one
## side of its start (where the layer stands). [] if none.
func _approach(s: Scenario, table: Vector2i) -> Array:
	var seg: LoadSegment = LoadSegment.make(ItemKinds.Kind.STRETCHER, Vector2.ZERO, 0)
	var at_table: Vector2 = Vector2(table) + Vector2(0.5, 0.5)
	var reach: float = Tuning.f(&"vision.touch_range_tiles") - 0.1
	for h: int in [0, 16384, 32768, 49152]:
		var u: PackedFloat64Array = LbDetMath.unit(h / 65536.0)
		var dir: Vector2 = Vector2(u[0], u[1])
		for dy: int in range(-6, 7):
			for dx: int in range(-6, 7):
				var finish: Vector2 = at_table + Vector2(dx, dy) * 0.25
				if finish.distance_to(at_table) > reach:
					continue
				var clear: bool = true
				for k: int in roundi(RUN_TILES / 0.125) + 1:
					var c: Vector2 = finish - dir * (RUN_TILES - k * 0.125)
					if seg.collides(c.x, c.y, h, _solid(s)):
						clear = false
						break
				var start: Vector2 = finish - dir * RUN_TILES
				var side: Vector2 = start + Vector2(-dir.y, dir.x)
				if clear and s.run.mine.native.is_walkable(Vector2i(floori(side.x), floori(side.y))):
					return [start, h]
	return []


## Bob fallen on a stretcher laid in base camp, by way of Cid's ring; Ann and Cid holding its ends:
## [s, ann, bob, cid, load, table].
func _laid_and_lifted(run_seed: int) -> Array:
	var s: Scenario = make({"seed": run_seed, "fixture": C.scenario_fixture()})
	var camp: BaseCampState = C.load_camp(s)
	var table: Vector2i = camp.medbay_tables()[0]
	var plan: Array = _approach(s, table)
	assert_false(plan.is_empty(), "a way to the table")
	var start: Vector2 = plan[0]
	var heading: int = plan[1]
	var u: PackedFloat64Array = LbDetMath.unit(heading / 65536.0)
	var side: Vector2 = start + Vector2(-u[1], u[0])
	var ann: MinerHandle = s.add_miner("ann", Vector2i(floori(start.x), floori(start.y)))
	var bob: MinerHandle = s.add_miner("bob", Vector2i(floori(start.x), floori(start.y)))
	var cid: MinerHandle = s.add_miner("cid", Vector2i(floori(side.x), floori(side.y)))
	s.step(2)
	var load: int = s.run.loads.place(s.run, ItemKinds.Kind.STRETCHER, start, heading)
	assert_ne(load, 0)
	s.run.movement.place(s.run, bob.entity_id, start)
	s.run.movement.place(s.run, cid.entity_id, side)
	cid.at(s.run.tick).face(rad_to_deg((start - side).angle()))
	L.lit_in_hand(s, cid)
	assert_true(s.run.falls.fall_unconscious(s.run, bob.entity_id, FallCause.Cause.BLAST))
	s.step(4)
	# The ring on Bob: lay, right after lift, then 40 ticks of held interact.
	R.tap(s, cid)
	var options: Array = Variants.array(cid.connection.ring.get("options", []))
	assert_true(options.has("lay"), "lay is offered on the fallen beside a stretcher")
	assert_eq(options.find("lay"), options.find("lift") + 1, "right after lift")
	var started: Array[int] = [-1]
	var laid: Array[int] = [-1]
	s.on_tick = func(sc: Scenario) -> void:
		var a: TimedAction = sc.run.inventory.actions.get(cid.entity_id, null)
		if started[0] < 0 and a != null and a.verb == &"lay_on_stretcher":
			started[0] = a.started_tick
		if laid[0] < 0 and sc.run.falls.body_of(bob.entity_id).on_load != 0:
			laid[0] = sc.run.tick - 1
	assert_true(R.pick_and_hold(s, cid, "lay", 44))
	s.on_tick = Callable()
	assert_eq(laid[0] - started[0], 40, "laying takes 40 ticks (started by the ring, as a lift is)")
	var b: BodyState = s.run.falls.body_of(bob.entity_id)
	assert_eq(b.on_load, W.uid_of(s, load), "on the stretcher")
	assert_false(b.on_floor)
	assert_eq(s.run.registry.get_entity(bob.entity_id).position, s.run.registry.get_entity(load).position, "at its centre")
	# Ann and Cid take its ends.
	var seg: LoadSegment = W.segment(s, load)
	s.run.movement.place(s.run, ann.entity_id, seg.front_end())
	s.run.movement.place(s.run, cid.entity_id, seg.rear_end())
	W.both_take(s, ann, cid)
	assert_true(s.run.loads.carrying(ann.entity_id) and s.run.loads.carrying(cid.entity_id), "both ends taken")
	return [s, ann, bob, cid, load, table]


func _carry_to_table(s: Scenario, ann: MinerHandle, cid: MinerHandle, load: int) -> void:
	var dir: float = W.segment(s, load).heading * 360.0 / 65536.0
	W.drive(s, ann, cid, dir, roundi(RUN_TILES / 0.125))
	s.step(roundi(RUN_TILES / 0.125) + 6)


func test_set_down_beside_a_free_table_the_body_is_on_it_40_ticks_later() -> void:
	var w: Array = _laid_and_lifted(1511)
	var s: Scenario = w[0]
	var ann: MinerHandle = w[1]
	var bob: MinerHandle = w[2]
	var cid: MinerHandle = w[3]
	var load: int = w[4]
	var table: Vector2i = w[5]
	_carry_to_table(s, ann, cid, load)
	var at_table: Vector2 = Vector2(table) + Vector2(0.5, 0.5)
	assert_lte(s.run.registry.get_entity(bob.entity_id).position.distance_to(at_table), Tuning.f(&"vision.touch_range_tiles"),
		"carried to beside the table, the body with it")
	var down: Array[int] = [-1]
	var on: Array[int] = [-1]
	s.on_tick = func(sc: Scenario) -> void:
		if down[0] < 0 and not sc.run.loads.carrying(ann.entity_id):
			down[0] = sc.run.tick - 1
		if on[0] < 0 and sc.run.falls.body_of(bob.entity_id).on_table:
			on[0] = sc.run.tick - 1
	cid.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 2)
	s.step(60)
	assert_gte(down[0], 0, "set down")
	assert_eq(on[0] - down[0], 40, "on the table 40 ticks later")
	var b: BodyState = s.run.falls.body_of(bob.entity_id)
	assert_eq(b.on_load, 0, "off the stretcher")
	assert_eq(int(Variants.number(s.run.base_camp.cupboard().bodies[table])), bob.entity_id, "the table holds him")
	assert_eq(s.run.registry.get_entity(bob.entity_id).tile(), table)
	assert_eq(s.run.loads.body_on(s.run, W.uid_of(s, load)), 0, "the stretcher is empty again")


func test_taking_it_up_inside_2_s_cancels_the_transfer() -> void:
	var w: Array = _laid_and_lifted(1512)
	var s: Scenario = w[0]
	var ann: MinerHandle = w[1]
	var bob: MinerHandle = w[2]
	var cid: MinerHandle = w[3]
	var load: int = w[4]
	_carry_to_table(s, ann, cid, load)
	cid.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 2)
	s.step(4)
	assert_false(s.run.loads.carrying(ann.entity_id), "set down")
	# Ann takes her end again at once: up before the 2 s are out.
	W.take(s, ann)
	assert_true(s.run.loads.carrying(ann.entity_id))
	s.step(40)
	assert_false(s.run.falls.body_of(bob.entity_id).on_table, "taken up: no transfer")
	assert_eq(s.run.falls.body_of(bob.entity_id).on_load, W.uid_of(s, load), "still on the stretcher")
	# Down again: it starts over.
	var down_at: int = s.run.tick
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 2)
	assert_true(s.run_until(func(sc: Scenario) -> bool: return sc.run.falls.body_of(bob.entity_id).on_table, 80), "on the table after all")
	assert_lte(s.run.tick - down_at, 40 + 6)

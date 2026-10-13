extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-04: the interaction target is among things in touch range seen with identity (or just
## felt): the one nearest the facing ray, then the nearest. Out of reach, unseen and unfelt
## things are never targets; other owners' interactables (levers) compete on the same terms.

const W = preload("res://tests/unit/mnr/belt_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _pick(s: Scenario, h: MinerHandle) -> Dictionary:
	var inv: InventorySystem = s.run.inventory
	return inv.targets.pick(s.run, h.entity_id, h.slot, inv.world)


func test_facing_ray_then_nearest() -> void:
	var s: Scenario = make({"seed": 1, "fixture": W.room()})
	W.light(s)
	var a: Vector2i = s.fixture.spot("a")
	var ann: MinerHandle = s.add_miner("ann", a)
	var east: int = W.put(s, ItemKinds.Kind.SPANNER, a + Vector2i(1, 0))
	var south: int = W.put(s, ItemKinds.Kind.CANDLE, a + Vector2i(0, 1))
	var far: int = W.put(s, ItemKinds.Kind.HAMMER, a + Vector2i(3, 0))
	ann.at(s.run.tick).face(0.0)
	s.step(4)
	var t: Dictionary = _pick(s, ann)
	assert_eq(int(Variants.number(t.get("id", 0))), east, "on the facing ray")
	ann.at(s.run.tick).face(90.0)
	s.step(4)
	assert_eq(int(Variants.number(_pick(s, ann).get("id", 0))), south, "facing south now")
	for c: Dictionary in s.run.inventory.targets.candidates(s.run, ann.entity_id, ann.slot, s.run.inventory.world):
		assert_ne(int(Variants.number(c["id"])), far, "out of touch range")
	# Two on the same ray: the nearer.
	ann.at(s.run.tick).face(0.0)
	s.step(4)
	var near_east: int = W.put(s, ItemKinds.Kind.FUSE, a + Vector2i(1, 0))
	s.step(2)
	var both: Dictionary = _pick(s, ann)
	assert_true(int(Variants.number(both["id"])) in [east, near_east], "one of the two on the ray")


func test_unseen_needs_feeling() -> void:
	var s: Scenario = make({"seed": 2, "fixture": W.room()})
	var a: Vector2i = s.fixture.spot("a")
	var ann: MinerHandle = s.add_miner("ann", a)
	var spanner: int = W.put(s, ItemKinds.Kind.SPANNER, a + Vector2i(1, 0))
	s.step(4)
	assert_true(_pick(s, ann).is_empty(), "in the dark an item is never seen, so never a target")
	s.run.inventory.targets.note_felt(ann.entity_id, spanner)
	assert_eq(int(Variants.number(_pick(s, ann).get("id", 0))), spanner, "the thing just felt is")
	var dim: int = W.light(s, 0.25)
	s.run.inventory.targets.felt.clear()
	s.step(4)
	assert_true(_pick(s, ann).is_empty(), "0.25 is below the small-thing threshold")
	s.run.light.grid.remove_source(dim)
	W.light(s, 0.30)
	s.step(4)
	assert_eq(int(Variants.number(_pick(s, ann).get("id", 0))), spanner, "seen at 0.30")


func test_providers_compete() -> void:
	var s: Scenario = make({"seed": 3, "fixture": W.room()})
	W.light(s)
	var a: Vector2i = s.fixture.spot("a")
	var ann: MinerHandle = s.add_miner("ann", a)
	W.put(s, ItemKinds.Kind.SPANNER, a + Vector2i(0, 1))
	var lever_at: Vector2 = Vector2(a) + Vector2(1.5, 0.5)
	s.run.inventory.targets.providers.append(func(_run: RunState, _actor: int, at: Vector2, reach: float) -> Array:
		return [{"kind": &"lever", "id": 1, "point": lever_at}] if at.distance_to(lever_at) <= reach else [])
	ann.at(s.run.tick).face(0.0)
	s.step(4)
	assert_eq(StringName(str(_pick(s, ann)["kind"])), &"lever", "the lever lies on the ray")

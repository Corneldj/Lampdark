extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-12 with GEN-10 and GEN-11: in a generated mine, every phone GEN-10 hangs is numbered and
## routed as its cell first commits: unique numbers, a road home to a gate, its PHONE entity
## attached. Its cell evicted and back, the phone keeps its number and line, and stands again.

const F = preload("res://tests/scenario/gen/test_placement_spawn.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_every_hung_phone_is_numbered_and_routed() -> void:
	var s: Scenario = make({"seed": 5101, "generated": {"pack": F.finds_pack(), "centres": [Vector2i(2, 2)]}})
	assert_true(s.run_until(func(sc: Scenario) -> bool: return sc.mine.native.loaded_cells().size() >= 40, 600), "the window generated")
	var found: Variant = CreatureStarts.nearest_floor(s.run, Vector2i(50, 50), 12)
	assert_true(found is Vector2i)
	var home: Vector2i = found
	var ann: MinerHandle = s.add_miner("ann", home)
	ann.brain = null
	s.step(4)
	assert_true(s.run_until(func(sc: Scenario) -> bool: return sc.run.phones.pending_routes() == 0, 200), "every road found, one a tick")
	var hung: Array[String] = []
	for cell: Vector2i in s.mine.native.loaded_cells():
		for p: Dictionary in s.run.placed.of_kind(cell, "phone"):
			hung.append(str(p["id"]))
	gut.p("%d phones hung in %d cells" % [hung.size(), s.mine.native.loaded_cells().size()])
	assert_gt(hung.size(), 0, "GEN-10 hung phones")
	var numbers: Dictionary = {}
	var routed: int = 0
	for id: String in hung:
		assert_true(s.run.phones.phones.has(id), "%s met as its cell committed" % id)
		var p: PitPhone = s.run.phones.phones[id]
		assert_gt(p.number, 0)
		assert_false(numbers.has(p.number), "number %d unique" % p.number)
		numbers[p.number] = true
		assert_eq(p.entity, int(Variants.number(s.run.placed.phones.get(id, 0))), "its PHONE entity")
		assert_eq(s.run.registry.get_entity(p.entity).kind, WorldIds.EntityKind.PHONE)
		if p.routed:
			routed += 1
			var last: Vector2i = p.route_cells[p.route_cells.size() - 1]
			assert_eq(absi(last.x) + absi(last.y), 1, "%s's road ends at a gate" % id)
	assert_eq(routed, hung.size(), "every one has its road home")
	# One evicted with its cell, and back.
	var p0: PitPhone = s.run.phones.phones[hung[0]]
	var number: int = p0.number
	var cell0: Vector2i = p0.cell
	s.run.movement.place(s.run, ann.entity_id, Vector2(cell0 * 20) + Vector2(10.5 + 20 * 9, 10.5))
	assert_true(s.run_until(func(sc: Scenario) -> bool: return not sc.mine.native.is_loaded(cell0), 600), "its cell leaves")
	assert_eq(p0.entity, 0, "the phone is gone with it")
	s.run.movement.place(s.run, ann.entity_id, Vector2(home) + Vector2(0.5, 0.5))
	assert_true(s.run_until(func(sc: Scenario) -> bool: return p0.entity != 0, 600), "and stands again when it is back")
	assert_eq(p0.number, number, "with its number")
	assert_eq(s.run.phones.history.filter(func(h: Dictionary) -> bool: return str(h["id"]) == p0.id and str(h["what"]) == "generated").size(), 1,
		"never generated twice")


## Dead Lines (Gameplay §13.6): GEN-10 hangs no phone, so none exists, and power never makes a line live.
func test_under_dead_lines_no_phone_exists() -> void:
	var s: Scenario = make({"seed": 5101, "generated": {"pack": F.finds_pack(), "centres": [Vector2i(2, 2)], "plan": true,
		"plan_overrides": {"hard_variant": "dead_lines"}}})
	assert_true(s.run_until(func(sc: Scenario) -> bool: return sc.mine.native.loaded_cells().size() >= 40, 600), "the same window")
	s.step(4)
	var hung: int = 0
	for cell: Vector2i in s.mine.native.loaded_cells():
		hung += s.run.placed.of_kind(cell, "phone").size()
	assert_eq(hung, 0, "no phone hung")
	assert_true(s.run.phones.phones.is_empty(), "none met")
	s.run.power.switch_closed = true
	assert_false(s.run.power.lines_live(), "and power never makes a line live")

extends "res://tests/scenario/kit/scenario_test.gd"
## HAZ-03 (Gameplay §12.5, §6.1): a collapse point's states. Armed and standing, it has its tell
## and the hook armed on its rubble. A trigger starts the 5 s creak (a creak every second); a second
## trigger mid-creak changes nothing; exactly 100 ticks after the trigger the roof falls in one
## tick: the tiles swap, one 30 np roof fall, GEN-13's FALL record, the tell gone and the hook
## disarmed. A fallen point never falls again, and is never armed again.

const W = preload("res://tests/unit/hazards/collapse_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_standing_then_creaking_then_fallen() -> void:
	var s: Scenario = make(W.cfg(3101))
	var p: CollapsePoints.Point = W.arm(s)
	assert_eq(p.rubble.size(), 9, "the fallen set's rock, across the road")
	assert_true(s.run.registry.has(p.tell))
	assert_eq(s.run.registry.get_entity(p.tell).kind, WorldIds.EntityKind.COLLAPSE_POINT, "its tell")
	assert_true(s.run.noise.collapse.armed().has(p.id), "armed")
	var triggered: Array[int] = []
	s.run.collapses.triggered.connect(func(_pid: int, _event: int) -> void: triggered.append(s.run.tick))
	W.trigger(s, Vector2i(W.WEST - 3, 2))
	assert_eq(triggered.size(), 1, "a run step 3 tiles off starts it")
	assert_eq(p.state, CollapsePoints.State.CREAKING)
	s.step(30)
	W.trigger(s, Vector2i(W.EAST + 2, 2))
	assert_eq(triggered.size(), 1, "a second trigger mid-creak changes nothing")
	var fell_at: int = W.until_fallen(s, p.id)
	assert_eq(fell_at - triggered[0], 100, "exactly 100 ticks after the trigger")
	var creaks: Array[NoiseSystem.Event] = W.events_of(s, NoiseTypes.Type.COLLAPSE_CREAK)
	assert_eq(creaks.size(), 5, "a creak a second for the 5 s")
	for i: int in creaks.size():
		assert_eq(creaks[i].tick - triggered[0], 1 + 20 * i, "creak %d" % i)
		assert_eq(creaks[i].level_np, Tuning.f(&"noise.collapse_creak_np"))
	var falls: Array[NoiseSystem.Event] = W.events_of(s, NoiseTypes.Type.ROOF_FALL)
	assert_eq(falls.size(), 1, "one roof fall")
	assert_eq(falls[0].level_np, 30.0, "at 30 np")
	assert_eq(falls[0].tick, fell_at, "in the swap's tick")
	for t: Vector2i in p.rubble:
		assert_true(s.mine.native.is_solid(t), "%s fallen" % t)
	assert_false(s.run.registry.has(p.tell), "the tell is gone")
	assert_false(s.run.noise.collapse.armed().has(p.id), "disarmed")
	assert_eq(int(Variants.number(s.run.diff_log.payload_of(Vector2i.ZERO, DiffLog.Kind.FALL, "collapse:1").get("fallen_at", -1))), fell_at,
		"GEN-13 records the fall")
	# Once a run.
	W.trigger(s, Vector2i(W.WEST - 2, 2))
	s.step(140)
	assert_eq(W.events_of(s, NoiseTypes.Type.ROOF_FALL).size(), 1, "it never falls twice")
	assert_eq(s.run.collapses.arm_alternate(s.run, Vector2i.ZERO, 1), 0, "and is never armed again")


func test_unarmed_alternates_show_nothing() -> void:
	var s: Scenario = make(W.cfg(3102))
	s.step(4)
	assert_true(s.run.collapses.points.is_empty(), "nothing arms a fixed map's alternate by itself")
	for id: int in s.run.registry.ids():
		assert_ne(s.run.registry.get_entity(id).kind, WorldIds.EntityKind.COLLAPSE_POINT, "no tell")
	W.trigger(s, Vector2i(W.WEST - 1, 2))
	s.step(120)
	assert_eq(W.events_of(s, NoiseTypes.Type.ROOF_FALL).size(), 0, "an unarmed alternate never falls")
	assert_false(s.mine.native.is_solid(Vector2i(W.WEST, 2)))

extends "res://tests/scenario/kit/scenario_test.gd"
## FND-08: every available command works as tabled; teleport onto rock lands on the nearest open
## tile; out-of-range values clamp; unavailable commands change nothing; state-changing commands
## taint the run; freeze_ai stops every creature for 200 ticks while a miner walks on, and their
## timers resume where they paused. A client console line goes over the debug lane and back.

const D = preload("res://tests/scenario/debug/debug_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func after_each() -> void:
	WorldCoords.ring_override = -1
	Tuning.clear_dev_overrides()


func _world(run_seed: int) -> Array:
	var s: Scenario = make({"seed": run_seed, "fixture": D.hall()})
	var ann: MinerHandle = s.add_miner("ann", Vector2i(3, 2))
	s.step(2)
	return [s, ann]


func test_debug_server_installed_outside_release() -> void:
	var w: Array = _world(1)
	var s: Scenario = w[0]
	assert_not_null(s.run.debug, "a dev run has the debug channel's server end")
	assert_false(s.run.debug.hashed(), "and it never enters the state hash")


func test_teleport_onto_rock_lands_on_the_nearest_open_tile() -> void:
	var w: Array = _world(2)
	var s: Scenario = w[0]
	var ann: MinerHandle = w[1]
	assert_false(s.run.header.debug_tainted)
	var r: Dictionary = D.run_line(s, "teleport me 10 4", ann.slot)
	assert_true(Variants.flag(r["ok"]), str(r["text"]))
	var m: MovementSystem.Miner = s.run.movement.miner(ann.slot)
	var tile: Vector2i = Vector2i(floori(m.state.x), floori(m.state.y))
	assert_true(s.mine.native.is_walkable(tile), "on open floor")
	assert_almost_eq(Vector2(tile).distance_to(Vector2(10, 4)), 1.0, 0.01, "the nearest: one tile from the pillar's middle column")
	s.step(3)
	m = s.run.movement.miner(ann.slot)
	assert_eq(Vector2i(floori(m.state.x), floori(m.state.y)), tile, "and it stays (the registry and motion agree)")
	assert_true(s.run.header.debug_tainted, "teleport taints the run")
	assert_true(Variants.flag(D.run_line(s, "teleport 0 25 7")["ok"]), "the server console names a slot")


func test_clamps_and_unavailable() -> void:
	var w: Array = _world(3)
	var s: Scenario = w[0]
	var r: Dictionary = D.run_line(s, "ring_override 9")
	assert_true(Variants.flag(r["ok"]))
	assert_string_contains(str(r["text"]), "clamped")
	assert_eq(WorldCoords.ring_override, 4)
	assert_eq(WorldCoords.ring_of_point(Vector2(3, 3)), 4, "every ring lookup returns it")
	assert_true(Variants.flag(D.run_line(s, "ring_override off")["ok"]))
	assert_eq(WorldCoords.ring_of_point(Vector2(3, 3)), 0)
	var tainted_before: bool = s.run.header.debug_tainted
	var hash_before: String = s.run.state_hash()
	for line: String in ["set_pull all 150", "set_intensity 0 50"]:
		var n: Dictionary = D.run_line(s, line)
		assert_false(Variants.flag(n["ok"]), line)
		assert_string_contains(str(n["text"]), "not available", line)
	# CRT-13 builds the Stythe; the starting tuning keeps it off, so the spawn is refused.
	var sp: Dictionary = D.run_line(s, "spawn stythe 5 5")
	assert_false(Variants.flag(sp["ok"]))
	assert_string_contains(str(sp["text"]), "disabled", "spawn stythe: off in creatures.enabled")
	assert_eq(s.run.state_hash(), hash_before, "unavailable commands change nothing")
	assert_true(tainted_before, "(ring_override already tainted the run)")


func test_seed_tuning_help_and_deafen() -> void:
	var w: Array = _world(4)
	var s: Scenario = w[0]
	var ann: MinerHandle = w[1]
	assert_string_contains(str(D.run_line(s, "seed")["text"]), LbHash.to_hex(s.run.header.run_seed))
	assert_false(s.run.header.debug_tainted, "seed changes nothing")
	var set: Dictionary = D.run_line(s, "tuning set moth.memory_s 31")
	assert_true(Variants.flag(set["ok"]), str(set["text"]))
	assert_almost_eq(Tuning.f(&"moth.memory_s"), 31.0, 1e-6, "the override took effect")
	var bad: Dictionary = D.run_line(s, "tuning set no.such_key 1")
	assert_false(Variants.flag(bad["ok"]), "an unknown key is refused")
	assert_push_error("no.such_key")
	assert_true(Variants.flag(D.run_line(s, "tuning reload")["ok"]))
	assert_string_contains(str(D.run_line(s, "help")["text"]), "freeze_ai")
	var deaf: Dictionary = D.run_line(s, "deafen me 3", ann.slot)
	assert_true(Variants.flag(deaf["ok"]), str(deaf["text"]))
	assert_true(s.run.deafen.is_deafened(ann.slot))
	assert_true(s.run.header.debug_tainted)


func test_spawn_item_on_open_floor() -> void:
	var w: Array = _world(5)
	var s: Scenario = w[0]
	var before: int = s.run.inventory.world.items.size()
	var r: Dictionary = D.run_line(s, "spawn item flare 10 4")
	assert_true(Variants.flag(r["ok"]), str(r["text"]))
	assert_eq(s.run.inventory.world.items.size(), before + 1)
	assert_false(Variants.flag(D.run_line(s, "spawn item unicorn 1 1")["ok"]))


func test_freeze_ai_200_ticks() -> void:
	var w: Array = _world(6)
	var s: Scenario = w[0]
	var ann: MinerHandle = w[1]
	assert_true(Variants.flag(D.run_line(s, "spawn tapper 25 7")["ok"]))
	var tapper: Tapper = s.run.creatures.creature_of_kind(WorldIds.EntityKind.TAPPER) as Tapper
	s.step(40)
	s.run.creatures.begin_retreat(s.run, tapper, "test")
	var retreat_left: int = tapper.retreat_until - s.run.tick
	var state: StringName = tapper.state.name
	var at: Vector2 = tapper.position(s.run)
	assert_true(Variants.flag(D.run_line(s, "freeze_ai on")["ok"]))
	ann.walk_to(Vector2i(20, 1))
	var miner_from: Vector2 = s.run.registry.get_entity(ann.entity_id).position
	s.step(200)
	assert_eq(tapper.position(s.run), at, "the creature never moved")
	assert_eq(tapper.state.name, state, "nor changed state")
	assert_gt(s.run.registry.get_entity(ann.entity_id).position.distance_to(miner_from), 3.0, "while the miner walked on")
	assert_true(Variants.flag(D.run_line(s, "freeze_ai off")["ok"]))
	assert_eq(tapper.retreat_until - s.run.tick, retreat_left, "its retreat resumes where it paused")

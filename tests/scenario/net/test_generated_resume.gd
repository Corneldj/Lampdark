extends "res://tests/scenario/kit/scenario_test.gd"
## NET-09 with GEN-10, GEN-11 and GEN-13: a run generated from the shipped set, saved and resumed as
## server_main resumes one (a fresh run of the same seed, its start windows committed and their
## placements spawned, then the save applied), plays on cleanly. Every item lying in the mine has its
## entity; no phone, coat heap or trap of the fresh run is left over or doubled beside the save's; the
## items come back as the save left them.

const Specs = preload("res://tests/unit/gen/template_specs.gd")
const S = preload("res://tests/scenario/net/save_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _cfg(run_seed: int) -> Dictionary:
	return {"seed": run_seed, "generated": {"pack": Specs.shipped_pack(), "plan": true, "home_windows": true}, "saves": true}


## kind name -> {tile: count} of the entities that cells' loads make.
static func _load_made(s: Scenario) -> Dictionary:
	var out: Dictionary = {}
	for kind: WorldIds.EntityKind in [WorldIds.EntityKind.PHONE, WorldIds.EntityKind.COAT_HEAP, WorldIds.EntityKind.TRAP]:
		var tiles: Dictionary = {}
		for id: int in s.run.registry.ids():
			var e: SimEntity = s.run.registry.get_entity(id)
			if e.kind == kind:
				tiles[e.tile()] = Variants.whole(tiles.get(e.tile(), 0)) + 1
		out[WorldIds.EntityKind.find_key(kind)] = tiles
	return out


## placement id -> [kind, tile, oil] of every placed item lying in the mine.
static func _placed_lying(s: Scenario) -> Dictionary:
	var out: Dictionary = {}
	for raw: Variant in s.run.inventory.world.items.keys():
		var it: Item = s.run.inventory.world.items[raw]
		if it.placement.is_empty():
			continue
		var e: SimEntity = s.run.registry.get_entity(Variants.whole(raw))
		out[it.placement] = [it.kind, e.tile() if e != null else Vector2i(-99999, -99999), it.state.get("oil", -1.0)]
	return out


func test_a_resumed_generated_run_plays_on_cleanly() -> void:
	S.clear(4801)
	var s: Scenario = make(_cfg(4801))
	var ann: MinerHandle = s.add_miner("ann", Vector2i(10, 10))
	ann.brain = null
	s.step(5)
	var before_made: Dictionary = _load_made(s)
	var before_lying: Dictionary = _placed_lying(s)
	assert_gt(before_lying.size(), 0, "the windows hold placed items")
	assert_false(s.run.saves.snapshot(s.run).is_empty(), "saved")
	var path: String = S.snapshot_path(s)
	S.kill(s)
	var opened: Dictionary = SaveResume.open_file(path)
	assert_true(Variants.flag(opened["ok"]), str(opened["message"]))
	var b: Scenario = make(_cfg(4801))
	SaveResume.apply(b.run, b.net, opened)
	b.rejoin("ann")
	b.step(20)
	for raw: Variant in b.run.inventory.world.items.keys():
		assert_true(b.run.registry.has(Variants.whole(raw)), "every lying item has its entity")
	assert_eq(_load_made(b), before_made, "phones, coat heaps and traps as they were, none doubled")
	assert_eq(_placed_lying(b), before_lying, "every placed item where it lay, as it was")

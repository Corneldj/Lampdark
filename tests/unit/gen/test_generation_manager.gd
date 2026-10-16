extends "res://tests/scenario/kit/scenario_test.gd"
## GEN-11's generation manager in synchronous mode (the kit's): run start commits base camp and
## the window round it before the first tick; every cell within 4 of a holder is loaded each tick;
## cells beyond 6 of every holder go, base camp and its gate cells never; and a worker pool gives
## the very cells the synchronous mode does.

const Specs = preload("res://tests/unit/gen/template_specs.gd")

static var _pack: PackedByteArray = PackedByteArray()


func before_all() -> void:
	assert_true(Tuning.load_server())
	_pack = Specs.road_pack()


func test_run_start_commits_base_camp_and_its_window() -> void:
	var s: Scenario = make({"seed": 4101, "generated": {"pack": _pack}})
	assert_not_null(s.generation)
	var loaded: Array = s.mine.native.loaded_cells()
	assert_eq(loaded.size(), 81, "base camp's 9x9 window, before the first tick")
	assert_true(s.mine.native.is_loaded(Vector2i.ZERO))
	var deck: Rect2i = Basecamp.deck_rect(s.run.header.run_seed)
	assert_true(s.mine.native.is_walkable(deck.position), "base camp is GEN-02's, deck and all")
	assert_eq(s.generation.failures, 0, "every cell had a template")
	for cell: Vector2i in MineLayouts.gate_cells(s.run.header.run_seed):
		assert_true(s.generation.pinned.has(cell), "the gate cells are pinned")


func test_the_window_follows_a_miner_and_cells_behind_go() -> void:
	var s: Scenario = make({"seed": 4102, "generated": {"pack": _pack}})
	var ann: MinerHandle = s.add_miner("ann", Basecamp.deck_rect(s.run.header.run_seed).position)
	ann.brain = null
	s.step(2)
	# Off east along the main road, 12 cells out.
	var far: Vector2i = Vector2i(12, 0)
	s.run.movement.place(s.run, ann.entity_id, Vector2(far * 20) + Vector2(1.5, 10.5))
	s.step(3)
	for y: int in range(far.y - 4, far.y + 5):
		for x: int in range(far.x - 4, far.x + 5):
			assert_true(s.mine.native.is_loaded(Vector2i(x, y)), "cell (%d, %d) within 4 of her is loaded" % [x, y])
	assert_true(s.mine.native.is_loaded(Vector2i.ZERO), "base camp stays")
	for cell: Vector2i in MineLayouts.gate_cells(s.run.header.run_seed):
		assert_true(s.mine.native.is_loaded(cell), "the gate cells stay")
	assert_false(s.mine.native.is_loaded(Vector2i(-3, 3)), "a cell 15 from her went")
	assert_false(s.mine.native.is_loaded(Vector2i(3, -4)), "and another")
	for raw: Variant in s.mine.native.loaded_cells():
		var c: Vector2i = raw
		var d: int = maxi(absi(c.x - far.x), absi(c.y - far.y))
		assert_true(d <= 6 or s.generation.pinned.has(c), "nothing beyond 6 but the pinned cells (%s)" % c)
	assert_gt(s.generation.evicted, 60)
	assert_eq(s.generation.missing_sight_ticks, 0)


func test_a_worker_pool_derives_the_cells_the_synchronous_mode_does() -> void:
	var digests: Array[Dictionary] = []
	for workers: int in [0, 2]:
		var mine: Mine = Mine.new()
		var layouts: LbLayouts = LbLayouts.new()
		assert_true(layouts.load_pack(_pack))
		MineLayouts.configure(layouts, 909)
		var g: Generation = Generation.new(mine, layouts, 909, workers == 0, maxi(workers, 1))
		var out: Dictionary = {}
		for y: int in range(-6, 7):
			for x: int in range(-6, 7):
				layouts.want(Vector2i(x, y), absi(x) + absi(y))
		var until: int = Time.get_ticks_msec() + 20000
		while out.size() < 169 and Time.get_ticks_msec() < until:
			for raw: Variant in layouts.take(64):
				var r: Dictionary = Variants.dict(raw)
				out[r["at"]] = r["digest"]
		assert_eq(out.size(), 169)
		digests.append(out)
		layouts.stop_pool()
		assert_not_null(g)
	assert_eq(digests[0], digests[1], "the same layouts, whatever the threads")

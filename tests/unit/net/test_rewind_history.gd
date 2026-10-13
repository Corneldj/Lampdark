extends GutTest
## NET-06's rewind: positions min(T - S, 150 ms) back, interpolated between frames; range checks
## move only the target; a shot is traced against bodies as the shooter saw them.

var run: RunState
var rw: Rewind
var actor: SimEntity
var walker: SimEntity


func before_all() -> void:
	assert_true(Tuning.load_server())


func before_each() -> void:
	run = RunState.new()
	rw = Rewind.new()
	rw.bind(run)
	actor = run.registry.create(WorldIds.EntityKind.MINER, Vector2(0.0, 0.0))
	walker = run.registry.create(WorldIds.EntityKind.MINER, Vector2(0.0, 0.0))
	# A teammate walking east at 3.0 tiles/s (0.15 a tick); ticks 0-19 recorded, now tick 20.
	for t: int in 20:
		run.tick = t
		run.registry.move(walker.id, Vector2(0.15 * t, 0.0))
		rw.tick(run)
	run.tick = 20
	run.registry.move(walker.id, Vector2(3.0, 0.0))


func test_rewind_cap() -> void:
	assert_almost_eq(rw.rewind_time(18.0), 18.0, 1e-9, "T - S = 2 ticks: back exactly 2")
	assert_almost_eq(rw.position_of(walker.id, rw.rewind_time(18.0)).x, 2.7, 1e-6, "where frame 18 showed it")
	assert_almost_eq(rw.rewind_time(10.0), 17.0, 1e-9, "T - S = 10 ticks: capped at 150 ms, 3 ticks")
	assert_almost_eq(rw.position_of(walker.id, rw.rewind_time(10.0)).x, 2.55, 1e-6)
	assert_almost_eq(rw.position_of(walker.id, rw.rewind_time(18.5)).x, 2.775, 1e-6, "between frames: interpolated")
	assert_almost_eq(rw.position_of(walker.id, rw.rewind_time(25.0)).x, 3.0, 1e-6, "never ahead of now")
	assert_almost_eq(rw.position_of(walker.id, 19.5).x, 2.925, 1e-6, "between the last frame and now")


func test_range_checks_rewind_only_the_target() -> void:
	run.registry.move(actor.id, Vector2(2.75, 0.5))
	assert_true(rw.in_range_at(actor.id, walker.id, 0.52, 18.0), "in range as the presser saw it (2.7)")
	assert_false(rw.in_range_at(actor.id, walker.id, 0.52, 20.0), "not where it is now (3.0)")
	assert_false(rw.in_range_at(actor.id, walker.id, 0.52, 10.0), "a stamp older than 150 ms counts as 150 ms (2.55)")
	run.registry.move(actor.id, Vector2(9.0, 0.0))
	assert_false(rw.in_range_at(actor.id, walker.id, 0.52, 18.0), "the actor is where it is now, never rewound")


func test_history_depth() -> void:
	assert_eq(rw.history.size(), Tuning.i(&"net.rewind_history_ticks"))
	assert_false(rw.history.has(9))
	assert_true(rw.history.has(19))


func test_a_shot_hits_the_first_body_as_the_shooter_saw_it() -> void:
	# The line x = 2.6 passes 0.1 from the teammate as the shooter saw it (2.7), 0.4 from it now.
	var shooter: SimEntity = run.registry.create(WorldIds.EntityKind.MINER, Vector2(2.6, -4.0))
	var bystander: SimEntity = run.registry.create(WorldIds.EntityKind.MINER, Vector2(2.6, 3.0))
	var hit: Dictionary = rw.trace_bodies(shooter.position, Vector2(0.0, 1.0), 20.0, 18.0, shooter.id)
	assert_eq(int(Variants.number(hit.get("entity", 0))), walker.id, "the teammate where the shooter saw it: a friendly hit")
	assert_almost_eq(Variants.number(hit["distance"]), 4.0 - sqrt(0.35 * 0.35 - 0.01), 1e-6)
	hit = rw.trace_bodies(shooter.position, Vector2(0.0, 1.0), 20.0, 20.0, shooter.id)
	assert_eq(int(Variants.number(hit.get("entity", 0))), bystander.id, "now the teammate has walked on: the next body is hit")
	hit = rw.trace_bodies(shooter.position, Vector2(0.0, 1.0), 6.0, 20.0, shooter.id)
	assert_true(hit.is_empty(), "nothing within range")
	hit = rw.trace_bodies(shooter.position, Vector2(0.0, 1.0), 20.0, 18.0)
	assert_eq(int(Variants.number(hit.get("entity", 0))), shooter.id, "without excluding the shooter it starts inside itself")


func test_items_are_not_bodies() -> void:
	run.registry.create(WorldIds.EntityKind.ITEM, Vector2(8.0, 0.0))
	var hit: Dictionary = rw.trace_bodies(Vector2(5.0, 0.0), Vector2(1.0, 0.0), 20.0, 20.0)
	assert_true(hit.is_empty(), "an item on the line is no body")


func test_state_round_trip() -> void:
	var w: SimStateWriter = SimStateWriter.new()
	rw.write_state(w)
	var other: Rewind = Rewind.new()
	other.read_state(SimStateReader.new(w.bytes()))
	assert_eq(other.history.size(), rw.history.size())
	var h18: Dictionary = other.history[18]
	var at: Vector2 = h18[walker.id]
	assert_eq(at, Vector2(2.7, 0.0))


func test_shots_never_use_the_defender_rule() -> void:
	var source: String = FileAccess.get_file_as_string("res://server/net/rewind.gd")
	assert_false(source.contains("DefenderRule") or source.contains(".defender"), "a shot has no wind-up: the trace never asks the defender rule")

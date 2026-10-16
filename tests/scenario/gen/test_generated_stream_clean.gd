extends "res://tests/scenario/kit/scenario_test.gd"
## GEN-11 with NET-08: a generated run streams nothing of its generation (Gameplay §5.10: darkness
## is missing data). Two miners go out of base camp along the east main road, each with a light
## that goes with them, while the cells round them generate, commit and drop behind; NET-08's
## audit judges every frame, so geometry and tiles reach a client only where seen and no record
## tells it a cell appeared or went.

const StreamAudit = preload("res://tools/stream_audit/stream_audit.gd")
const Specs = preload("res://tests/unit/gen/template_specs.gd")
const W = preload("res://tests/scenario/net/net04_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_a_generated_run_streams_only_what_is_seen() -> void:
	var s: Scenario = make({"seed": 4120, "generated": {"pack": Specs.road_pack()}})
	var audit: StreamAudit = StreamAudit.new()
	audit.attach(s.run, s.net)
	var deck: Vector2i = Basecamp.deck_rect(s.run.header.run_seed).position
	var ann: MinerHandle = s.add_miner("ann", deck)
	var ben: MinerHandle = s.add_miner("ben", deck + Vector2i(1, 0))
	ann.brain = null
	ben.brain = null
	s.step(5)
	var committed: int = s.generation.commits
	# Along the east main road (tile row 10 of the cells on row 0), ben a few tiles behind ann.
	var stride: float = Tuning.f(&"movement.run_speed") / Tuning.f(&"net.tick_hz")
	var x: float = 21.5
	var light_a: int = W.lamp(s, Vector2(x, 10.5))
	var light_b: int = W.lamp(s, Vector2(x, 10.5))
	while x < 12.0 * 20.0:
		var at_b: Vector2 = Vector2(maxf(21.5, x - 4.0), 10.5)
		s.run.movement.place(s.run, ann.entity_id, Vector2(x, 10.5))
		s.run.movement.place(s.run, ben.entity_id, at_b)
		s.run.light.grid.update_point(light_a, Vector2(x, 10.5), 5.5, 1.0)
		s.run.light.grid.update_point(light_b, at_b, 5.5, 1.0)
		s.step(1)
		x += stride
	var r: Dictionary = audit.report()
	gut.p("judged: %s; cells committed on the way %d, dropped %d" % [r["checked"], s.generation.commits - committed,
		s.generation.evicted])
	for v: Dictionary in audit.violations.slice(0, 12):
		gut.p("VIOLATION %s" % v)
	assert_gt(s.generation.commits - committed, 40, "cells generated round them on the way")
	assert_gt(s.generation.evicted, 20, "and dropped behind them")
	assert_eq(s.generation.missing_sight_ticks, 0)
	assert_eq(audit.violation_count, 0, "nothing unseen, nothing of the generation, reached a client")
	var checked: Dictionary = r["checked"]
	for rule: String in ["frame", "tile", "geometry"]:
		assert_gt(int(Variants.number(checked.get(rule, 0))), 0, "%s records were judged" % rule)

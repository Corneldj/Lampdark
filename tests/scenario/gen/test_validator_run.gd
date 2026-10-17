extends "res://tests/scenario/kit/scenario_test.gd"
## GEN-12 in a generated run: the plan's spines were walked at run start and base camp's gates
## checked; every committed cell is its final layout, its placements those phase 2 passed; the
## validator's counts by rule, biome and template are kept in the run's generation stats; and NET-08's
## audit, which decodes every message sent and fails any type it does not know, finds none of it on
## the wire: no verdict, count, socket or layout reaches a client.

const StreamAudit = preload("res://tools/stream_audit/stream_audit.gd")
const Placement = preload("res://tests/scenario/gen/test_placement_spawn.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _base_camp_floor(s: Scenario) -> Vector2i:
	for r: int in 10:
		for dy: int in range(-r, r + 1):
			for dx: int in range(-r, r + 1):
				var t: Vector2i = Vector2i(10 + dx, 10 + dy)
				if s.mine.native.is_walkable(t):
					return t
	return Vector2i(10, 10)


func test_a_generated_runs_validator_keeps_to_the_server() -> void:
	var s: Scenario = make({"seed": 4231, "generated": {"pack": Placement.finds_pack(), "plan": true}})
	var audit: StreamAudit = StreamAudit.new()
	audit.attach(s.run, s.net)
	var ann: MinerHandle = s.add_miner("ann", _base_camp_floor(s))
	ann.brain = null
	s.step(4)
	# Every committed cell is its final layout, each with the placements phase 2 passed.
	var layouts: LbLayouts = s.generation.layouts
	for cell: Vector2i in s.mine.native.loaded_cells():
		if cell == Vector2i.ZERO:
			continue
		var final: Dictionary = layouts.derive_final(cell)
		assert_true(Variants.flag(final["ok"]), "%s derived" % cell)
		var report: Dictionary = layouts.placement_report(cell)
		assert_eq(Variants.array(report["failures"]).size(), 0, "%s: %s" % [cell, str(report["failures"])])
	# Out along a road, so more cells generate and commit through the validator.
	s.run.movement.place(s.run, ann.entity_id, Vector2(Vector2i(6, 0) * 20) + Vector2(1.5, 10.5))
	s.step(6)
	var stats: Dictionary = Variants.dict(s.generation.stats()["validator"])
	assert_gt(int(Variants.number(stats.get("cells", 0))), 40, "cells validated")
	assert_gt(int(Variants.number(stats.get("placed", 0))), 20, "placements validated")
	assert_eq(int(Variants.number(stats.get("shipped_invalid", 0))), 0)
	assert_eq(int(Variants.number(stats.get("no_layout", 0))), 0)
	assert_gt(int(Variants.number(stats.get("spines", 0))), 0, "the plan's spines walked at run start")
	assert_eq(int(Variants.number(stats.get("spines_unreached", 0))), 0)
	# NET-08: nothing of it on the wire.
	for v: Dictionary in audit.violations.slice(0, 6):
		gut.p("VIOLATION %s" % v)
	assert_eq(audit.violation_count, 0, "NET-08: no validator data, nothing unseen")
	assert_gt(audit.checked.size(), 0, "messages judged")
	assert_false(audit.checked.has("registry"), "no message of a type the audit does not know: %s" % str(audit.checked))

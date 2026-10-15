extends "res://tests/scenario/kit/scenario_test.gd"
## VIS-10, under NET-08's audit: with the Stythe's tell playing, every floor tile of its 3x3 block lit
## below 0.30 leaves Ann's seen set and margin with the Stythe on it; tiles at 0.30 or more stay;
## the bite moves with it; the Thin bites below 0.50. With its tell off it is a plain miner-sized
## token in the fringe. bite_seen_by is true exactly while a bitten tile would have been seen.

const StreamAudit = preload("res://tools/stream_audit/stream_audit.gd")
const W = preload("res://tests/scenario/vis/bite_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_the_bite_moves_with_the_stythe() -> void:
	var s: Scenario = make({"seed": 1001, "fixture": W.road()})
	var audit: StreamAudit = StreamAudit.new()
	audit.attach(s.run, s.net)
	var w: W = W.new()
	w.build(s)
	var t: Vector2i = w.fringe_tile()
	assert_ne(t, Vector2i(-1, -1), "a fringe tile in her pool")
	w.put_stythe(t)
	s.step(2)
	assert_eq(w.token_count(), 1, "tell off: a plain token in the fringe")
	assert_false(s.run.vision.bite_seen_by(w.ann.entity_id))
	w.active = true
	s.step(2)
	var bite: Array[Vector2i] = s.run.vision.bite_now
	gut.p("stythe at %s; bite %s" % [t, bite])
	assert_gt(bite.size(), 0)
	var seen: Dictionary = w.frame_tiles()
	var margin: Dictionary = w.margin_tiles()
	for b: Vector2i in bite:
		assert_lt(s.run.light.light_at(b), 0.30, "bitten tiles are below 0.30")
		assert_false(seen.has(b), "%s left her seen set" % b)
		assert_false(margin.has(b), "and her margin")
	for dy: int in range(-1, 2):
		for dx: int in range(-1, 2):
			var n: Vector2i = t + Vector2i(dx, dy)
			if s.run.light.light_at(n) >= 0.30:
				assert_false(bite.has(n), "%s at 0.30 or more stays" % n)
	assert_eq(w.token_count(), 0, "the Stythe went with its tiles")
	assert_true(s.run.vision.bite_seen_by(w.ann.entity_id), "she would have seen bitten tiles")
	# It moves one tile west: the bite moves with it.
	w.put_stythe(t + Vector2i(-1, 0))
	s.step(2)
	assert_true(s.run.vision.bite_now.has(t + Vector2i(-2, 0)) or s.run.light.light_at(t + Vector2i(-2, 0)) >= 0.30,
		"the block follows it west")
	assert_false(s.run.vision.bite_now.has(t + Vector2i(1, 0)), "and leaves the tile it left behind")
	# The Thin bites deeper into the pool.
	var normal: int = s.run.vision.bite_now.size()
	w.thin = true
	s.step(2)
	assert_gte(s.run.vision.bite_now.size(), normal, "the Thin takes tiles below 0.50")
	for b: Vector2i in s.run.vision.bite_now:
		assert_lt(s.run.light.light_at(b), 0.50)
	w.active = false
	s.step(2)
	assert_eq(s.run.vision.bite_now.size(), 0, "tell off: no bite")
	for v: Dictionary in audit.violations.slice(0, 8):
		gut.p("VIOLATION %s" % v)
	assert_eq(audit.violation_count, 0, "no stream record names or leaks a bite")

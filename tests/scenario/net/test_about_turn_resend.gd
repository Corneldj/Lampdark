extends "res://tests/scenario/kit/scenario_test.gd"
## NET-04: an about-turn skips geometry the client already holds and resends geometry that
## changed while unseen (a gate shut behind its back).

const N = preload("res://tests/scenario/net/net04_world.gd")
const ROWS: PackedStringArray = [
	"######################",
	"#.........a....G.....#",
	"######################",
]


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_about_turn() -> void:
	var s: Scenario = make({"seed": 49, "fixture": FixtureMap.from_ascii(ROWS)})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	N.lamp(s, Vector2(10.5, 1.5), 5.5, ann.entity_id)
	s.set_gate(1, true)
	var sent: Array[int] = [0]
	s.on_tick = func(sc: Scenario) -> void:
		sent[0] += int(Variants.number(sc.run.replication.native.last_stats(ann.slot).get("geometry_sent", 0)))
	# Each phase is 16 ticks: an about-turn takes 10 at the capped rate (NET-12), then a frame's trip.
	# 179°, not 180°: turns sweep through the same side both ways, so the walls they pass are held too.
	ann.at(0).face(0.0)
	s.step(16)
	var east: int = sent[0]
	sent[0] = 0
	ann.at(s.run.tick).face(179.0)
	s.step(16)
	var west: int = sent[0]
	var gate: Vector2i = Vector2i(15, 1)
	var held: PackedByteArray = s.client(ann).records_at(s.run.tick).geometry[gate]
	sent[0] = 0
	ann.at(s.run.tick).face(0.0)
	s.step(16)
	assert_eq(sent[0], 0, "turning back: everything east is already held, none resent")
	sent[0] = 0
	ann.at(s.run.tick).face(179.0)
	s.step(16)
	s.set_gate(1, false)  # shut while unseen
	sent[0] = 0
	ann.at(s.run.tick).face(0.0)
	s.step(16)
	assert_eq(sent[0], 1, "only the changed gate is resent")
	var now: PackedByteArray = s.client(ann).records_at(s.run.tick).geometry[gate]
	assert_ne(now, held, "the client has the gate's new state")
	gut.p("geometry sent: east %d, west %d" % [east, west])
	assert_gt(east, 5)
	assert_gt(west, 5)

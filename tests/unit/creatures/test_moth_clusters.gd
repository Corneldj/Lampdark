extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-04: the awake Moth sees lit tiles (0.30 or more) only in line of sight and within its ring's
## sight; a flare at 50 tiles and a lamp signal at 40; never through rock, a shut gate or a closed
## air door. It targets the cluster with the highest summed light and switches within one rescan
## when a brighter cluster appears.

const A = preload("res://tests/scenario/creatures/moth_awake_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


## Scans from a fixed tile (the Moth itself may move between steps as it hunts).
func _scan(s: Scenario, m: Moth, from: Vector2i = Vector2i(5, 2)) -> MothPerception:
	m.awake.perception.scan(s.run, from, CreatureTables.moth_sight_tiles(0))
	return m.awake.perception


func test_sight_range_and_walls() -> void:
	var rows: PackedStringArray = A.road(70).rows
	var r: String = rows[2]
	rows[2] = r.substr(0, 42) + "G" + r.substr(43)
	var s: Scenario = make({"seed": 1, "fixture": FixtureMap.from_ascii(rows)})
	var m: Moth = A.awake(s, Vector2i(5, 2), false)
	assert_eq(CreatureTables.moth_sight_tiles(m.ring(s.run)), 20.0, "ring 0: 20 tiles")
	var grid: LbLightGrid = s.run.light.grid
	grid.add_spot(0, Vector2i(24, 2), 0.5, 0)
	grid.add_spot(0, Vector2i(26, 2), 0.5, 0)
	grid.add_spot(0, Vector2i(10, 2), 0.29, 0)
	s.step(2)
	var p: MothPerception = _scan(s, m)
	assert_true(p.seen.has(Vector2i(24, 2)), "19 tiles: seen")
	assert_false(p.seen.has(Vector2i(26, 2)), "21 tiles: beyond its sight")
	assert_false(p.seen.has(Vector2i(10, 2)), "0.29: not lit enough")
	# Beacons: a flare at 45 tiles, a lamp signal at 38 but not at 42; a shut gate between hides.
	var flare: int = grid.add_spot(0, Vector2i(50, 2), 0.9, 0)
	m.awake.perception.beacons[1] = {"kind": &"flare", "source": flare, "until": s.run.tick + 400}
	s.step(2)
	assert_false(_scan(s, m).seen.has(Vector2i(50, 2)), "the shut gate at x = 42 blocks the flare")
	s.set_gate(1, true)
	s.step(2)
	assert_true(_scan(s, m).seen.has(Vector2i(50, 2)), "a flare is seen at 45 tiles")
	var near_signal: int = grid.add_spot(0, Vector2i(43, 2), 0.9, 0)
	var far_signal: int = grid.add_spot(0, Vector2i(47, 2), 0.9, 0)
	m.awake.perception.beacons[2] = {"kind": &"signal", "source": near_signal, "until": s.run.tick + 400}
	m.awake.perception.beacons[3] = {"kind": &"signal", "source": far_signal, "until": s.run.tick + 400}
	s.step(2)
	p = _scan(s, m)
	assert_true(p.seen.has(Vector2i(43, 2)), "a signal at 38 tiles")
	assert_false(p.seen.has(Vector2i(47, 2)), "not at 42")


func test_rock_and_air_doors_block() -> void:
	var rows: PackedStringArray = A.road(40).rows
	var r: String = rows[2]
	rows[2] = r.substr(0, 12) + "D" + r.substr(13)
	var s: Scenario = make({"seed": 2, "fixture": FixtureMap.from_ascii(rows)})
	var m: Moth = A.awake(s, Vector2i(5, 2), false)
	s.run.light.grid.add_spot(0, Vector2i(15, 2), 0.8, 0)
	s.step(2)
	assert_false(_scan(s, m).seen.has(Vector2i(15, 2)), "a closed air door blocks it")
	s.set_gate(1, true)
	s.step(2)
	assert_true(_scan(s, m).seen.has(Vector2i(15, 2)), "open, it sees through")
	var hall: Scenario = make({"seed": 3, "fixture": A.hall(30, 9)})
	var m2: Moth = A.awake(hall, Vector2i(3, 5), false)
	hall.run.light.grid.add_spot(0, Vector2i(20, 5), 0.8, 0)
	hall.step(2)
	assert_true(_scan(hall, m2, Vector2i(3, 5)).seen.has(Vector2i(20, 5)), "in sight in the open")


func test_brightest_summed_cluster_and_switch() -> void:
	var s: Scenario = make({"seed": 4, "fixture": A.hall(40, 20)})
	var m: Moth = A.awake(s, Vector2i(20, 10), false)
	var grid: LbLightGrid = s.run.light.grid
	# A small bright spot against a wide dimmer pool: the summed light decides.
	grid.add_spot(0, Vector2i(10, 10), 1.0, 0)
	grid.add_point("gauze_lamp", LbLightGrid.COLOUR_AMBER, 0, LbLightGrid.FLAG_FLAME | LbLightGrid.FLAG_UNHELD, 4.0, 1.0, Vector2(30.5, 10.5), 0)
	s.step(2)
	var p: MothPerception = _scan(s, m, Vector2i(20, 10))
	assert_eq(p.clusters.size(), 2)
	assert_gt(p.clusters[0].score, p.clusters[1].score)
	assert_eq(p.clusters[0].kind, "gauze_lamp", "the wider pool sums higher than the single bright tile")
	assert_true(p.clusters[0].unheld())
	assert_eq(p.clusters[1].tiles.size(), 1)
	# Hunting the lamp; a brighter light appears: the switch comes within one rescan.
	m.enter(s.run, &"prowl", "test")
	s.step(2)
	assert_eq(m.state.name, &"hunt")
	var big: int = grid.add_point("gauze_lamp", LbLightGrid.COLOUR_AMBER, 0, LbLightGrid.FLAG_FLAME | LbLightGrid.FLAG_UNHELD, 5.5, 1.0, Vector2(12.5, 4.5), 0)
	s.step(1)
	var rescan: int = roundi(Tuning.f(&"net.tick_hz") / Tuning.f(&"moth.rescan_hz"))
	var switched: int = -1
	for i: int in rescan + 1:
		if int(Variants.number(m.awake.target.get("source", 0))) == big:
			switched = i
			break
		s.step(1)
	assert_between(switched, 0, rescan, "switched within one rescan (%d ticks)" % rescan)


func test_never_a_miner_outside_a_frenzy() -> void:
	var s: Scenario = make({"seed": 5, "fixture": A.hall(40, 20)})
	var m: Moth = A.awake(s, Vector2i(5, 10), false)
	var bob: MinerHandle = s.add_miner("bob", Vector2i(20, 10))
	s.run.light.grid.add_area("emergency", LbLightGrid.COLOUR_WHITE, 0, 0.6, [Vector2i(19, 9), Vector2i(20, 9), Vector2i(21, 9),
		Vector2i(19, 10), Vector2i(20, 10), Vector2i(21, 10)])
	s.step(3)
	var t: Dictionary = m.awake.best_target(s.run, m, false)
	assert_eq(str(t["kind"]), "cover", "prowling, it targets the light, never bob standing in it")
	assert_eq(int(Variants.number(t["miner"])), 0)
	var f: Dictionary = m.awake.best_target(s.run, m, true)
	assert_eq(str(f["kind"]), "lit_miner", "in a frenzy, the lit miner")
	assert_eq(int(Variants.number(f["miner"])), bob.entity_id)

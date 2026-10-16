extends "res://tests/scenario/kit/scenario_test.gd"
## DIR-03's rates (Gameplay §10.5): for every ring and group size, one scripted minute changes the
## Pull by exactly the tabled amount (±0.01). Alone +6 × D, a pair +2 × D, three or more −4; solo or
## a lone human always alone, every rate × 0.5.

const D = preload("res://tests/scenario/director/draught_world.gd")

## Ring 0-4: alone, a pair, three or more, solo.
const TABLE: Array = [[3.0, 1.0, -4.0, 1.5], [6.0, 2.0, -4.0, 3.0], [9.0, 3.0, -4.0, 4.5], [12.0, 4.0, -4.0, 6.0],
	[15.0, 5.0, -4.0, 7.5]]


func before_all() -> void:
	assert_true(Tuning.load_server())


## One alone (x 1), a pair (x 20-21) and a group of three (x 37-39) along the hall, every Pull at 50,
## a minute at `ring`; the change for [alone, pair, group].
func _minute(ring: int, seed_value: int) -> Array[float]:
	var s: Scenario = make({"seed": seed_value, "fixture": D.hall(), "director": true, "slots": 8})
	var spots: Array[Vector2i] = [Vector2i(1, 1), Vector2i(20, 1), Vector2i(21, 1), Vector2i(37, 1), Vector2i(38, 1), Vector2i(39, 1)]
	var ids: Array[int] = []
	for i: int in spots.size():
		ids.append(s.add_miner("m%d" % i, spots[i]).entity_id)
	D.stand_in(s)
	s.run.pull.ring_of = func(_m: int) -> int: return ring
	s.step(2)
	for e: int in ids:
		assert_true(s.run.pull.set_value(e, 50.0))
	var start: Array[float] = []
	for e: int in ids:
		start.append(s.run.pull.value_of(e))
	s.step(roundi(60.0 * Tuning.f(&"net.tick_hz")))
	return [s.run.pull.value_of(ids[0]) - start[0], s.run.pull.value_of(ids[1]) - start[1], s.run.pull.value_of(ids[3]) - start[3]]


func test_every_ring_and_group_size() -> void:
	for ring: int in 5:
		var got: Array[float] = _minute(ring, 2000 + ring)
		var want: Array = TABLE[ring]
		assert_almost_eq(got[0], float(Variants.number(want[0])), 0.01, "ring %d alone" % ring)
		assert_almost_eq(got[1], float(Variants.number(want[1])), 0.01, "ring %d a pair" % ring)
		assert_almost_eq(got[2], float(Variants.number(want[2])), 0.01, "ring %d three or more" % ring)


func test_solo_is_always_alone_at_half() -> void:
	for ring: int in 5:
		var s: Scenario = make({"seed": 2010 + ring, "fixture": D.hall(), "director": true})
		var ann: MinerHandle = s.add_miner("ann", Vector2i(1, 1))
		D.stand_in(s)
		s.run.crew.lobby = CrewCensus.Lobby.SOLO
		s.run.pull.ring_of = func(_m: int) -> int: return ring
		s.step(2)
		assert_true(s.run.pull.set_value(ann.entity_id, 50.0))
		var from: float = s.run.pull.value_of(ann.entity_id)
		s.step(roundi(60.0 * Tuning.f(&"net.tick_hz")))
		var want: Array = TABLE[ring]
		assert_almost_eq(s.run.pull.value_of(ann.entity_id) - from, float(Variants.number(want[3])), 0.01, "solo, ring %d" % ring)

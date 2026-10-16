extends "res://tests/scenario/kit/scenario_test.gd"
## DIR-03: Gameplay §10.11's Pull, from 44:00. Ada and Harry go out together from the pit-bottom
## roads (ring 0) to the First Level (1) and the Second (2), then split at 50:00: Ada starts home
## through the First Level and the pit-bottom roads, Harry goes in-bye alone on the Second Level.
## Ellis, Wilf and Nell sit in base camp behind shut gates, and at 54:00 the gate shuts behind Ada.
## At 55:00 the Tapper's hunt on Harry ends (a stub event): the ebb. Rings are scripted per miner on
## the minute; groups are where they stand (together, 1 tile apart; apart, a hall's length).
## Groups are worked out at 4 Hz, so a split can lag a quarter of a second (±0.05 Pull).

const D = preload("res://tests/scenario/director/draught_world.gd")

var _base: int = 0
var _hz: int = 20


func before_all() -> void:
	assert_true(Tuning.load_server())


## The tick at run time mm:ss (the test starts at 44:00).
func _at(mm: int, ss: int) -> int:
	return _base + ((mm - 44) * 60 + ss) * _hz


func test_the_pull_column() -> void:
	var s: Scenario = make({"seed": 1012, "fixture": D.hall(), "director": true, "slots": 8})
	_hz = roundi(Tuning.f(&"net.tick_hz"))
	var ids: Array[int] = []
	for spot: Array in [["ada", Vector2i(10, 1)], ["harry", Vector2i(11, 1)], ["ellis", Vector2i(26, 3)],
			["wilf", Vector2i(27, 3)], ["nell", Vector2i(28, 3)]]:
		var at: Vector2i = spot[1]
		ids.append(s.add_miner(str(spot[0]), at).entity_id)
	var ada: int = ids[0]
	var harry: int = ids[1]
	var home: Dictionary = {ids[2]: true, ids[3]: true, ids[4]: true}
	var rings: Dictionary = {ada: 0, harry: 0}
	D.stand_in(s)
	s.run.crew.is_sealed_inside = func(e: int) -> bool: return home.has(e)
	s.run.pull.ring_of = func(m: int) -> int: return int(Variants.number(rings.get(m, 0)))
	s.step(2)
	_base = s.run.tick
	var pull: Pull = s.run.pull
	pull.set_value(ada, 0.0)
	pull.set_value(harry, 0.0)
	# Each minute: [mm, Ada's ring, Harry's ring, together, Ada home]; the table's values at its end.
	var minutes: Array = [
		[44, 0, 0, true, false, 1.0, 1.0], [45, 1, 1, true, false, 3.0, 3.0], [46, 1, 1, true, false, 5.0, 5.0],
		[47, 2, 2, true, false, 8.0, 8.0], [48, 2, 2, true, false, 11.0, 11.0], [49, 2, 2, true, false, 14.0, 14.0],
		[50, 2, 2, false, false, 23.0, 23.0], [51, 1, 2, false, false, 29.0, 32.0], [52, 1, 2, false, false, 35.0, 41.0],
		[53, 0, 2, false, false, 38.0, 50.0], [54, 0, 2, false, true, 18.0, 59.0], [55, 0, 2, false, true, 0.0, 38.0],
		[56, 0, 2, false, true, 0.0, 47.0], [57, 0, 2, false, true, 0.0, 56.0]]
	# First crossings: [miner, threshold, upward, the time it should land].
	var watch: Array = [[harry, 30.0, true, _at(51, 47)], [ada, 30.0, true, _at(52, 10)], [harry, 50.0, true, _at(54, 0)],
		[harry, 30.0, true, _at(55, 7)], [ada, 0.0, false, _at(55, 54)], [harry, 50.0, true, _at(57, 20)]]
	var seen: Array[int] = []
	var prev: Dictionary = {ada: 0.0, harry: 0.0}
	var attended_ada: bool = false
	for row: Array in minutes:
		var mm: int = int(Variants.number(row[0]))
		rings[ada] = row[1]
		rings[harry] = row[2]
		if Variants.flag(row[3]):
			s.run.movement.place(s.run, ada, Vector2(10.5, 1.5))
			s.run.movement.place(s.run, harry, Vector2(11.5, 1.5))
		else:
			s.run.movement.place(s.run, harry, Vector2(40.5, 1.5))
			if Variants.flag(row[4]):
				s.run.movement.place(s.run, ada, Vector2(29.5, 3.5)) # home with the others
				home[ada] = true
			else:
				s.run.movement.place(s.run, ada, Vector2(1.5, 1.5))
		while s.run.tick < _at(mm + 1, 0):
			if s.run.tick == _at(55, 0):
				# The Tapper's hunt on Harry ends (CRT-01): the ebb.
				s.run.creatures.gate.hunt_ended.emit(null, harry, "searched 30 s")
				assert_almost_eq(pull.value_of(harry), 29.0, 0.05, "59, ebbing to 29 at 55:00")
			s.step(1)
			_watch(pull, watch, seen, prev, s.run.tick)
			if s.run.tick >= _at(51, 47) and s.run.tick < _at(55, 0) and pull.highest_at_or_above(30.0) == ada:
				attended_ada = true
		assert_almost_eq(pull.value_of(ada), float(Variants.number(row[5])), 0.05, "Ada at %d:00" % (mm + 1))
		assert_almost_eq(pull.value_of(harry), float(Variants.number(row[6])), 0.05, "Harry at %d:00" % (mm + 1))
	while s.run.tick < _at(58, 20):
		s.step(1)
	assert_almost_eq(pull.value_of(harry), 59.0, 0.05, "Harry at 59 at 58:20")
	for i: int in watch.size():
		var w: Array = watch[i]
		assert_true(absi(seen[i] - int(Variants.number(w[3]))) <= _hz / 2,
			"crossing %d lands within 0.5 s (%.2f s off)" % [i, (seen[i] - int(Variants.number(w[3]))) / float(_hz)])
	assert_false(attended_ada, "from 51:47 to 55:00 the highest at 30 or more is Harry, never Ada")


## Notes the tick each watched crossing happens, in order: the next one, as its miner's Pull goes
## from one side of its threshold to the other this tick.
func _watch(pull: Pull, watch: Array, seen: Array[int], prev: Dictionary, tick: int) -> void:
	if seen.size() < watch.size():
		var w: Array = watch[seen.size()]
		var m: int = int(Variants.number(w[0]))
		var t: float = float(Variants.number(w[1]))
		var p: float = float(Variants.number(prev[m]))
		var v: float = pull.value_of(m)
		var crossed: bool = (p < t - 1e-9 and v >= t - 1e-9) if Variants.flag(w[2]) else (p > t + 1e-9 and v <= t + 1e-9)
		if crossed:
			seen.append(tick)
	for raw: Variant in prev.keys():
		prev[raw] = pull.value_of(int(Variants.number(raw)))

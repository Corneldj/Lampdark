extends "res://tests/scenario/kit/scenario_test.gd"
## DIR-01's cycle (Gameplay §10.2): a maximum of 70 or more enters PEAK on that tick; PEAK lasts
## 60-100 ticks (3-5 s, rolled); RELAX lasts 1,200, 900 or 600 ticks for a peaker in rings 0-1, 2
## or 3-4; then BUILD, and PEAK at once if the maximum is still 70 or more. The hunt gate follows:
## creatures may choose to hunt in BUILD (and, Proposed, through PEAK), never in a relax.

const D = preload("res://tests/scenario/director/draught_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func after_each() -> void:
	WorldCoords.ring_override = -1


## Ann at a and Ben at e, in neutral light; [s, ann, ben].
func _s(seed_value: int, rolls: PackedInt64Array = PackedInt64Array()) -> Array:
	var s: Scenario = make({"seed": seed_value, "fixture": D.hall(), "director": true})
	if not rolls.is_empty():
		assert_true(s.run.script_rolls(HashDomain.DIRECTOR_PEAK_HOLD, PackedInt64Array(), rolls))
	var ids: Array[int] = D.crew(s, ["ann", "ben"] as Array[String], ["a", "e"] as Array[String])
	D.stand_in(s)
	s.step(2)
	return [s, ids[0], ids[1]]


func _phase(s: Scenario) -> DraughtCycle.Phase:
	return s.run.draught.cycle.phase


## Ticks from now until the phase changes (at most `limit`).
func _ticks_in_phase(s: Scenario, limit: int) -> int:
	var from: DraughtCycle.Phase = _phase(s)
	var n: int = 0
	while _phase(s) == from and n < limit:
		s.step(1)
		n += 1
	return n


func test_70_enters_peak_on_that_tick_and_the_gate_follows() -> void:
	var w: Array = _s(601)
	var s: Scenario = w[0]
	var ann: int = w[1]
	var gate: HuntGate = s.run.creatures.gate
	D.set_value(s, ann, 69.0)
	s.step(1)
	assert_eq(_phase(s), DraughtCycle.Phase.BUILD, "69 builds")
	assert_true(Variants.flag(gate.build_active.call()), "creatures may choose to hunt")
	assert_false(Variants.flag(gate.relax_active.call()))
	var peaks: Array = []
	s.run.draught.cycle.peak_begun.connect(func(peaker: int, ring: int) -> void: peaks.append([s.run.tick, peaker, ring]))
	D.set_value(s, ann, 70.0)
	s.step(1)
	assert_eq(_phase(s), DraughtCycle.Phase.PEAK, "70 peaks")
	assert_eq(peaks.size(), 1)
	assert_eq(int(Variants.number(peaks[0][1])), ann, "Ann peaked")
	assert_false(Variants.flag(gate.build_active.call()), "no build in a peak")
	assert_false(Variants.flag(gate.relax_active.call()), "and no relax yet: chosen hunts still allowed (Proposed)")


func test_peak_lasts_60_to_100_ticks() -> void:
	# The roll's extremes and its middle, scripted; then unscripted seeds.
	var cases: Array = [[0, 60], [1 << 63, 80], [-1, 100]]
	var seed_value: int = 610
	for c: Array in cases:
		seed_value += 1
		var w: Array = _s(seed_value, PackedInt64Array([int(Variants.number(c[0]))]))
		var s: Scenario = w[0]
		D.set_value(s, int(Variants.number(w[1])), 70.0)
		s.step(1)
		assert_eq(_ticks_in_phase(s, 500), int(Variants.number(c[1])), "a roll of %s holds %s ticks" % [c[0], c[1]])
	for i: int in 8:
		var w: Array = _s(620 + i)
		var s: Scenario = w[0]
		D.set_value(s, int(Variants.number(w[1])), 75.0)
		s.step(1)
		var held: int = _ticks_in_phase(s, 500)
		assert_true(held >= 60 and held <= 100, "seed %d: %d ticks" % [620 + i, held])


func test_relax_lasts_by_the_peakers_ring() -> void:
	var cases: Array = [[0, 1200], [1, 1200], [2, 900], [3, 600], [4, 600]]
	var seed_value: int = 630
	for c: Array in cases:
		seed_value += 1
		WorldCoords.ring_override = int(Variants.number(c[0]))
		var w: Array = _s(seed_value, PackedInt64Array([0]))
		var s: Scenario = w[0]
		var relaxes: Array = []
		s.run.draught.cycle.relax_begun.connect(func(length: int, ring: int) -> void: relaxes.append([length, ring]))
		D.set_value(s, int(Variants.number(w[1])), 70.0)
		s.step(1)
		assert_eq(_ticks_in_phase(s, 500), 60, "the peak")
		assert_eq(_phase(s), DraughtCycle.Phase.RELAX)
		assert_true(Variants.flag(s.run.creatures.gate.relax_active.call()), "the gate shuts on chosen hunts")
		assert_eq(int(Variants.number(relaxes[0][1])), int(Variants.number(c[0])), "the peaker's ring, read at the peak")
		assert_eq(_ticks_in_phase(s, 3000), int(Variants.number(c[1])), "ring %s: a %s-tick relax" % [c[0], c[1]])
		assert_eq(_phase(s), DraughtCycle.Phase.BUILD, "then build")


func test_after_a_relax_a_peak_follows_at_once_if_the_maximum_is_still_over() -> void:
	WorldCoords.ring_override = 3
	var w: Array = _s(640, PackedInt64Array([0, 0]))
	var s: Scenario = w[0]
	var ben: int = w[2]
	var ended: Array = []
	var peaks: Array = []
	s.run.draught.cycle.relax_ended.connect(func() -> void: ended.append(s.run.tick))
	s.run.draught.cycle.peak_begun.connect(func(_p: int, _r: int) -> void: peaks.append(s.run.tick))
	D.set_value(s, int(Variants.number(w[1])), 70.0)
	s.step(1)
	_ticks_in_phase(s, 500)
	assert_eq(_phase(s), DraughtCycle.Phase.RELAX)
	s.step(599) # the 600-tick relax (ring 3) has one tick left
	D.set_value(s, ben, 100.0) # still over when the relax ends (it drains only 0.25 a tick)
	s.step(1)
	assert_eq(ended.size(), 1, "the relax ended")
	assert_eq(peaks.size(), 2, "and a second peak began")
	assert_eq(int(Variants.number(peaks[1])), int(Variants.number(ended[0])), "on the same tick")
	assert_eq(s.run.draught.cycle.peaker, ben, "Ben, now the highest")

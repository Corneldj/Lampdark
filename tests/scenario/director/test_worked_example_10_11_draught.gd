extends "res://tests/scenario/kit/scenario_test.gd"
## DIR-01: Gameplay §10.11's Draught column, from 57:30. Harry is out alone on the Second Level,
## lit, his lamp open. At 57:40 he shutters it to pass a chamber hung with coats: alone in the dark,
## 30 at 57:46. A man-trap at 57:50: 45. The Stythe's grab at 58:00: 70, the peak. With the peak's
## roll forced to 4 s the relax runs 58:04-58:49 (45 s, the Second Level). The drag runs out at
## 58:20: Harry falls, untracked; Ada (out, lit) and Ellis, Wilf and Nell (behind shut gates) each
## gain +15 once when the knocks reach them, and are back to 0 within 2 s of the gain.
## Scripted miners, light and lamps; the creatures are stubbed (the grab names none).

const D = preload("res://tests/scenario/director/draught_world.gd")
const LIT: float = 0.35
const DARK: float = 0.05

var _base: int = 0


func before_all() -> void:
	assert_true(Tuning.load_server())


func after_each() -> void:
	WorldCoords.ring_override = -1


## The tick at run time mm:ss (the test starts at 57:30).
func _at(mm: int, ss: int) -> int:
	return _base + ((mm - 57) * 60 + ss - 30) * roundi(Tuning.f(&"net.tick_hz"))


## Steps until `tick` is the next to run: an event issued now happens in that tick.
func _to(s: Scenario, tick: int) -> void:
	s.step(tick - s.run.tick)


func test_the_draught_column() -> void:
	WorldCoords.ring_override = 2 # the Second Level
	var s: Scenario = make({"seed": 1011, "fixture": D.hall(), "director": true})
	assert_true(s.run.script_rolls(HashDomain.DIRECTOR_PEAK_HOLD, PackedInt64Array(), PackedInt64Array([1 << 63])), "a 4 s peak")
	var ids: Array[int] = D.crew(s, ["ada", "harry", "ellis", "wilf", "nell"] as Array[String],
		["c", "f", "a", "b", "g"] as Array[String])
	var ada: int = ids[0]
	var harry: int = ids[1]
	var home: Array[int] = [ids[2], ids[3], ids[4]]
	var light: Dictionary = {ada: LIT, harry: LIT, ids[2]: LIT, ids[3]: LIT, ids[4]: LIT}
	var lamps: Dictionary = {harry: true}
	D.stand_in(s, light, lamps)
	s.run.crew.is_sealed_inside = func(e: int) -> bool: return home.has(e)
	var peaks: Array = []
	var relaxes: Array = []
	var ended: Array = []
	s.run.draught.cycle.peak_begun.connect(func(p: int, r: int) -> void: peaks.append([s.run.tick, p, r]))
	s.run.draught.cycle.relax_begun.connect(func(n: int, r: int) -> void: relaxes.append([s.run.tick, n, r]))
	s.run.draught.cycle.relax_ended.connect(func() -> void: ended.append(s.run.tick))
	s.step(2)
	_base = s.run.tick
	_to(s, _at(57, 40))
	assert_eq(D.value(s, harry), 0.0, "Harry reads 0 until 57:40: lit, nothing seen")
	# 57:40: he shutters to pass the chamber hung with coats.
	light[harry] = DARK
	lamps.erase(harry)
	_to(s, _at(57, 46))
	assert_almost_eq(D.value(s, harry), 30.0, 1e-6, "30 at 57:46: alone in the dark")
	# 57:50: a man-trap.
	_to(s, _at(57, 50))
	assert_true(s.run.holds.catch(s.run, harry, CaughtHold.Kind.MAN_TRAP, 1))
	s.step(1)
	assert_almost_eq(D.value(s, harry), 45.0, 1e-6, "45 at 57:50: caught")
	# 58:00: the grab; the drag runs 20 s.
	_to(s, _at(58, 0))
	assert_gt(s.run.holds.grab(s.run, harry, GrabHold.Kind.STYTHE_DRAG, 0, roundi(20.0 * Tuning.f(&"net.tick_hz"))), 0)
	s.step(1)
	assert_almost_eq(D.value(s, harry), 70.0, 1e-6, "70 at 58:00: grabbed")
	assert_eq(peaks.size(), 1, "the peak")
	var peak: Array = peaks[0]
	assert_eq(peak, [_at(58, 0), harry, 2], "at 58:00, Harry, the Second Level")
	# The peak holds 4 s; the relax runs 45 s.
	_to(s, _at(58, 4) + 1)
	assert_eq(relaxes, [[_at(58, 4), 900, 2]], "the relax from 58:04, 45 s (the Second Level)")
	# Through the fall and its knocks: Ada, Ellis, Wilf and Nell each gain once and drain away.
	var others: Array[int] = [ada]
	others.append_array(home)
	var last: Dictionary = {}
	var gains: Dictionary = {}
	var zero_after: Dictionary = {}
	for e: int in others:
		last[e] = D.value(s, e)
		gains[e] = []
	while s.run.tick < _at(58, 40):
		s.step(1)
		for e: int in others:
			var v: float = D.value(s, e)
			var g: Array = gains[e]
			if v > float(Variants.number(last[e])):
				g.append(s.run.tick)
			if v == 0.0 and not g.is_empty() and not zero_after.has(e):
				zero_after[e] = s.run.tick - int(Variants.number(g[0]))
			last[e] = v
	assert_eq(D.value(s, harry), -1.0, "Harry fell at 58:20: no longer tracked")
	var knocks: int = -1
	for e: int in others:
		var g: Array = gains[e]
		assert_eq(g.size(), 1, "miner %d gains once" % e)
		var at_tick: int = int(Variants.number(g[0])) if not g.is_empty() else -1
		if knocks < 0:
			knocks = at_tick
		assert_eq(at_tick, knocks, "all at the knocks")
		assert_true(zero_after.has(e) and int(Variants.number(zero_after[e])) <= roundi(2.0 * Tuning.f(&"net.tick_hz")),
			"miner %d back to 0 within 2 s of the gain" % e)
	var knock_delay: int = roundi(Tuning.f(&"voice.knock_delay_s") * Tuning.f(&"net.tick_hz"))
	assert_true(knocks >= _at(58, 20) - 1 and knocks <= _at(58, 20) + knock_delay + 1, "the knocks of the 58:20 fall")
	_to(s, _at(58, 49) + 1)
	assert_eq(ended, [_at(58, 49)], "the relax ends at 58:49")
	assert_eq(s.run.draught.cycle.phase, DraughtCycle.Phase.BUILD)

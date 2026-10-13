extends "res://tests/scenario/kit/scenario_test.gd"
## NET-06 at 60, 120 and 200 ms: light the victim makes after a Stythe wind-up starts (a shutter
## opened, an electric lamp switched on) never saves them, whatever its stamp; leaving the
## 1.5-tile reach still does. The Stythe is a stub until CRT-14.

const L = preload("res://tests/scenario/net/lagcomp_world.gd")
const E: int = 40
const REACH: float = 1.5


func before_all() -> void:
	assert_true(Tuning.load_server())


func _case(rtt_ms: int, press: int, walk: bool) -> DefenderRule.WindUp:
	var s: Scenario = make({"seed": 800 + press, "fixture": L.room()})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"), {"facing_deg": 0.0})
	ann.link(rtt_ms, 0.0)
	ann.at(0).lamp(true, 1)
	# The Stythe snuffed her flame before winding up: her lamp starts dark.
	var lamp: L.StubLamp = L.StubLamp.new(ann.slot, false)
	assert_true(s.run.add_system(lamp))
	var start: Vector2 = s.run.registry.get_entity(ann.entity_id).position
	var stythe_at: Vector2 = start - Vector2(1.45, 0.0)
	var id: int = ann.entity_id
	var w: DefenderRule.WindUp = DefenderRule.WindUp.new()
	w.kind = &"stythe"
	w.defender_slot = ann.slot
	w.defender_entity = id
	w.started_tick = E - 12
	w.in_reach = func(r: RunState) -> bool: return r.registry.get_entity(id).position.distance_to(stythe_at) <= REACH
	# Were light to count, her lamp lit would save her: the rule must ignore it.
	w.lit = func(_r: RunState, _shut: bool) -> bool: return not lamp.open
	assert_true(s.run.add_system(L.StubWindUp.new(w, E)))
	if walk:
		ann.at(press).move(0.0, InputRecord.Gait.WALK, 12)
	else:
		# Opening the shutter, or switching an electric lamp on (the same light to the rule).
		ann.at(press).lamp(false, 1)
	s.step(E + 20)
	return w


func _sweep(rtt_ms: int) -> void:
	for press: int in range(E - 12, E + 2):
		var w: DefenderRule.WindUp = _case(rtt_ms, press, false)
		assert_eq(w.outcome, DefenderRule.Outcome.CONFIRMED, "%d ms: light made at %+d never saves" % [rtt_ms, press - E])
		assert_lte(w.decided_tick, E + 3)
	var escaped: DefenderRule.WindUp = _case(rtt_ms, E - 12, true)
	assert_eq(escaped.outcome, DefenderRule.Outcome.MISSED, "%d ms: leaving the reach early still escapes" % rtt_ms)


func test_at_60_ms() -> void:
	_sweep(60)


func test_at_120_ms() -> void:
	_sweep(120)


func test_at_200_ms() -> void:
	_sweep(200)

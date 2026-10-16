extends "res://tests/scenario/kit/scenario_test.gd"
## DIR-02's Fan roll (Gameplay §6.9, §10.3): never for a relax in ring 0; a surge in half the
## relaxes in ring 1 or deeper (50% ± 1.5% of 10,000 seeded relaxes); and the surge lasts its full
## 40 s even after a 30 s relax. SND-16's surge is stood in for by FanRoll's own.

const D = preload("res://tests/scenario/director/draught_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func after_each() -> void:
	super.after_each()
	WorldCoords.ring_override = -1


func test_never_rolled_in_ring_0() -> void:
	var s: Scenario = make({"seed": 1201, "fixture": D.hall(), "director": true})
	var fan: FanRoll = s.run.relax.fan
	for i: int in 50:
		fan.on_relax_begun(s.run, 0)
	assert_eq(fan.rolls, 0, "a relax in ring 0 is never rolled")
	assert_eq(fan.surges, 0)


func test_half_the_relaxes_from_ring_1_surge() -> void:
	var surges: int = 0
	for seed_value: int in range(1, 10001):
		var fan: FanRoll = FanRoll.new()
		fan.rng = LbRng.from_seed(LbHash.sub_seed(seed_value, HashDomain.DIRECTOR_FAN_ROLL, PackedInt64Array(), 0))
		if fan.roll():
			surges += 1
	gut.p("%d of 10,000 relaxes surged" % surges)
	assert_between(surges, 4850, 5150, "50% ± 1.5%")


func test_a_surge_runs_40_s_past_a_30_s_relax() -> void:
	WorldCoords.ring_override = 3 # a 30 s relax
	var s: Scenario = make({"seed": 1203, "fixture": D.hall(), "director": true,
		"overrides": {"director.fan_roll_chance": 1.0}})
	var ids: Array[int] = D.crew(s, ["ann"] as Array[String], ["a"] as Array[String])
	D.stand_in(s)
	s.step(2)
	var begun: Array = []
	var ended: Array = []
	s.run.draught.cycle.relax_begun.connect(func(n: int, _r: int) -> void: begun.append([s.run.tick, n]))
	s.run.draught.cycle.relax_ended.connect(func() -> void: ended.append(s.run.tick))
	D.set_value(s, ids[0], 70.0)
	while ended.is_empty():
		s.step(1)
	var hz: int = roundi(Tuning.f(&"net.tick_hz"))
	var first: Array = begun[0]
	var start: int = int(Variants.number(first[0]))
	assert_eq(int(Variants.number(first[1])), 30 * hz, "a 30 s relax")
	assert_eq(s.run.relax.fan.surges, 1, "it surged")
	assert_true(s.run.relax.fan.surging(s.run), "still surging as the relax ends")
	while s.run.tick < start + 40 * hz - 1:
		s.step(1)
	assert_true(s.run.relax.fan.surging(s.run), "until 40 s")
	s.step(2)
	assert_false(s.run.relax.fan.surging(s.run), "and no longer")

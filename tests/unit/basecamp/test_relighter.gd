extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-01: before power_on the relighter refuses; after it, it relights an Out lamp in 3 s with no
## notch spent.

const C = preload("res://tests/scenario/basecamp/camp_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_relighter() -> void:
	var s: Scenario = make({"seed": 5, "fixture": C.scenario_fixture()})
	var camp: BaseCampState = C.load_camp(s)
	s.step(1)
	# The first lamp, hung Out on its hook, is a gauze lamp (MNR-06); MNR-07 relights it.
	var lamp: GauzeLamp = s.run.lamps.lamp_at_entity(camp.first_lamp.entity)
	assert_not_null(lamp)
	assert_eq(lamp.state(), GauzeLamp.State.OUT)
	assert_false(camp.relighter.begin(s.run, camp.powered, lamp), "dead until Power")
	camp.powered = true
	var noise_before: int = s.run.noise.event_log.size()
	assert_true(camp.relighter.begin(s.run, camp.powered, lamp))
	var start: int = s.run.tick
	var lit_at: Array[int] = [-1]
	s.on_tick = func(sc: Scenario) -> void:
		if lit_at[0] < 0 and lamp.burning():
			lit_at[0] = sc.run.tick - 1
	s.step(80)
	assert_eq(lit_at[0] - start, 60, "3 s")
	assert_eq(lamp.notches, 3, "no notch spent")
	assert_eq(s.run.noise.event_log.size(), noise_before, "no noise")
	assert_false(camp.relighter.begin(s.run, camp.powered, lamp), "a lit lamp needs no relight")

extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-08 with CRT-13's snuff wiring: snuffs every 2.0 s beside an on, full lamp end its light after
## 22-24 s depending on the first snuff's phase; every 1.6 s, after 17.5-19.5 s. The Stythe reads
## the lamp's light as an electric source and drains it through `electric_drain`.

const C = preload("res://tests/unit/mnr/chalk_world.gd")
const SW = preload("res://tests/unit/creatures/stythe_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


## Seconds of light under snuffs every `interval` ticks, the first after `phase` ticks.
func _light_lasts(run_seed: int, interval: int, phase: int) -> float:
	var s: Scenario = make({"seed": run_seed, "fixture": C.B.room()})
	var ann: MinerHandle = C.miner(s, "ann", Vector2i(4, 3))
	s.step(2)
	var it: Item = ElectricLamps.make(s.run, -1, true)
	s.run.inventory.hands_of(ann.entity_id).lamp_hand = it
	s.step(1)
	var start: int = s.run.tick
	var next: int = start + phase
	for _i: int in 1000:
		if s.run.tick >= next:
			var source: int = int(Variants.number(s.run.electric.sources.get(it.uid, 0)))
			if source != 0:
				s.run.electric.drain_source(s.run, source, Tuning.f(&"stythe.electric_snuff_drain_s"))
			next += interval
		s.step(1)
		if not s.run.electric.sources.has(it.uid):
			break
	return (s.run.tick - start) / Tuning.f(&"net.tick_hz")


func test_snuffs_every_two_seconds_and_every_one_point_six() -> void:
	var hz: float = Tuning.f(&"net.tick_hz")
	for phase: int in [0, 10, 20, 39]:
		var t: float = _light_lasts(1121 + phase, roundi(2.0 * hz), phase)
		assert_between(t, 22.0, 24.0, "every 2.0 s, first after %d ticks: %.2f s" % [phase, t])
	for phase: int in [0, 16, 31]:
		var t: float = _light_lasts(1161 + phase, roundi(1.6 * hz), phase)
		assert_between(t, 17.5, 19.5, "every 1.6 s, first after %d ticks: %.2f s" % [phase, t])


func test_the_stythe_drains_it_through_its_wiring() -> void:
	var s: Scenario = make({"seed": 1171, "fixture": C.B.room(), "overrides": SW.ON})
	var st: StytheCreature = SW.stythe(s, Vector2i(11, 5))  # placed before anyone can see its tile
	var ann: MinerHandle = C.miner(s, "ann", Vector2i(4, 3))
	s.step(2)
	var it: Item = ElectricLamps.make(s.run, -1, true)
	s.run.inventory.hands_of(ann.entity_id).lamp_hand = it
	s.step(1)
	var sources: Array = st.snuff.electric_sources.call(s.run)
	assert_eq(sources, [s.run.electric.sources[it.uid]], "its snuff sees the lamp as electric")
	var before: int = ElectricLamps.battery_ticks(it)
	assert_true(Variants.flag(st.electric_drain.call(s.run, sources[0], 30.0)))
	assert_eq(ElectricLamps.battery_ticks(it), before - 600)
	s.run.electric.switch(s.run, it, false)
	s.step(1)
	var after: Array = st.snuff.electric_sources.call(s.run)
	assert_eq(after, [], "switched off: no target (Proposed)")

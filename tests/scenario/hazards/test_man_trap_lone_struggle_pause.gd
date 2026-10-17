extends "res://tests/scenario/kit/scenario_test.gd"
## HAZ-01 (Gameplay §8.2, §7.3): a lone miner in the jaws waits out the rock. A Tapper stand-in
## listens a few tiles off: each struggle reaches it while Bob holds interact; he lets go, and for as
## long as he waits nothing of his reaches it; holding again he goes on from where he stopped, and is
## free after 300 ticks of struggle in all.

const T = preload("res://tests/unit/hazards/trap_world.gd")
const LISTENER: int = 9001


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_he_pauses_while_it_listens_and_keeps_his_progress() -> void:
	var s: Scenario = make(T.cfg(5001))
	var bob: MinerHandle = T.miner_at(s, "bob", Vector2(6.5, 2.5))
	s.step(2)
	T.catch(s, bob)
	s.run.noise.set_creature_listener(LISTENER, T.TRAP + Vector2i(4, 0), 1.0)
	var heard: Array[int] = []
	s.run.noise.creature_hooks.append(func(event: NoiseSystem.Event, d: Dictionary) -> void:
		if Variants.whole(d["listener"]) == LISTENER and event.type == NoiseTypes.Type.STRUGGLE:
			heard.append(event.tick))
	s.step(2)
	bob.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 100)
	s.step(110)
	assert_gt(heard.size(), 0, "his struggles reach it")
	var progress: int = Variants.whole(s.run.man_traps.struggle.get(bob.entity_id, 0))
	var during: int = heard.size()
	# It listens: he waits.
	s.step(200)
	assert_eq(heard.size(), during, "waiting, nothing of his reaches it")
	assert_eq(Variants.whole(s.run.man_traps.struggle.get(bob.entity_id, 0)), progress, "and he keeps his progress")
	assert_true(s.run.holds.caught.has(bob.entity_id))
	bob.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 300 - progress + 10)
	s.step(300 - progress + 20)
	assert_false(s.run.holds.caught.has(bob.entity_id), "free after 300 ticks of struggle in all")
	assert_eq(heard.size(), 8, "a struggle every 40 ticks held, and it heard each")

extends "res://tests/scenario/kit/scenario_test.gd"
## HAZ-01 (Gameplay §8.2, §11.3): alone in the jaws. The victim holds interact: free after 300 ticks
## of holding in all, a struggle (noise.struggle_np) every 40 ticks held and none while paused, the
## progress kept across pauses; their status says they may struggle. A Hired Hand driving a miner
## never struggles, nor does an unconscious one, who waits for a teammate.

const T = preload("res://tests/unit/hazards/trap_world.gd")

var freed: Array[Array] = []


func before_all() -> void:
	assert_true(Tuning.load_server())


func _alone(run_seed: int) -> Dictionary:
	var s: Scenario = make(T.cfg(run_seed))
	var bob: MinerHandle = T.miner_at(s, "bob", Vector2(6.5, 2.5))
	s.step(2)
	T.catch(s, bob)
	s.step(2)
	freed.clear()
	s.run.trap_events.freed.connect(func(miner: int, kind: CaughtHold.Kind) -> void: freed.append([miner, kind, s.run.tick]))
	return {"s": s, "bob": bob}


func test_three_hundred_ticks_of_struggle_pauses_keeping_the_progress() -> void:
	var w: Dictionary = _alone(4301)
	var s: Scenario = w["s"]
	var bob: MinerHandle = w["bob"]
	var flags: int = Variants.whole(OwnStatus.of(s.run, bob.entity_id)["flags"])
	assert_ne(flags & StatusWire.TRAP_STRUGGLE, 0, "his status says he may struggle")
	var before: int = T.events_of(s, NoiseTypes.Type.STRUGGLE).size()
	bob.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 120)
	s.step(130)
	var progress: int = Variants.whole(s.run.man_traps.struggle.get(bob.entity_id, 0))
	assert_between(progress, 115, 120, "120 ticks held")
	var paused: int = T.events_of(s, NoiseTypes.Type.STRUGGLE).size()
	s.step(80)
	assert_eq(Variants.whole(s.run.man_traps.struggle.get(bob.entity_id, 0)), progress, "a pause keeps the progress")
	assert_eq(T.events_of(s, NoiseTypes.Type.STRUGGLE).size(), paused, "and makes no sound")
	assert_true(s.run.holds.caught.has(bob.entity_id), "still held")
	bob.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 220)
	s.step(230)
	assert_eq(freed.size(), 1, "struggled free")
	var f: Array = freed[0]
	assert_eq(Variants.whole(f[1]), CaughtHold.Kind.MAN_TRAP)
	assert_false(s.run.holds.caught.has(bob.entity_id))
	assert_eq(Variants.whole(OwnStatus.of(s.run, bob.entity_id)["flags"]) & StatusWire.TRAP_STRUGGLE, 0, "free: no more")
	var struggles: Array[NoiseSystem.Event] = T.events_of(s, NoiseTypes.Type.STRUGGLE)
	assert_eq(struggles.size() - before, 8, "a struggle every 40 ticks of the 300 held")
	assert_eq(struggles[struggles.size() - 1].level_np, Tuning.f(&"noise.struggle_np"))
	var last: Dictionary = s.run.man_traps.history[s.run.man_traps.history.size() - 1]
	assert_eq(str(last["how"]), "struggle")


func test_a_hand_and_the_unconscious_never_struggle() -> void:
	var w: Dictionary = _alone(4302)
	var s: Scenario = w["s"]
	var bob: MinerHandle = w["bob"]
	s.run.crew.is_hand_driven = func(e: int) -> bool: return e == bob.entity_id
	assert_false(ManTraps.may_struggle(s.run, bob.entity_id), "a Hand driving him never struggles")
	bob.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 60)
	s.step(65)
	assert_eq(Variants.whole(s.run.man_traps.struggle.get(bob.entity_id, 0)), 0, "no progress")
	s.run.crew.is_hand_driven = func(_e: int) -> bool: return false
	assert_true(s.run.falls.fall_unconscious(s.run, bob.entity_id, FallCause.Cause.BLAST))
	s.step(2)
	assert_true(s.run.holds.caught.has(bob.entity_id), "unconscious, he stays in the jaws")
	assert_false(ManTraps.may_struggle(s.run, bob.entity_id), "and cannot struggle")
	bob.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 60)
	s.step(65)
	assert_eq(Variants.whole(s.run.man_traps.struggle.get(bob.entity_id, 0)), 0)
	assert_eq(freed.size(), 0, "he waits for a teammate")

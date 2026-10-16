extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-09: it strikes only a conscious miner who is the true source of a heard sound and within
## 1.5 tiles of the wall face where it waits; a sound further off sends it to Approach; it never
## strikes the unconscious; a strike is never made on an apparent position alone.

const W = preload("res://tests/scenario/creatures/hunt_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func before_each() -> void:
	W.ring(1)


func after_each() -> void:
	super.after_each()
	Tuning.clear_dev_overrides()


func test_true_source_in_reach() -> void:
	var s: Scenario = make({"seed": 1, "fixture": W.road()})
	var r: Array = W.pinned(s)
	var ann: MinerHandle = r[0]
	var t: Tapper = r[1]
	assert_eq(t.state.name, &"pin", "Ann talked within reach of its face: struck and pinned")
	assert_eq(W.life(s, ann.entity_id), MinerTransitions.Life.GRABBED)
	var checks: Array[Dictionary] = s.run.creatures.log.of_type(&"tapper_strike_check")
	assert_eq(int(Variants.number(checks[0]["miner"])), ann.entity_id, "the Inquiry logs the true source")


func test_out_of_reach_approaches() -> void:
	var s: Scenario = make({"seed": 2, "fixture": W.road()})
	var bob: MinerHandle = s.add_miner("bob", Vector2i(14, 5))
	var t: Tapper = W.tapper(s, Vector2i(10, 4))
	t.follower.stop()
	s.step(2)
	W.talk(s, bob)
	s.step(3)
	assert_eq(t.state.name, &"approach", "4 tiles off: it comes to the wall nearest the sound")
	assert_eq(s.run.holds.grab_of(bob.entity_id), null)


func test_never_the_unconscious() -> void:
	var s: Scenario = make({"seed": 3, "fixture": W.road()})
	var ann: MinerHandle = s.add_miner("ann", Vector2i(10, 5))
	var t: Tapper = W.tapper(s, Vector2i(10, 4))
	t.follower.stop()
	s.step(2)
	s.run.miner_state.fall_unconscious(ann.entity_id, "test")
	s.step(1)
	s.run.noise.emit(NoiseTypes.Type.GASP, Vector2i(10, 5), {"level_np": 12.0, "source": ann.entity_id})
	s.step(30)
	assert_eq(s.run.holds.grab_of(ann.entity_id), null, "moans bring it to the wall, never a strike")
	assert_ne(t.state.name, &"windup")


func test_the_arm_is_seen_the_tapper_never() -> void:
	var s: Scenario = make({"seed": 4, "fixture": W.road()})
	var bob: MinerHandle = s.add_miner("bob", Vector2i(14, 5), {"facing_deg": 180.0})
	bob.at(0).face(180.0)
	var lit: Array = []
	for x: int in 40:
		for y: int in 11:
			lit.append(Vector2i(x, y))
	s.run.light.grid.add_area("emergency", 3, 0, 0.6, lit)
	var r: Array = W.pinned(s)
	var t: Tapper = r[1]
	s.step(2)
	assert_eq(t.state.name, &"pin")
	assert_ne(s.run.vision.native.sees_entity(bob.slot, t.hunt.arm), LbVision.LEVEL_NONE, "the arm out of the wall is seen in light")
	assert_eq(s.run.vision.native.sees_entity(bob.slot, t.entity_id), LbVision.LEVEL_NONE, "the Tapper in the rock never is")


## The first playtest: its silence was the tell nobody noticed. Going quiet to listen within
## tapper.listen_cue_tiles of a miner, it tells them '[the tapping stops]' (diffuse: never where),
## and its dust trickles from the face; a miner far off is told nothing.
func test_going_quiet_near_a_miner_is_noticed() -> void:
	var s: Scenario = make({"seed": 4, "fixture": W.road()})
	var bob: MinerHandle = s.add_miner("bob", Vector2i(14, 5))
	bob.brain = null
	var far: MinerHandle = s.add_miner("far", Vector2i(40, 5))
	far.brain = null
	var heard: Dictionary = {}
	var prev: Callable = s.run.audio.sink
	s.run.audio.sink = func(slot: int, r: AudioRecord) -> void:
		if r.type == LocalSounds.Type.ROCK_HUSH:
			heard[slot] = r.flags
		if prev.is_valid():
			prev.call(slot, r)
	var t: Tapper = W.tapper(s, Vector2i(10, 4))
	t.follower.stop()
	s.step(2)
	var bursts: int = s.run.tells.bursts_sent
	W.talk(s, bob)
	W.until_state(s, t, &"listen", 200)
	assert_eq(t.state.name, &"listen", "it came to the wall nearest the sound and went quiet")
	s.step(1)
	assert_true(heard.has(bob.slot), "Bob is told the tapping stopped")
	assert_ne(int(Variants.number(heard.get(bob.slot, 0))) & AudioRecord.DIFFUSE, 0, "from nowhere in particular")
	assert_false(heard.has(far.slot), "the far miner is told nothing")
	assert_gte(s.run.tells.bursts_sent, bursts, "its dust trickles where lit")

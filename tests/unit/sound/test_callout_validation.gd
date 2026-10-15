extends "res://tests/scenario/kit/scenario_test.gd"
## SND-11: the server refuses a callout, with no record and no event: in the Aside, holding the breath
## (Proposed), unconscious (but for RSC-04's forced 'Help!') or dead, at no band or a scream, from the
## wrong page, or while the last bark still plays (Proposed). Grabbed miners may call. Every wheel
## line and job-page line sends at whisper, talk and shout.

const N = preload("res://tests/scenario/net/net04_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _pair(seed_value: int) -> Array:
	var s: Scenario = make({"seed": seed_value, "fixture": N.road()})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	var bob: MinerHandle = s.add_miner("bob", s.fixture.spot("a") + Vector2i(2, 0))
	s.step(3)
	return [s, ann, bob]


func _wait_out(s: Scenario) -> void:
	s.step(4 * 20)


func test_every_line_at_every_band() -> void:
	var p: Array = _pair(401)
	var s: Scenario = p[0]
	var ann: MinerHandle = p[1]
	var bob: MinerHandle = p[2]
	var heard: Array[String] = []
	for page: Array[String] in [CalloutLines.WHEEL, CalloutLines.JOB_PAGE]:
		if page == CalloutLines.JOB_PAGE:
			assert_true(s.run.inventory.begin_two_handed(s.run, ann.entity_id), "carrying two-handed: the job page")
		for line: String in page:
			for band: int in [1, 2, 3]:
				var id: int = s.run.callouts.speak(s.run, ann.slot, line, band)
				assert_gt(id, 0, "%s at band %d" % [line, band])
				_wait_out(s)
				var r: CalloutRecord = bob.connection.callouts.pop_back() if not bob.connection.callouts.is_empty() else null
				if r != null:
					heard.append("%s/%d" % [VoiceManifest.line_of_wire(r.line), r.band])
	assert_eq(heard.size(), 48, "Bob, 2 tiles away (inside whisper's 3), heard all 16 lines at all 3 bands")


func test_refusals() -> void:
	var p: Array = _pair(402)
	var s: Scenario = p[0]
	var ann: MinerHandle = p[1]
	var c: CalloutSystem = s.run.callouts
	assert_eq(c.speak(s.run, ann.slot, "here", 4), 0, "no scream")
	assert_eq(c.speak(s.run, ann.slot, "here", 0), 0, "no band: the centre cancels")
	assert_eq(c.speak(s.run, ann.slot, "now", 2), 0, "the job page while not carrying or at a job")
	assert_eq(c.speak(s.run, ann.slot, "here", 2, true), 0, "holding the breath")
	s.run.voice.set_route(ann.slot, VoiceRoutes.Route.ASIDE)
	assert_eq(c.speak(s.run, ann.slot, "here", 2), 0, "in the Aside")
	s.run.voice.set_route(ann.slot, VoiceRoutes.Route.NORMAL)
	assert_gt(c.speak(s.run, ann.slot, "here", 2), 0)
	assert_eq(c.speak(s.run, ann.slot, "help", 2), 0, "while the last bark still plays")
	_wait_out(s)
	assert_true(s.run.inventory.begin_two_handed(s.run, ann.entity_id))
	assert_eq(c.speak(s.run, ann.slot, "here", 2), 0, "the wheel while the job page is up")
	s.run.inventory.end_two_handed(ann.entity_id)
	s.run.miner_state.enter_caught(ann.entity_id, &"man_trap", 1)
	s.step(1)
	assert_gt(c.speak(s.run, ann.slot, "help", 3), 0, "the Caught may call")
	_wait_out(s)
	s.run.miner_state.release_caught(ann.entity_id, "test")
	s.step(1)
	# A drag's route muffles a callout to whisper range (the Grabbed may call; RSC-03 sets the route).
	s.run.voice.set_route(ann.slot, VoiceRoutes.Route.DRAGGED)
	var bob: MinerHandle = p[2]
	bob.connection.callouts.clear()
	assert_gt(c.speak(s.run, ann.slot, "help", 3), 0, "a dragged miner may call")
	s.step(4)
	assert_false(bob.connection.callouts.is_empty(), "heard within whisper range")
	if not bob.connection.callouts.is_empty():
		assert_true((bob.connection.callouts[0].flags & CalloutRecord.FLAG_MUFFLED) != 0, "muffled")
	_wait_out(s)
	s.run.voice.set_route(ann.slot, VoiceRoutes.Route.NORMAL)
	assert_true(s.run.falls.fall_unconscious(s.run, ann.entity_id, FallCause.Cause.MOTH_SMOTHER))
	s.step(1)
	assert_eq(c.speak(s.run, ann.slot, "help", 2), 0, "unconscious")
	assert_gt(c.speak(s.run, ann.slot, "help", 2, false, true), 0, "but RSC-04's forced 'Help!'")
	_wait_out(s)
	s.run.miner_state.kill(ann.entity_id, "test")
	s.step(1)
	assert_eq(c.speak(s.run, ann.slot, "help", 2, false, true), 0, "dead")
	for why: String in ["band", "page", "breath", "aside", "playing", "state"]:
		assert_gt(int(Variants.number(c.refused.get(why, 0))), 0, "refused for %s" % why)

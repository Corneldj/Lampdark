extends "res://tests/scenario/kit/scenario_test.gd"
## UI-02: nothing pauses behind a close-up. Game audio still reaches the reader's client, and the
## unheard timer keeps counting (SND-09). The Pull (DIR-03) is not built yet: every miner's reads 0,
## and the close-up path has no way to it (checked here statically), so it will count on too. The
## client's close-up never touches the audio buses or players.

const W = preload("res://tests/scenario/ui/closeup_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_audio_and_the_unheard_timer_run_on() -> void:
	var s: Scenario = W.camp(221, self)
	var deck: Vector2i = Basecamp.fixture(W.C.SEED, "cage_deck", s.run.base_camp.side)[0]["position"]
	var ann: MinerHandle = s.add_miner("ann", deck)
	s.step(3)
	W.ask(s, ann, CloseupKind.Ask.OPEN_POCKET_BOOK)
	s.step(8)
	assert_eq(W.kind_of(s, ann), CloseupKind.Kind.POCKET_BOOK)
	var unheard_before: float = s.run.heard.unheard_seconds(ann.slot)
	var events_before: int = s.client(ann).received_events.size()
	s.run.noise.emit(NoiseTypes.Type.ROCK_TAP, deck + Vector2i(2, 0))
	s.step(100)
	assert_eq(W.kind_of(s, ann), CloseupKind.Kind.POCKET_BOOK, "still reading")
	assert_almost_eq(s.run.heard.unheard_seconds(ann.slot) - unheard_before, 100.0 / Tuning.f(&"net.tick_hz"), 0.051,
		"the unheard timer ran the whole time")
	assert_gt(s.client(ann).received_events.size(), events_before, "the tap reached the reader's ears")


func test_nothing_in_the_close_up_path_reaches_a_timer() -> void:
	var server: String = FileAccess.get_file_as_string("res://server/systems/closeups/closeup_state.gd")
	for word: String in ["Pull", "pull_", "Draught", "director", "HeardTracker", "run.heard", "frozen", "set_time_scale"]:
		assert_false(server.contains(word), "the server's close-up never names %s" % word)
	var client: String = FileAccess.get_file_as_string("res://client/ui/closeup/closeup_manager.gd")
	for word: String in ["AudioServer", "AudioBuses", "EventPlayer", "AmbientBeds", "paused", "time_scale"]:
		assert_false(client.contains(word), "the client's close-up never names %s" % word)

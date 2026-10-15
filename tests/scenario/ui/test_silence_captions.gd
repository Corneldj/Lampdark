extends "res://tests/scenario/kit/scenario_test.gd"
## UI-03: a bed layer's end and start, as the server cues them (SND-03's ambient cues), each make a
## silence caption: '[the drip stops]', then the drip again.

const F = preload("res://tests/scenario/ui/caption_feed.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_stop_and_start() -> void:
	var s: Scenario = make({"seed": 321, "fixture": "test"})
	var ann: MinerHandle = s.add_miner("ann", Vector2i(2, 1))
	var f: F = F.new(ann, self)
	s.on_tick = func(sc: Scenario) -> void: f.pump(sc)
	s.step(5)
	s.run.audio.ambient(ann.slot, &"drips", false)
	s.step(4)
	s.run.audio.ambient(ann.slot, &"drips", true)
	s.step(4)
	assert_eq(f.texts(), [UiText.text("caption.silence.drips.stop"), UiText.text("caption.silence.drips.start")] as Array[String])
	assert_eq(f.texts()[0], "[the drip stops]")
	f.free_nodes()

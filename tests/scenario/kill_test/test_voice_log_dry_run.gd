extends "res://tests/scenario/kit/scenario_test.gd"
## QA-01's dry run of criterion 2's log instrument: a talker speaks 60 one-second utterances to four
## listeners standing at fixed road distances down a corridor (clean, and each quarter from half range
## to the edge, over two layouts), so the server writes real "voice loss" lines.
## tools/kill_test/voice_dry_run.sh runs this test and feeds its output to voice_log_check.py.

const UTTERANCES: int = 60
const FRAMES: int = 50


func before_all() -> void:
	assert_true(Tuning.load_server())


func _corridor() -> FixtureMap:
	return FixtureMap.from_ascii(PackedStringArray(["#".repeat(32), "#a" + ".".repeat(29) + "#", "#".repeat(32)]))


func _layout(seed_value: int, offsets: Array[int]) -> int:
	var s: Scenario = make({"seed": seed_value, "fixture": _corridor()})
	var a: Vector2i = s.fixture.spot("a")
	var talker: MinerHandle = s.add_miner("talker", a)
	var names: Array[String] = ["ben", "cat", "dan", "eve"]
	for i: int in offsets.size():
		s.add_miner(names[i], a + Vector2i(offsets[i], 0))
	s.step(3)
	var closed: int = 0
	for _u: int in UTTERANCES:
		talker.at(s.run.tick).say(2, FRAMES)
		s.step(FRAMES + 2)
		talker.connection.send_voice(VoicePackets.end(talker.voice_frames_sent))
		s.step(3)
		closed += 1
	return closed


func test_two_layouts_of_listeners() -> void:
	# Talk: range 12, half range 6. Offsets 3 (clean), 7, 9 and 11; then 8 for the second quarter.
	var first: int = await _layout(91, [3, 7, 9, 11])
	var second: int = await _layout(92, [3, 8, 10, 11])
	gut.p("voice dry run: %d utterances" % (first + second))
	assert_eq(first + second, UTTERANCES * 2)

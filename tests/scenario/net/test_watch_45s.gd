extends "res://tests/scenario/kit/scenario_test.gd"
## NET-07: delayed_view() runs 45 s (rescue.watch_delay_s) behind, within a tick, and gives the
## target's own received view and game sounds only: never voice (the target talks throughout),
## and nothing but what rode in its frames (no map table, Pocket Book or close-up).

const W = preload("res://tests/scenario/net/record_world.gd")
const RESULT_KEYS: Array[String] = ["tick", "view", "events"]
## The fields a frame's audio event carries (FrameDecoder), and nothing else.
const EVENT_KEYS: Array[String] = ["number", "type", "start_tick", "apparent", "remaining_np", "level_np", "duration_s", "flags", "voice",
	"gain_db", "points"]


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_watching_runs_45_s_behind_with_no_voice() -> void:
	var s: Scenario = make({"seed": 111, "fixture": "test"})
	var miners: Array[MinerHandle] = W.crew(s, 2, 111)
	var bob: MinerHandle = miners[1]
	var bobs: Dictionary = W.decoded_by_tick(s, bob)
	for t: int in range(20, 1300, 100):
		bob.at(t).say(3, 40)
	var delay_s: float = Tuning.f(&"rescue.watch_delay_s")
	var delay_ticks: int = roundi(delay_s * Tuning.f(&"net.tick_hz"))
	s.step(delay_ticks - 20)
	assert_eq(RecordReaders.delayed_view(s.run.record, bob.slot, delay_s), {}, "not yet: the run is not 45 s old")
	s.step(220)
	var worst: int = 0
	var problems: Array[String] = []
	var events: int = 0
	for i: int in 200:
		s.step(1)
		var got: Dictionary = RecordReaders.delayed_view(s.run.record, bob.slot, delay_s)
		if got.is_empty():
			problems.append("nothing at tick %d" % s.run.tick)
			continue
		var keys: Array = got.keys()
		keys.sort()
		var want: Array = RESULT_KEYS.duplicate()
		want.sort()
		if keys != want:
			problems.append("keys %s" % [keys])
		var t: int = got["tick"]
		var behind: int = (s.run.tick - 1) - t
		worst = maxi(worst, absi(behind - delay_ticks))
		var view: ReceivedView = got["view"]
		var theirs: Array = Variants.array(bobs.get(t, []))
		var their_view: ReceivedView = theirs[0] if not theirs.is_empty() else null
		if their_view == null or not view.same_as(their_view):
			problems.append("tick %d: not the view Bob held" % t)
		for e: Dictionary in Variants.array(got["events"]):
			events += 1
			for k: Variant in e.keys():
				if not EVENT_KEYS.has(str(k)):
					problems.append("an event field %s" % k)
	gut.p("worst lag error %d ticks; %d game sounds relayed; Bob spoke %d voice frames" % [worst, events, bob.voice_frames_sent])
	assert_gt(bob.voice_frames_sent, 0, "Bob was talking")
	assert_lte(worst, 1, "45 s behind, within a tick")
	assert_eq(problems, [] as Array[String])

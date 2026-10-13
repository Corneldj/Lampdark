extends GutTest
## NET-06's 'Now!' judge: the cue's arrival A from the client's report, clamped to 150 ms after
## the cue, or estimated from acknowledgements; a press counts within the window after A; a miss
## is ruled only once a later input or starvation says so.

const C: int = 100
const WINDOW: float = 20.0

var judge: NowJudge
var cue: int


func before_all() -> void:
	assert_true(Tuning.load_server())


func before_each() -> void:
	judge = NowJudge.new()
	cue = judge.register_cue(0, NoiseTypes.Type.ENGINE_CRANK, C)


func _consumed(stamp: int, reports: Array[PackedInt64Array] = [], acked: int = -1, starved: bool = false) -> InputBuffer.Consumed:
	var c: InputBuffer.Consumed = InputBuffer.Consumed.new()
	c.record = InputRecord.new()
	c.real = not starved
	c.starved = starved
	c.shown_tick = stamp
	c.cue_reports = reports
	c.acked_frame = acked
	return c


func test_the_cue_id_is_shared() -> void:
	assert_eq(cue, TimedCues.cue_id(NoiseTypes.Type.ENGINE_CRANK, C))
	assert_true(TimedCues.is_timed(NoiseTypes.Type.ENGINE_CRANK))
	assert_false(TimedCues.is_timed(NoiseTypes.Type.STEP_WALK))


func test_reported_arrival_and_the_window() -> void:
	assert_eq(judge.displayed_tick_of(0, cue), -1.0, "unknown until reported")
	judge.on_consumed(C + 4, 0, _consumed(C, [PackedInt64Array([cue, C + 1, 128])]))
	assert_almost_eq(judge.displayed_tick_of(0, cue), C + 1.5, 1e-9)
	assert_eq(judge.judge(0, cue, C + 1.5 + 18.0, WINDOW), NowJudge.Verdict.ON_TIME, "0.9 s after it reached the presser")
	assert_eq(judge.judge(0, cue, C + 1.5 + 22.0, WINDOW), NowJudge.Verdict.LATE, "1.1 s after")
	assert_eq(judge.judge(0, cue, C, WINDOW), NowJudge.Verdict.EARLY, "before it reached them")


func test_the_arrival_is_clamped_to_150_ms() -> void:
	judge.on_consumed(C + 20, 0, _consumed(C + 10, [PackedInt64Array([cue, C + 10, 0])]))
	assert_eq(judge.displayed_tick_of(0, cue), C + 3.0, "a delayed cue counts from at most 150 ms after it")
	var early: NowJudge = NowJudge.new()
	var id: int = early.register_cue(1, NoiseTypes.Type.ENGINE_CRANK, C)
	early.on_consumed(C, 1, _consumed(C, [PackedInt64Array([id, C - 5, 0])]))
	assert_eq(early.displayed_tick_of(1, id), float(C), "never before the cue itself")


func test_estimated_from_acknowledgements_without_a_report() -> void:
	judge.on_consumed(C + 2, 0, _consumed(C - 2, [], C - 1))
	assert_eq(judge.displayed_tick_of(0, cue), -1.0, "no frame at or after the cue acknowledged yet")
	judge.on_consumed(C + 5, 0, _consumed(C + 1, [], C + 1))
	assert_eq(judge.displayed_tick_of(0, cue), C + 1.0, "the render time just after the frame arrived")
	judge.on_consumed(C + 6, 0, _consumed(C + 2, [], C + 2))
	assert_eq(judge.displayed_tick_of(0, cue), C + 1.0, "the first acknowledgement decides")
	judge.on_consumed(C + 7, 0, _consumed(C + 3, [PackedInt64Array([cue, C, 0])]))
	assert_eq(judge.displayed_tick_of(0, cue), float(C), "a report, when one comes, wins")


func test_a_miss_is_ruled_only_when_known() -> void:
	judge.on_consumed(C + 4, 0, _consumed(C, [PackedInt64Array([cue, C, 0])]))
	judge.on_consumed(C + 20, 0, _consumed(C + 15))
	assert_false(judge.miss_ruled(0, cue, WINDOW), "the presser may still press")
	judge.on_consumed(C + 26, 0, _consumed(C + 21))
	assert_true(judge.miss_ruled(0, cue, WINDOW), "an input stamped after A + window was processed")
	var other: NowJudge = NowJudge.new()
	var id: int = other.register_cue(2, NoiseTypes.Type.ENGINE_CRANK, C)
	other.on_consumed(C + 4, 2, _consumed(C, [PackedInt64Array([id, C, 0])]))
	other.on_consumed(C + 9, 2, _consumed(C, [], -1, true))
	assert_true(other.miss_ruled(2, id, WINDOW), "starved inputs rule the miss")

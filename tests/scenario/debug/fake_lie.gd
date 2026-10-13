extends SimSystem
## FND-08 test fixture, never shipped: a stand-in for CRT-10's illusion stage that, at `at_tick`,
## appends one illusion (a 'Here!' callout from a rock face) to `slot`'s stream with a fake lie-log
## id, before the frames are built.

var slot: int = -1
var at_tick: int = -1
var illusion_id: int = 77


func stage() -> int:
	return StageTable.Stage.ILLUSIONS


func order() -> int:
	return 99


func system_name() -> String:
	return "fake_lie"


func hashed() -> bool:
	return false


func tick(run: RunState) -> void:
	if run.tick != at_tick or slot < 0:
		return
	var r: AudioRecord = AudioRecord.new()
	r.type = NoiseTypes.Type.CALLOUT
	r.start_tick = run.tick
	r.apparent = Vector2(12.5, 0.5)
	r.level_np = 12.0
	r.remaining_np = 8.0
	r.voice = 2
	run.replication.append_illusion_event(slot, r.to_event(), illusion_id)

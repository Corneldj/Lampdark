class_name VoiceFacts
extends SimSystem
## SND-09: live voice as an input. Frames arrive between ticks (ServerNet services the network
## then), but what voice does to the run's state, a band's Road Graph event (VoiceNoise) and a
## speaker heard by voice (HeardTracker), must fall on ticks and replay. So each is queued as a
## fact, applied here at a fixed point (before SND-02 dispatches the tick's events), and written to
## FND-09's input log; a replay applies the logged facts and ignores the network. Taps, calls and
## callouts come from simulated actions and mark the heard directly.

## [BAND, slot, np]: a voice event at the speaker's tile.
const BAND: String = "b"
## [HEARD, slot, 0]: an utterance reached a conscious teammate.
const HEARD: String = "h"

var _pending: Array = []
var _run: RunState = null


func stage() -> int:
	return StageTable.Stage.ROAD_GRAPH


func order() -> int:
	return 7  # after SND-04's deafen (5), before SND-02's dispatch (10)


func system_name() -> String:
	return "voice_facts"


## Not state itself: what it applies is (the noise events, the heard tracker).
func hashed() -> bool:
	return false


func bind(run: RunState) -> void:
	_run = run


func add(kind: String, slot: int, arg: float) -> void:
	_pending.append([kind, slot, arg])


func tick(run: RunState) -> void:
	var facts: Array = _pending
	_pending = []
	if run.inputs != null and run.inputs.replay != null:
		facts = Variants.array(run.inputs.replay.voice_by_tick.get(run.tick, []))
	if facts.is_empty():
		return
	if run.inputs != null and run.inputs.recorder != null:
		run.inputs.recorder.append_voice(run.tick, facts)
	for raw: Variant in facts:
		var f: Array = Variants.array(raw)
		var slot: int = int(Variants.number(f[1]))
		match str(f[0]):
			BAND:
				if run.voice_noise != null:
					run.voice_noise.emit_band(slot, float(Variants.number(f[2])))
			HEARD:
				if run.heard != null:
					run.heard.mark_heard(slot, &"voice")

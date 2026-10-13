class_name CueReporter
extends RefCounted
## NET-06 on the client: a timed cue (TimedCues) is presented when the shown timeline reaches its
## start tick, or at once if it arrives late; the moment it was presented is reported up with
## the inputs, so the server judges a 'Now!' against the cue as it reached this player.

## cue_id -> start tick, waiting for the shown timeline to reach it.
var _waiting: Dictionary = {}
## [cue_id, shown_tick, fraction] presented, in order (for the audio and for tests).
var presented: Array[PackedInt64Array] = []


## An audio event arrived (once per event number).
func on_event(event: Dictionary) -> void:
	var type: int = int(Variants.number(event.get("type", 0)))
	if not TimedCues.is_timed(type):
		return
	var start: int = int(Variants.number(event.get("start_tick", 0)))
	_waiting[TimedCues.cue_id(type, start)] = start


## Each client tick, before inputs go up: present what the shown time has reached.
func poll(shown: float, sender: ClientInputSender) -> void:
	var due: Array = []
	for raw: Variant in _waiting.keys():
		if shown >= float(Variants.number(_waiting[raw])):
			due.append(raw)
	due.sort()
	for raw: Variant in due:
		var cue: int = int(Variants.number(raw))
		var start: int = int(Variants.number(_waiting[raw]))
		_waiting.erase(raw)
		# Polled each tick: within a tick of its start it was on time and shows at its own tick;
		# later than that it arrived late and shows now.
		var at: float = shown if shown - start >= 1.0 else float(start)
		var whole: int = floori(at)
		var fraction: int = clampi(floori((at - whole) * 256.0), 0, 255)
		presented.append(PackedInt64Array([cue, whole, fraction]))
		sender.report_cue(cue, whole, fraction)

class_name CalloutWheel
extends RefCounted
## SND-11: the client's side of a callout pick (Gameplay §4.8, GDD §14.5). With the band rings a pick
## goes as MNR-15 made it (the slice's angle and the ring's distance). With the timing option the
## band comes from the press itself, against this player's settings (BindingsStore): a hold of
## whisper_hold_s whispers, a tap talks, a second tap within shout_window_s shouts. A tap waits out
## the shout window before it goes, so a double tap sends one shout, never a talk and then a shout;
## each pick then goes as the middle of its band's ring, so the server reads one encoding.

var store: BindingsStore = null
## [aim, send-at seconds]: a tap waiting to see whether a second tap makes it a shout.
var _pending: Array = []


func _init(bindings: BindingsStore = null) -> void:
	store = bindings


## This tick's one-shot actions ([kind, arg, aim], InputRouter's), with callout picks settled: the
## actions to send now.
func filter(actions: Array[Array], now: float) -> Array[Array]:
	var out: Array[Array] = []
	for a: Array in actions:
		var kind: int = a[0]
		var arg: int = a[1]
		var aim: int = a[2]
		if kind != ActionRecord.Kind.CALLOUT or (arg & Intents.TIMING_FLAG) == 0:
			out.append(a)
			continue
		var pick: Dictionary = Intents.decode_wheel_arg(arg)
		var band: int = CalloutLines.band_of(pick, store.whisper_hold_s if store != null else -1.0)
		if band == CalloutLines.SHOUT:
			_pending.clear()  # the first tap becomes this shout
		if band == CalloutLines.TALK:
			_pending = [aim, now + _window()]
			continue
		out.append([kind, Intents.wheel_arg_distance(CalloutLines.ring_distance(band)), aim])
	var due: float = _pending[1] if not _pending.is_empty() else INF
	if now >= due:
		var aim: int = _pending[0]
		out.append([ActionRecord.Kind.CALLOUT, Intents.wheel_arg_distance(CalloutLines.ring_distance(CalloutLines.TALK)), aim])
		_pending.clear()
	return out


func _window() -> float:
	var w: float = store.shout_window_s if store != null else 0.0
	return w if w > 0.0 else Tuning.f(&"voice.callout_shout_window_s")

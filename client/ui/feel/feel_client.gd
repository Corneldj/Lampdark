class_name FeelClient
extends RefCounted
## VIS-07 on the client: the own miner's feel answers and wall bumps (FeelMessages), handed to
## UI-01's feel glyph (drawn beside the own miner, never at the thing), and a rumble per bump:
## vision.bump_rumble_ms on any joypad (STM-06's Steam Input haptics replace this), nothing on
## keyboard and mouse.

## The last feel answer {caption_key, bearing_q, verb_key} and the last bump {caption_key}.
var last_feel: Dictionary = {}
var last_bump: Dictionary = {}
var feels: int = 0
var bumps: int = 0
var rumbles: int = 0


func on_message(payload: PackedByteArray) -> void:
	var m: Dictionary = FeelMessages.decode(payload)
	if m.is_empty():
		return
	if int(Variants.number(m["kind"])) == FeelMessages.Kind.BUMP:
		last_bump = {"caption_key": m["caption_key"]}
		bumps += 1
		_rumble()
	else:
		last_feel = {"caption_key": m["caption_key"], "bearing_q": m["bearing_q"], "verb_key": m["verb_key"]}
		feels += 1


func _rumble() -> void:
	rumbles += 1
	var ms: float = Tuning.f(&"vision.bump_rumble_ms") if Tuning.current.has_key(&"vision.bump_rumble_ms") else 80.0
	for pad: int in Input.get_connected_joypads():
		Input.start_joy_vibration(pad, 0.6, 0.0, ms / 1000.0)

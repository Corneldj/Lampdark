class_name VoiceConditions
extends RefCounted
## SND-08: the conditions that cost voice frames, read each time routes are worked out (Gameplay
## §6.2, A.3): the speaker running or panting (MNR-02's voice-loss flag); a speaker or listener
## within voice.stythe_radius_tiles (straight line, as for the guttering) of a Stythe whose tell
## plays (Hunt, WindUp, Drag, Collect: CRT-13 supplies them; until then the stub finds none); a
## deafened listener (SND-04); and the Fan's surge (SND-16; a stub flag until then). Nothing here is
## ever sent to a client.

## CRT-13: the positions (tiles) of Stythes whose tell plays. Stub: none.
var stythe_tells: Callable = func() -> Array[Vector2]: return [] as Array[Vector2]
## SND-16: the Fan is surging (voice beyond half range is lost). Stub: never.
var fan_surge_active: bool = false
var _run: RunState = null


func bind(run: RunState) -> void:
	_run = run


func running(slot: int) -> bool:
	return _run != null and _run.movement != null and _run.movement.voice_loss_flag(slot)


func deafened(slot: int) -> bool:
	return _run != null and _run.deafen != null and _run.deafen.is_deafened(slot)


## Within the radius of a Stythe whose tell plays.
func near_stythe(at: Vector2) -> bool:
	var radius: float = Tuning.f(&"voice.stythe_radius_tiles")
	var tells: Array[Vector2] = stythe_tells.call()
	for p: Vector2 in tells:
		if p.distance_to(at) <= radius:
			return true
	return false

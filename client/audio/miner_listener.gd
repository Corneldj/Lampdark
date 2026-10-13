class_name MinerListener
extends RefCounted
## SND-04 (Gameplay §6.10): the client's ears. They sit on the own miner, at its predicted position
## (NET-05's, once the client predicts; until then the position last received) and turn with its
## facing (the router's live facing), never the camera's: squinting or aiming moves the view, not the
## ears. Each frame it sets the native mixer's pose and tells the event player where the listener is
## (diffuse emitters, caption directions). Screen-up (dev and QA only) points the ears north.

var mixer: SpatialMixer = null
var events: EventPlayer = null
var position: Vector2 = Vector2.ZERO
var facing: int = 0


func _init(spatial: SpatialMixer, event_player: EventPlayer = null) -> void:
	mixer = spatial
	events = event_player


## Every frame, from the own miner.
func follow(miner_position: Vector2, miner_facing: int) -> void:
	position = miner_position
	facing = miner_facing & 0xFFFF
	mixer.set_pose(position, facing)
	if events != null:
		events.listener = position


## The A/B listener mode: `facing` or `screen_up` (FND-08's `listener_mode`); false where screen-up
## is compiled out (release builds) or the mode is unknown.
func set_mode(mode_name: String) -> bool:
	match mode_name:
		"facing":
			return mixer.set_screen_up(false)
		"screen_up":
			return mixer.set_screen_up(true)
	return false

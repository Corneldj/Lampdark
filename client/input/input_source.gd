class_name InputSource
extends RefCounted
## MNR-15: one device family's view of the controls, read once per client tick into the frame
## InputRouter.sample takes. GodotInputSource reads Godot's Input; STM-06 adds a Steam Input source
## that fills the same frame, so gameplay code never changes; tests script frames directly.

## "kbm" or "pad".
var family: String = "kbm"


## {down: {action: bool}, now_s, move: Vector2, cursor: Vector2, own_screen: Vector2,
## face_stick: Vector2, wheel_vec: Vector2}.
func frame(_now_s: float, _store: BindingsStore) -> Dictionary:
	return {}

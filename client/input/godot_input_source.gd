class_name GodotInputSource
extends InputSource
## MNR-15: keyboard and mouse, or a Godot joypad, read through Godot's Input. Keys are physical
## positions (other layouts work unchanged); the mouse wheel arrives as events only, so `push_event`
## collects its notches for the next frame. The renderer sets `own_screen`: the own miner's screen
## position with the camera's lead taken out, so mouse facing measured from it never feeds back
## into the lead that follows it.

const AXIS_PRESSED: float = 0.5

var device: int = 0
var own_screen: Vector2 = Vector2.ZERO
var viewport: Viewport = null
## Set from InputRouter.picking(): while a wheel or the ring is open the mouse picks by its offset
## from where it stood when it opened.
var wheel_open: bool = false
var _wheel_anchor: Vector2 = Vector2.ZERO
var _pulses: Dictionary = {}


func _init(input_family: String = "kbm", view: Viewport = null) -> void:
	family = input_family
	viewport = view


## Feeds an event Input cannot poll (the mouse wheel); it reads as down for one frame.
func push_event(event: InputEvent, store: BindingsStore) -> void:
	if event.is_pressed():
		for action: String in store.action_for(event, family):
			_pulses[action] = true


## Where the mouse stood when the open wheel opened (UI-01 draws the wheel there).
func wheel_anchor() -> Vector2:
	return _wheel_anchor


func frame(now_s: float, store: BindingsStore) -> Dictionary:
	var down: Dictionary = {}
	for raw: Variant in store.bindings.keys():
		var action: String = str(raw)
		var is_down: bool = Variants.flag(_pulses.get(action, false))
		for spec_raw: Variant in store.specs(action, family):
			is_down = is_down or _spec_down(Variants.dict(spec_raw))
		down[action] = is_down
	_pulses.clear()
	var cursor: Vector2 = viewport.get_mouse_position() if viewport != null else Vector2.ZERO
	var short_side: float = 1.0
	if viewport != null:
		var size: Vector2 = viewport.get_visible_rect().size
		short_side = maxf(1.0, minf(size.x, size.y))
	var face_stick: Vector2 = Vector2(Input.get_joy_axis(device, JOY_AXIS_RIGHT_X), Input.get_joy_axis(device, JOY_AXIS_RIGHT_Y))
	# The mouse picks by its offset from where it stood when the wheel opened; the stick by deflection.
	var wheel_vec: Vector2 = face_stick
	if family == "kbm":
		if not wheel_open:
			_wheel_anchor = cursor
		wheel_vec = (cursor - _wheel_anchor) / (Tuning.f(&"ui.wheel_radius") * short_side)
	return {"down": down, "now_s": now_s, "cursor": cursor, "own_screen": own_screen,
		"move": Vector2(Input.get_joy_axis(device, JOY_AXIS_LEFT_X), Input.get_joy_axis(device, JOY_AXIS_LEFT_Y)),
		"face_stick": face_stick, "wheel_vec": wheel_vec}


## LFT-14: the pad's state for a close-up's own frame-rate input (the map table's cursor, its
## pencil and rubber triggers through the bindings, pan, and zoom on the D-pad, Proposed).
func close_up_pad(store: BindingsStore) -> Dictionary:
	return {"pencil": action_down("pencil", store, "pad"), "rubber": action_down("rubber", store, "pad"),
		"stick_r": Vector2(Input.get_joy_axis(device, JOY_AXIS_RIGHT_X), Input.get_joy_axis(device, JOY_AXIS_RIGHT_Y)),
		"stick_l": Vector2(Input.get_joy_axis(device, JOY_AXIS_LEFT_X), Input.get_joy_axis(device, JOY_AXIS_LEFT_Y)),
		"zoom_in": Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_UP),
		"zoom_out": Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_DOWN)}


## True while any of the action's bindings for `input_family` is down.
func action_down(action: String, store: BindingsStore, input_family: String) -> bool:
	for spec_raw: Variant in store.specs(action, input_family):
		if _spec_down(Variants.dict(spec_raw)):
			return true
	return false


func _spec_down(spec: Dictionary) -> bool:
	match str(spec.get("type", "")):
		"key":
			return Input.is_physical_key_pressed(int(Variants.number(spec["code"])) as Key)
		"mouse":
			return Input.is_mouse_button_pressed(int(Variants.number(spec["button"])) as MouseButton)
		"joy_button":
			return Input.is_joy_button_pressed(device, int(Variants.number(spec["button"])) as JoyButton)
		"joy_axis":
			var value: float = Input.get_joy_axis(device, int(Variants.number(spec["axis"])) as JoyAxis)
			return value * float(Variants.number(spec.get("sign", 1))) > AXIS_PRESSED
	return false

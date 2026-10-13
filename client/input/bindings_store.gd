class_name BindingsStore
extends RefCounted
## MNR-15: the action set's bindings for keyboard and mouse ("kbm") and for gamepad and Steam Deck
## ("pad"), with §4.8's defaults, every action remappable, and the bindings and input options kept
## in user://input.cfg (Proposed; STM-05 syncs it with the profile). A binding is a spec: a physical
## key (so any keyboard layout works unchanged), a mouse button, a joypad button or axis, the pointer,
## or "unbound". `mode` "tap" or "hold" marks a button shared between a tap and a hold (LB, View, A).

const PATH: String = "user://input.cfg"
const FAMILIES: Array[String] = ["kbm", "pad"]

## §4.8's rows: which actions make up each (a row has a default when any of its actions does).
const ROWS: Dictionary = {
	"move": ["move_up", "move_down", "move_left", "move_right"],
	"face": ["face"],
	"run": ["run"],
	"crouch": ["crouch"],
	"squint_or_aim": ["squint"],
	"shutter": ["shutter"],
	"wick": ["wick_up", "wick_down"],
	"set_down": ["set_down"],
	"belt_slot": ["slot_1", "slot_2", "slot_3", "slot_4", "slot_prev", "slot_next"],
	"use": ["use"],
	"interact": ["interact"],
	"feel": ["interact"],
	"relight_or_reload": ["relight"],
	"fire": ["fire"],
	"lamp_signals": ["signal_wheel"],
	"chalk": ["chalk_wheel"],
	"callouts": ["callout"],
	"tap_rock": ["tap_rock"],
	"check_lamp": ["check_lamp"],
	"pocket_book": ["pocket_book"],
	"hold_breath": ["hold_breath"],
	"push_to_talk": ["push_to_talk"],
	"aside": ["aside"],
	"close_up_open": ["close_up_open"],
	"pencil": ["pencil"],
	"rubber": ["rubber"],
	"label": ["label"],
	"turn_page": ["page_prev", "page_next"],
	"hold_out": ["hold_out"],
	"board_pick": ["board_pick"],
	"plug": ["plug"],
	"hold_line": ["hold_line"],
	"ring_line": ["ring_line"],
	"close": ["close"],
}

## Rows the design leaves unbound on a family (push-to-talk on pads).
const UNBOUND_BY_DESIGN: Dictionary = {"push_to_talk": ["pad"]}

var bindings: Dictionary = {}
## Options: hold-or-toggle per held action (default Hold), and the callout timing option.
var toggles: Dictionary = {}
## The timing option's hold to whisper and double-tap window: defaults and ranges are SND-11's
## voice.callout_whisper_hold_s and voice.callout_shout_window_s (GDD §14.5).
var callout_timing: bool = false
var whisper_hold_s: float = 0.0
var shout_window_s: float = 0.0


func _init() -> void:
	bindings = defaults()
	whisper_hold_s = _option(&"voice.callout_whisper_hold_s", NAN)
	shout_window_s = _option(&"voice.callout_shout_window_s", NAN)


## A timing option's value clamped to its tuning range (NAN: the tuning default).
static func _option(tuning_key: StringName, value: float) -> float:
	var entry: Dictionary = Variants.dict(Tuning.current.entries.get(String(tuning_key), {}))
	if entry.is_empty():
		return 0.0 if is_nan(value) else value
	if is_nan(value):
		return Variants.number(entry["value"])
	return clampf(value, Variants.number(entry.get("min", value)), Variants.number(entry.get("max", value)))


static func key(code: int) -> Dictionary:
	return {"type": "key", "code": code}


static func mouse(button: int) -> Dictionary:
	return {"type": "mouse", "button": button}


static func joy(button: int, mode: String = "") -> Dictionary:
	var d: Dictionary = {"type": "joy_button", "button": button}
	if not mode.is_empty():
		d["mode"] = mode
	return d


static func axis(a: int, sign: int) -> Dictionary:
	return {"type": "joy_axis", "axis": a, "sign": sign}


static func pointer() -> Dictionary:
	return {"type": "pointer"}


static func unbound() -> Dictionary:
	return {"type": "unbound"}


## §4.8's default bindings: action -> {kbm: [spec], pad: [spec]}.
static func defaults() -> Dictionary:
	return {
		"move_up": {"kbm": [key(KEY_W)], "pad": [axis(JOY_AXIS_LEFT_Y, -1)]},
		"move_down": {"kbm": [key(KEY_S)], "pad": [axis(JOY_AXIS_LEFT_Y, 1)]},
		"move_left": {"kbm": [key(KEY_A)], "pad": [axis(JOY_AXIS_LEFT_X, -1)]},
		"move_right": {"kbm": [key(KEY_D)], "pad": [axis(JOY_AXIS_LEFT_X, 1)]},
		"face": {"kbm": [pointer()], "pad": [axis(JOY_AXIS_RIGHT_X, 1), axis(JOY_AXIS_RIGHT_Y, 1)]},
		"run": {"kbm": [key(KEY_SHIFT)], "pad": [joy(JOY_BUTTON_LEFT_STICK)]},
		"crouch": {"kbm": [key(KEY_CTRL)], "pad": [joy(JOY_BUTTON_B)]},
		"squint": {"kbm": [mouse(MOUSE_BUTTON_RIGHT)], "pad": [axis(JOY_AXIS_TRIGGER_LEFT, 1)]},
		"shutter": {"kbm": [key(KEY_Q)], "pad": [joy(JOY_BUTTON_RIGHT_SHOULDER)]},
		"wick_up": {"kbm": [mouse(MOUSE_BUTTON_WHEEL_UP)], "pad": [joy(JOY_BUTTON_DPAD_UP)]},
		"wick_down": {"kbm": [mouse(MOUSE_BUTTON_WHEEL_DOWN)], "pad": [joy(JOY_BUTTON_DPAD_DOWN)]},
		"set_down": {"kbm": [key(KEY_X)], "pad": [joy(JOY_BUTTON_A, "tap")]},
		"slot_1": {"kbm": [key(KEY_1)], "pad": [unbound()]},
		"slot_2": {"kbm": [key(KEY_2)], "pad": [unbound()]},
		"slot_3": {"kbm": [key(KEY_3)], "pad": [unbound()]},
		"slot_4": {"kbm": [key(KEY_4)], "pad": [unbound()]},
		"slot_prev": {"kbm": [unbound()], "pad": [joy(JOY_BUTTON_DPAD_LEFT)]},
		"slot_next": {"kbm": [unbound()], "pad": [joy(JOY_BUTTON_DPAD_RIGHT)]},
		"use": {"kbm": [key(KEY_G)], "pad": [axis(JOY_AXIS_TRIGGER_RIGHT, 1)]},
		"interact": {"kbm": [key(KEY_E)], "pad": [joy(JOY_BUTTON_A, "hold")]},
		"relight": {"kbm": [key(KEY_R)], "pad": [joy(JOY_BUTTON_X)]},
		"fire": {"kbm": [mouse(MOUSE_BUTTON_LEFT)], "pad": [axis(JOY_AXIS_TRIGGER_RIGHT, 1)]},
		"signal_wheel": {"kbm": [key(KEY_F)], "pad": [joy(JOY_BUTTON_Y)]},
		"chalk_wheel": {"kbm": [key(KEY_C)], "pad": [joy(JOY_BUTTON_Y)]},
		"callout": {"kbm": [key(KEY_Z)], "pad": [joy(JOY_BUTTON_LEFT_SHOULDER, "hold")]},
		"tap_rock": {"kbm": [key(KEY_T)], "pad": [joy(JOY_BUTTON_LEFT_SHOULDER, "tap")]},
		"check_lamp": {"kbm": [key(KEY_TAB)], "pad": [joy(JOY_BUTTON_BACK, "hold")]},
		"pocket_book": {"kbm": [key(KEY_M)], "pad": [joy(JOY_BUTTON_BACK, "tap")]},
		"hold_breath": {"kbm": [key(KEY_B)], "pad": [joy(JOY_BUTTON_RIGHT_STICK)]},
		"push_to_talk": {"kbm": [key(KEY_V)], "pad": [unbound()]},
		"aside": {"kbm": [key(KEY_H)], "pad": [joy(JOY_BUTTON_PADDLE1), joy(JOY_BUTTON_PADDLE2)]},
		"close_up_open": {"kbm": [key(KEY_E)], "pad": [joy(JOY_BUTTON_A)]},
		"pencil": {"kbm": [mouse(MOUSE_BUTTON_LEFT)], "pad": [axis(JOY_AXIS_TRIGGER_RIGHT, 1)]},
		"rubber": {"kbm": [mouse(MOUSE_BUTTON_RIGHT)], "pad": [axis(JOY_AXIS_TRIGGER_LEFT, 1)]},
		"label": {"kbm": [key(KEY_ENTER)], "pad": [joy(JOY_BUTTON_A)]},
		"page_prev": {"kbm": [key(KEY_A)], "pad": [joy(JOY_BUTTON_DPAD_LEFT)]},
		"page_next": {"kbm": [key(KEY_D)], "pad": [joy(JOY_BUTTON_DPAD_RIGHT)]},
		"hold_out": {"kbm": [key(KEY_E)], "pad": [joy(JOY_BUTTON_A, "hold")]},
		"board_pick": {"kbm": [pointer()], "pad": [axis(JOY_AXIS_RIGHT_X, 1), axis(JOY_AXIS_RIGHT_Y, 1)]},
		"plug": {"kbm": [mouse(MOUSE_BUTTON_LEFT)], "pad": [joy(JOY_BUTTON_A)]},
		"hold_line": {"kbm": [mouse(MOUSE_BUTTON_RIGHT)], "pad": [joy(JOY_BUTTON_X)]},
		"ring_line": {"kbm": [key(KEY_R)], "pad": [joy(JOY_BUTTON_Y)]},
		"close": {"kbm": [key(KEY_ESCAPE)], "pad": [joy(JOY_BUTTON_B)]},
	}


func specs(action: String, family: String) -> Array:
	return Variants.array(Variants.dict(bindings.get(action, {})).get(family, []))


## True if the family has at least one real binding for the action.
func is_bound(action: String, family: String) -> bool:
	for raw: Variant in specs(action, family):
		if str(Variants.dict(raw).get("type", "")) != "unbound":
			return true
	return false


func rebind(action: String, family: String, new_specs: Array) -> void:
	var entry: Dictionary = Variants.dict(bindings.get(action, {})).duplicate()
	entry[family] = new_specs.duplicate(true)
	bindings[action] = entry


func set_toggle(action: String, on: bool) -> void:
	toggles[action] = on


func is_toggle(action: String) -> bool:
	return Variants.flag(toggles.get(action, false))


## The action a pressed InputEvent drives in a family, or "" (first match in table order).
func action_for(event: InputEvent, family: String) -> Array[String]:
	var out: Array[String] = []
	for raw: Variant in bindings.keys():
		var action: String = str(raw)
		for spec_raw: Variant in specs(action, family):
			if matches(event, Variants.dict(spec_raw)):
				out.append(action)
	return out


static func matches(event: InputEvent, spec: Dictionary) -> bool:
	match str(spec.get("type", "")):
		"key":
			return event is InputEventKey and (event as InputEventKey).physical_keycode == int(Variants.number(spec["code"]))
		"mouse":
			return event is InputEventMouseButton and (event as InputEventMouseButton).button_index == int(Variants.number(spec["button"]))
		"joy_button":
			return event is InputEventJoypadButton and (event as InputEventJoypadButton).button_index == int(Variants.number(spec["button"]))
		"joy_axis":
			return event is InputEventJoypadMotion and (event as InputEventJoypadMotion).axis == int(Variants.number(spec["axis"]))
	return false


func save(path: String = PATH) -> Error:
	var cfg: ConfigFile = ConfigFile.new()
	for raw: Variant in bindings.keys():
		cfg.set_value("bindings", str(raw), bindings[raw])
	for raw: Variant in toggles.keys():
		cfg.set_value("toggles", str(raw), toggles[raw])
	cfg.set_value("options", "callout_timing", callout_timing)
	cfg.set_value("options", "whisper_hold_s", whisper_hold_s)
	cfg.set_value("options", "shout_window_s", shout_window_s)
	return cfg.save(path)


## Loads saved bindings and options over the defaults (a missing file keeps the defaults).
func load_from(path: String = PATH) -> Error:
	var cfg: ConfigFile = ConfigFile.new()
	var err: Error = cfg.load(path)
	if err != OK:
		return err
	bindings = defaults()
	if cfg.has_section("bindings"):
		for action: String in cfg.get_section_keys("bindings"):
			bindings[action] = Variants.dict(cfg.get_value("bindings", action, {}))
	toggles = {}
	if cfg.has_section("toggles"):
		for action: String in cfg.get_section_keys("toggles"):
			toggles[action] = Variants.flag(cfg.get_value("toggles", action, false))
	callout_timing = Variants.flag(cfg.get_value("options", "callout_timing", false))
	whisper_hold_s = _option(&"voice.callout_whisper_hold_s", Variants.number(cfg.get_value("options", "whisper_hold_s", whisper_hold_s)))
	shout_window_s = _option(&"voice.callout_shout_window_s", Variants.number(cfg.get_value("options", "shout_window_s", shout_window_s)))
	return OK

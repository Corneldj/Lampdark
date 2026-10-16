class_name GlyphText
extends RefCounted
## UI-01: the label of an action's first binding for the active family (MNR-15's BindingsStore), the
## placeholder for STM-06's Steam Input glyphs: "E", "Tab", "LMB", "A", "LB", "RT".

const PAD: Dictionary = {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y", JOY_BUTTON_BACK: "View",
	JOY_BUTTON_GUIDE: "Guide", JOY_BUTTON_START: "Menu", JOY_BUTTON_LEFT_STICK: "LS", JOY_BUTTON_RIGHT_STICK: "RS",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB", JOY_BUTTON_DPAD_UP: "Up", JOY_BUTTON_DPAD_DOWN: "Down",
	JOY_BUTTON_DPAD_LEFT: "Left", JOY_BUTTON_DPAD_RIGHT: "Right", JOY_BUTTON_PADDLE1: "P1", JOY_BUTTON_PADDLE2: "P2",
	JOY_BUTTON_PADDLE3: "P3", JOY_BUTTON_PADDLE4: "P4",
}
const MOUSE: Dictionary = {MOUSE_BUTTON_LEFT: "LMB", MOUSE_BUTTON_RIGHT: "RMB", MOUSE_BUTTON_MIDDLE: "MMB",
	MOUSE_BUTTON_WHEEL_UP: "Wheel up", MOUSE_BUTTON_WHEEL_DOWN: "Wheel down"}


static func label(store: BindingsStore, action: String, family: String) -> String:
	var specs: Array = store.specs(action, family)
	return spec_label(Variants.dict(specs[0])) if not specs.is_empty() else ""


static func spec_label(spec: Dictionary) -> String:
	match str(spec.get("type", "")):
		"key":
			return OS.get_keycode_string(int(Variants.number(spec.get("code", 0))))
		"mouse":
			var b: int = int(Variants.number(spec.get("button", 0)))
			return str(MOUSE.get(b, "Mouse %d" % b))
		"joy_button":
			var j: int = int(Variants.number(spec.get("button", 0)))
			return str(PAD.get(j, "Button %d" % j))
		"joy_axis":
			var a: int = int(Variants.number(spec.get("axis", 0)))
			if a == JOY_AXIS_TRIGGER_LEFT:
				return "LT"
			if a == JOY_AXIS_TRIGGER_RIGHT:
				return "RT"
			return "LS" if a <= JOY_AXIS_LEFT_Y else "RS"
	return ""

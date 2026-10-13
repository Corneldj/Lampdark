extends RefCounted
## MNR-15 test helper: scripted device frames for InputRouter, shaped as InputSource.frame makes them.

const FRAME_S: float = 1.0 / 60.0


static func router(family: String = "kbm", store: BindingsStore = null) -> InputRouter:
	return InputRouter.new(store if store != null else BindingsStore.new(), family)


static func frame(now: float, down: Dictionary = {}, extra: Dictionary = {}) -> Dictionary:
	var f: Dictionary = {"down": down, "now_s": now, "move": Vector2.ZERO, "cursor": Vector2(INF, INF),
		"own_screen": Vector2.ZERO, "face_stick": Vector2.ZERO, "wheel_vec": Vector2.ZERO}
	f.merge(extra, true)
	return f


## What a source reports while one pad button is down: every action bound to it.
static func pad_button(store: BindingsStore, button: int) -> Dictionary:
	var out: Dictionary = {}
	for raw: Variant in store.bindings.keys():
		for spec_raw: Variant in store.specs(str(raw), "pad"):
			var spec: Dictionary = Variants.dict(spec_raw)
			if str(spec.get("type", "")) == "joy_button" and int(Variants.number(spec["button"])) == button:
				out[str(raw)] = true
	return out


## Holds `down` from `start` for `seconds` at 60 frames a second, then releases it in a final frame
## at exactly start + seconds. Returns every action sent, in order.
static func press(r: InputRouter, down: Dictionary, start: float, seconds: float, extra: Dictionary = {}) -> Array:
	var out: Array = []
	var t: float = start
	while t < start + seconds - 1e-9:
		r.sample(frame(t, down, extra))
		out.append_array(r.actions)
		t += FRAME_S
	r.sample(frame(start + seconds, {}, extra))
	out.append_array(r.actions)
	return out


static func kinds(actions: Array) -> Array[int]:
	var out: Array[int] = []
	for a: Variant in actions:
		out.append(int(Variants.number(Variants.array(a)[0])))
	return out

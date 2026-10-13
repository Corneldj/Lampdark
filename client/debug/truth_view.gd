class_name TruthView
extends CanvasLayer
## FND-08: the truth view, a dev and QA layer above the game. It draws the last truth snapshot from
## the debug lane, each layer switched separately, from its own store keyed by server ids; it never
## writes into the client's world model or darkness, so switching it off restores the exact player
## view. Flat colours (no magenta: that is the QA overlay's). Placeholder look.

const LIGHT: Color = Color(1.0, 0.85, 0.2, 0.35)
const SEEN: Color = Color(0.3, 0.9, 1.0, 0.5)
const ENTITY: Color = Color(0.4, 1.0, 0.4)
const CREATURE: Color = Color(1.0, 0.3, 0.2)
const SOUND: Color = Color(0.6, 0.6, 1.0, 0.8)
const TEXT: Color = Color(0.95, 0.95, 0.95)

## The last snapshot, as received.
var snapshot: Dictionary = {}
## Layers drawn (a subset of what the server sends).
var layers: PackedStringArray = PackedStringArray(DebugCommands.LAYERS)
var view_origin: Vector2 = Vector2.ZERO
var tile_px: float = 32.0
var _canvas: Control = null


func _ready() -> void:
	layer = 90
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_truth)
	add_child(_canvas)
	tile_px = Tuning.f(&"camera.tile_px_at_1080p")


func show_snapshot(data: Dictionary, origin: Vector2) -> void:
	snapshot = data
	view_origin = origin
	if _canvas != null:
		_canvas.queue_redraw()


func follow(origin: Vector2) -> void:
	if origin != view_origin:
		view_origin = origin
		if _canvas != null:
			_canvas.queue_redraw()


func clear() -> void:
	snapshot = {}
	if _canvas != null:
		_canvas.queue_redraw()


func _at(p: Variant) -> Vector2:
	var v: Vector2 = Vector2.ZERO
	if p is Vector2i:
		var t: Vector2i = p
		v = Vector2(t)
	elif p is Vector2:
		v = p
	return (v - view_origin) * tile_px


func _draw_truth() -> void:
	if snapshot.is_empty():
		return
	var font: Font = ThemeDB.fallback_font
	if layers.has("light") and snapshot.has("light"):
		var l: Dictionary = snapshot["light"]
		var origin: Vector2i = l["origin"]
		var size: int = int(Variants.number(l["size"]))
		var values: PackedFloat32Array = l["values"]
		for y: int in size:
			for x: int in size:
				var v: float = values[y * size + x]
				if v > 0.0:
					_canvas.draw_rect(Rect2(_at(Vector2(origin + Vector2i(x, y))), Vector2(tile_px, tile_px)), Color(LIGHT, LIGHT.a * v))
	if layers.has("vision") and snapshot.has("vision"):
		var vis: Dictionary = snapshot["vision"]
		var xs: PackedInt32Array = vis["seen_x"]
		var ys: PackedInt32Array = vis["seen_y"]
		for i: int in xs.size():
			_canvas.draw_rect(Rect2(_at(Vector2(xs[i], ys[i])), Vector2(tile_px, tile_px)), SEEN, false, 1.0)
		var from: Vector2 = _at(vis["position"])
		var half: float = deg_to_rad(float(Variants.number(vis["cone_deg"])) / 2.0)
		var facing: float = float(Variants.number(vis["facing"])) / 65536.0 * TAU
		for side: float in [-half, half]:
			_canvas.draw_line(from, from + Vector2.from_angle(facing + side) * tile_px * 12.0, SEEN, 2.0)
	if layers.has("sound"):
		for raw: Variant in Variants.array(snapshot.get("sound", [])):
			var e: Dictionary = raw
			for o: Variant in Variants.array(e["origins"]):
				var tile: Vector2i = o if o is Vector2i else Vector2i.ZERO
				var at: Vector2 = _at(Vector2(tile) + Vector2(0.5, 0.5))
				_canvas.draw_arc(at, maxf(4.0, float(Variants.number(e["reach_tiles"])) * tile_px), 0.0, TAU, 48, SOUND, 1.5)
				_canvas.draw_string(font, at, "%s %.0f np" % [e["type"], e["np"]], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, SOUND)
	if layers.has("entities"):
		for raw: Variant in Variants.array(snapshot.get("entities", [])):
			var e: Dictionary = raw
			var at: Vector2 = _at(e["position"])
			_canvas.draw_circle(at, 4.0, ENTITY)
			_canvas.draw_string(font, at + Vector2(6, -6), "%s #%d" % [e["kind"], e["id"]], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, ENTITY)
	if layers.has("creatures"):
		for raw: Variant in Variants.array(snapshot.get("creatures", [])):
			var c: Dictionary = raw
			var at: Vector2 = _at(c["position"])
			_canvas.draw_circle(at, 7.0, CREATURE, false, 2.0)
			_canvas.draw_string(font, at + Vector2(8, 12), "%s: %s%s%s" % [c["kind"], c["state"], " guard" if Variants.flag(c["guard"]) else "",
				" FROZEN" if Variants.flag(c["frozen"]) else ""], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, CREATURE)
			var target: int = int(Variants.number(c["target"]))
			for e: Variant in Variants.array(snapshot.get("entities", [])):
				if int(Variants.number(Variants.dict(e)["id"])) == target:
					_canvas.draw_line(at, _at(Variants.dict(e)["position"]), CREATURE, 1.5)
	var lines: PackedStringArray = PackedStringArray(["truth  tick %d" % int(Variants.number(snapshot.get("tick", 0)))])
	if layers.has("director") and snapshot.has("director"):
		var d: Dictionary = snapshot["director"]
		lines.append("crew %s  cap %s" % [d["crew_count"], d["active_cap"]])
		for raw: Variant in Variants.array(d["miners"]):
			var m: Dictionary = raw
			lines.append("slot %s  pull %s  intensity %s  unheard %s / %.0f s" % [m["slot"], m["pull"], m["intensity"], m["unheard_s"], m["unheard_mark_s"]])
	if layers.has("lies"):
		for raw: Variant in Variants.array(snapshot.get("lies", [])):
			var lie: Dictionary = raw
			lines.append("lie #%s to slot %s (record %s, tick %s)" % [lie["illusion_id"], lie["slot"], lie["number"], lie["tick"]])
	for i: int in lines.size():
		_canvas.draw_string(font, Vector2(16, 120 + i * 18), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, TEXT)

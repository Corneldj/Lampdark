class_name ScreenElementRegistry
extends RefCounted
## UI-01's whitelist (Gameplay §14.3, §9.1; GDD §14.3): the only things drawn over the mine. Every
## node in the in-play layers is an element of one of these types (or part of one), and each takes
## content only through a typed schema (a binding and a verb key; a caption key, a bearing and a verb
## key; a band), so free text, names, numbers, meters, clocks or objectives cannot reach the screen.
## violations() is the check: debug and test builds run it every frame (InPlayLayer.check_frame).

const META: StringName = &"screen_element"
## The registered element types. Captions and arcs are UI-03's; the edge glow and own miner VIS-06's.
## The hotbar, the pick-up notice, the status line and the key hints are the first playtest's
## standard implementations (Gameplay §14.3, Proposed).
const TYPES: Array[StringName] = [&"interaction_glyph", &"feel_glyph", &"arc", &"breath_cloud", &"check_lamp", &"wheel",
	&"aside_tag", &"caption", &"edge_glow", &"own_miner", &"hotbar", &"pickup_notice", &"status", &"hint"]
## UI-01's colours: plain and modern, and never the world's reserved amber, umber, egg-glow or
## firedamp blue (Palette.RESERVED_FOR_WORLD).
const INK: Color = Color(0.93, 0.93, 0.95)
const DIM: Color = Color(0.62, 0.64, 0.68)
const PANEL: Color = Color(0.05, 0.05, 0.06, 0.8)
const FLAME: Color = Color(1.0, 0.94, 0.74)
## The canvas (project.godot: 1920x1080, canvas_items, aspect keep) and the Steam Deck's screen. At
## 1280x800 the canvas is scaled by min(1280/1920, 800/1080) = 2/3, so 16 px there is 24 canvas px.
const CANVAS: Vector2 = Vector2(1920.0, 1080.0)
const DECK: Vector2 = Vector2(1280.0, 800.0)


static func mark(node: Node, type: StringName) -> void:
	assert(TYPES.has(type), "unregistered screen element type %s" % type)
	node.set_meta(META, type)


static func type_of(node: Node) -> StringName:
	return node.get_meta(META, &"")


## The smallest font size an element may use, in 1080p canvas pixels.
static func min_font_px() -> int:
	return ceili(Tuning.f(&"camera.ui_min_text_px_at_800p") / deck_scale() - 1e-6)


## The canvas's scale on the Deck's screen.
static func deck_scale() -> float:
	return minf(DECK.x / CANVAS.x, DECK.y / CANVAS.y)


## Every visible drawing node under `roots` that is neither a registered element nor inside one.
static func violations(roots: Array[Node]) -> Array[String]:
	var out: Array[String] = []
	for root: Node in roots:
		for child: Node in root.get_children():
			_walk(child, out)
	return out


static func _walk(node: Node, out: Array[String]) -> void:
	var item: CanvasItem = node as CanvasItem
	if item != null and not item.visible:
		return
	if TYPES.has(type_of(node)):
		return  # an element: its own parts are its business
	if item != null:
		out.append("%s (%s) is drawn in play but is no registered screen element" % [node.get_path(), node.get_class()])
		return
	for child: Node in node.get_children():
		_walk(child, out)

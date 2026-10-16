class_name WorldView
extends CanvasLayer
## VIS-05, VIS-06: the root of the mine view. The world is drawn into an offscreen viewport: VIS-06's
## light pool (the received light, blended with the predicted own lamp, in each tile's colour class,
## with Brightness and Lamp Glow on lit tiles only), then the drawn entities (faceless tokens from
## speed alone; identity sprites for identity records only). VIS-05's darkness composite then shows
## it through the drawn-tile mask, the analytic cone and the view, writing exact black everywhere
## else. After the mask: the edge glow (direction and colour only) and the own miner, always drawn,
## at vision.own_miner_min_exposure at least. Pure black means no data and nothing else; nothing
## adapts. Screen space at the 1080p base (camera.tile_px_at_1080p a tile); the view's top-left in
## tiles comes from LampCamera.view_rect, so the world here never moves with the Camera2D.

enum Mode { NORMAL = 0, BLACK = 1, COMING_ROUND = 2 }

const SHADER: Shader = preload("res://client/render/darkness/darkness_composite.gdshader")
const POOL_SHADER: Shader = preload("res://client/render/light/light_pool.gdshader")
## Grey-box surface tones under the light (coal; VIS-06's tileset replaces them).
const FLOOR_ALBEDO: Vector3 = Vector3(0.62, 0.55, 0.47)
const WALL_ALBEDO: Vector3 = Vector3(0.86, 0.78, 0.68)
const OWN_TONE: Color = Color(0.85, 0.78, 0.6)

var mode: Mode = Mode.NORMAL
## UI-06's exposure options, on lit tiles only (VIS-06); bloom is a stand-in until a bloom pass exists.
var brightness: float = 1.0
var lamp_glow: float = 0.0
var bloom: float = 0.0
var flash: FlashReduction = FlashReduction.new()
var world: SubViewport = null
var composite: TextureRect = null
var light: LightTexture = LightTexture.new()
var tokens: TokenRenderer = TokenRenderer.new()
var _pool: ColorRect = null
var _pool_material: ShaderMaterial = null
var _entities: _EntityLayer = null
## VIS-09's tells, in the world viewport so VIS-05's mask has the last word on black.
var shadows: ShadowLayer = null
## VIS-10: blood trails on the floor and the egg-glow's hatch pulse.
var trails: TrailDecal = null
## MNR-10: chalk marks, seen at 0.30.
var chalk: ChalkDecal = null
var egg_glow: EggGlowView = null
var dust: DustHaze = null
var puffs: WallPuffs = null
var _over: _OverLayer = null
## VIS-06: what the own miner holds (ClientConnection.inventory), whether its flame shows (the own
## light's radius above 0) and the flame's states (FlameFlags): drawn on it, as identity sprites show
## what other miners hold. Empty while watching another miner.
var own_hands: Dictionary = {}
var own_lit: bool = false
var own_flame: int = 0
## SND-06: the own voice's breath-cloud, over the dark like the own miner.
var breath: BreathCloud = null
var _over_canvas: CanvasLayer = null
var _material: ShaderMaterial = null
var _mask: ImageTexture = null
var _light_tex: ImageTexture = null


func _init() -> void:
	layer = 0
	var base: Vector2 = ViewFit.base_px()
	world = SubViewport.new()
	world.size = Vector2i(roundi(base.x), roundi(base.y))
	world.transparent_bg = false
	world.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	world.disable_3d = true
	add_child(world)
	_pool_material = ShaderMaterial.new()
	_pool_material.shader = POOL_SHADER
	var colours: PackedVector3Array = PackedVector3Array()
	for i: int in 8:
		var c: Color = Palette.class_colour(i)
		colours.append(Vector3(c.r, c.g, c.b))
	_pool_material.set_shader_parameter("class_colours", colours)
	_pool_material.set_shader_parameter("floor_albedo", FLOOR_ALBEDO)
	_pool_material.set_shader_parameter("wall_albedo", WALL_ALBEDO)
	_pool = ColorRect.new()
	_pool.size = base
	_pool.material = _pool_material
	world.add_child(_pool)
	trails = TrailDecal.new()
	world.add_child(trails)
	chalk = ChalkDecal.new()
	world.add_child(chalk)
	shadows = ShadowLayer.new()
	world.add_child(shadows)
	egg_glow = EggGlowView.new()
	world.add_child(egg_glow)
	_entities = _EntityLayer.new()
	world.add_child(_entities)
	dust = DustHaze.new()
	world.add_child(dust)
	puffs = WallPuffs.new()
	world.add_child(puffs)
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	composite = TextureRect.new()
	composite.texture = world.get_texture()
	composite.size = base
	composite.stretch_mode = TextureRect.STRETCH_SCALE
	composite.material = _material
	add_child(composite)
	_over_canvas = CanvasLayer.new()
	_over_canvas.layer = 1
	add_child(_over_canvas)
	_over = _OverLayer.new()
	ScreenElementRegistry.mark(_over, &"edge_glow")  # UI-01: the edge glow and the own miner
	_over_canvas.add_child(_over)
	breath = BreathCloud.new()
	ScreenElementRegistry.mark(breath, &"breath_cloud")
	_over_canvas.add_child(breath)


## UI-01: the overlay layer drawn over the mine (its elements are checked against the whitelist).
func overlay_layer() -> CanvasLayer:
	return _over_canvas


## Shows or hides the whole mine view, overlay included. ClientMain keeps it hidden until the first
## frame from a server arrives, so the menus before it are not drawn over in black.
func set_shown(on: bool) -> void:
	visible = on
	_over_canvas.visible = on


## NORMAL; BLACK (RSC-04's Dark: nothing drawn, the own miner hidden); COMING_ROUND (the server
## already clamps what it sends to 4 tiles, VIS-03: drawn as normal).
func set_view_mode(m: Mode) -> void:
	mode = m


## One frame. `lights`: OwnLampBlend's {tile: light} (empty: the drawn set's own values); `now_s` the
## frame time (token phases and flash reduction).
func show_frame(drawn: DrawnSet, view: ReceivedView, view_origin: Vector2, miner: Vector2, facing: int, own_light: float,
		lights: Dictionary = {}, now_s: float = 0.0) -> void:
	var tile_px: float = Tuning.f(&"camera.tile_px_at_1080p")
	var size_tiles: Vector2 = ViewGeometry.view_size()
	var black: bool = mode == Mode.BLACK
	var shown: DrawnSet = drawn if not black else null
	var values: Dictionary = lights
	if values.is_empty() and shown != null:
		for raw: Variant in shown.tiles.keys():
			values[raw] = Variants.dict(shown.tiles[raw])["light"]
	values = flash.filter(values, now_s)
	light.build(shown, values, view_origin, size_tiles)
	_set_texture(light.image)
	_pool_material.set_shader_parameter("tex_origin", Vector2(light.origin))
	_pool_material.set_shader_parameter("tex_size", Vector2(light.size))
	_pool_material.set_shader_parameter("view_origin", view_origin)
	_pool_material.set_shader_parameter("view_size", size_tiles)
	_pool_material.set_shader_parameter("brightness", brightness)
	_pool_material.set_shader_parameter("lamp_glow", lamp_glow)
	_pool_material.set_shader_parameter("max_channel", flash.max_channel())
	trails.set_frame(shown, view, view_origin, tile_px)
	chalk.set_frame(shown, view, view_origin, tile_px)
	shadows.set_frame(shown, view, view_origin, tile_px)
	egg_glow.set_frame(shown, view_origin, tile_px, now_s)
	_entities.set_frame(shown, view, view_origin, tile_px, tokens, now_s)
	dust.set_frame(shown, view, view_origin, tile_px, now_s)
	puffs.set_frame(view_origin, tile_px, now_s)
	_update_mask(shown, view_origin, size_tiles)
	var f: Vector2 = ViewGeometry.facing_vector(facing)
	_material.set_shader_parameter("view_origin", view_origin)
	_material.set_shader_parameter("view_size", size_tiles)
	_material.set_shader_parameter("miner", miner)
	_material.set_shader_parameter("facing_dir", f)
	_material.set_shader_parameter("cos_half", LbDetMath.cos_deg(Tuning.f(&"vision.cone_deg") * 0.5))
	_material.set_shader_parameter("floor_level", Tuning.f(&"vision.min_drawn_level") / 255.0)
	_material.set_shader_parameter("bloom", bloom)
	_material.set_shader_parameter("black_mode", black)
	var exposure: float = maxf(own_light, Tuning.f(&"vision.own_miner_min_exposure"))
	var marks: Array[Dictionary] = []
	if not black and view != null:
		var rect: Rect2 = Rect2(view_origin, size_tiles)
		var off: Dictionary = {}
		for raw: Variant in shown.tiles.keys():
			var t: Vector2i = raw
			if not rect.has_point(Vector2(t) + Vector2(0.5, 0.5)):
				off[t] = int(Variants.number(Variants.dict(shown.tiles[raw]).get("colour", 1)))
		marks = EdgeGlow.layout(rect, miner, facing, view.glow_mask, view.glow_colour, off)
	_over.set_frame(not black, (miner - view_origin) * tile_px, f, exposure, tile_px, marks, view_origin)
	_over.set_hands(own_hands, own_lit, own_flame, now_s)
	breath.set_frame(not black, (miner - view_origin) * tile_px, f, tile_px, now_s)


func _set_texture(img: Image) -> void:
	if _light_tex == null or _light_tex.get_size() != Vector2(img.get_size()):
		_light_tex = ImageTexture.create_from_image(img)
	else:
		_light_tex.update(img)
	_pool_material.set_shader_parameter("light_tex", _light_tex)


## The mask: one texel per tile of the view (plus a tile of slack each side), 255 where drawn.
func _update_mask(drawn: DrawnSet, view_origin: Vector2, size_tiles: Vector2) -> void:
	var origin: Vector2i = Vector2i(floori(view_origin.x) - 1, floori(view_origin.y) - 1)
	var w: int = ceili(size_tiles.x) + 3
	var h: int = ceili(size_tiles.y) + 3
	var img: Image = Image.create_empty(w, h, false, Image.FORMAT_L8)
	img.fill(Color(0, 0, 0))
	if drawn != null:
		for raw: Variant in drawn.tiles.keys():
			var t: Vector2i = raw
			var p: Vector2i = t - origin
			if p.x >= 0 and p.y >= 0 and p.x < w and p.y < h:
				img.set_pixel(p.x, p.y, Color(1, 1, 1))
	if _mask == null or _mask.get_size() != Vector2(w, h):
		_mask = ImageTexture.create_from_image(img)
	else:
		_mask.update(img)
	_material.set_shader_parameter("mask", _mask)
	_material.set_shader_parameter("mask_origin", Vector2(origin))
	_material.set_shader_parameter("mask_size", Vector2(w, h))


## The drawn entities, before the mask: tokens by size class and speed; identities by kind.
class _EntityLayer:
	extends Node2D
	var _drawn: DrawnSet = null
	var _view: ReceivedView = null
	var _origin: Vector2 = Vector2.ZERO
	var _px: float = 64.0
	var _t: float = 0.0
	var _frames: Dictionary = {}

	func set_frame(drawn: DrawnSet, view: ReceivedView, origin: Vector2, px: float, tokens: TokenRenderer, t: float) -> void:
		_drawn = drawn
		_view = view
		_origin = origin
		_px = px
		_t = t
		var positions: Dictionary = {}
		if drawn != null and view != null:
			for token: int in drawn.entities:
				var e: Dictionary = Variants.dict(view.entities.get(token, {}))
				if not e.is_empty() and int(Variants.number(e["level"])) != 2:
					positions[token] = e["position"]
		_frames = tokens.update(positions)
		queue_redraw()

	func _draw() -> void:
		if _drawn == null or _view == null:
			return
		for token: int in _drawn.entities:
			var e: Dictionary = Variants.dict(_view.entities.get(token, {}))
			if e.is_empty():
				continue
			var p: Vector2 = e["position"]
			var at: Vector2 = (p - _origin) * _px
			if int(Variants.number(e["level"])) == 2:
				EntityRenderer.draw(self, e, at, _px, _t)
			else:
				var poly: PackedVector2Array = TokenRenderer.shape(int(Variants.number(e["size_or_kind"])), int(Variants.number(_frames.get(token, 0))))
				var placed: PackedVector2Array = PackedVector2Array()
				for q: Vector2 in poly:
					placed.append(at + q * _px)
				draw_colored_polygon(placed, EntityRenderer.BODY)


## After the mask: the edge glow strips and the own miner, facing marked.
class _OverLayer:
	extends Node2D
	var _show: bool = true
	var _at: Vector2 = Vector2.ZERO
	var _facing: Vector2 = Vector2.RIGHT
	var _exposure: float = 1.0
	var _px: float = 64.0
	var _marks: Array[Dictionary] = []
	var _origin: Vector2 = Vector2.ZERO
	var _hands: Dictionary = {}
	var _lit: bool = false
	var _flame: int = 0
	var _t: float = 0.0

	func set_hands(hands: Dictionary, lit: bool, flame: int, t: float) -> void:
		_hands = hands
		_lit = lit
		_flame = flame
		_t = t
		queue_redraw()

	func set_frame(show_it: bool, at_px: Vector2, facing: Vector2, exposure: float, px: float, marks: Array[Dictionary], origin: Vector2) -> void:
		_show = show_it
		_at = at_px
		_facing = facing
		_exposure = clampf(exposure, 0.0, 1.0)
		_px = px
		_marks = marks
		_origin = origin
		queue_redraw()

	func _draw() -> void:
		if not _show:
			return
		var depth: float = Tuning.f(&"light.edge_glow_strip_tiles") * _px
		var size: Vector2 = ViewGeometry.view_size() * _px
		for m: Dictionary in _marks:
			var mark_at: Vector2 = m["at"]
			var at: Vector2 = (mark_at - _origin) * _px
			var c: Color = Palette.class_colour(int(Variants.number(m["colour"])))
			c.a = 0.55
			var r: Rect2
			match int(Variants.number(m["side"])):
				0:
					r = Rect2(Vector2(at.x - _px * 0.5, 0.0), Vector2(_px, depth))
				1:
					r = Rect2(Vector2(size.x - depth, at.y - _px * 0.5), Vector2(depth, _px))
				2:
					r = Rect2(Vector2(at.x - _px * 0.5, size.y - depth), Vector2(_px, depth))
				_:
					r = Rect2(Vector2(0.0, at.y - _px * 0.5), Vector2(depth, _px))
			draw_rect(r, c)
		var c: Color = Color(OWN_TONE.r * _exposure, OWN_TONE.g * _exposure, OWN_TONE.b * _exposure)
		draw_circle(_at, _px * 0.32, c)
		var side: Vector2 = Vector2(-_facing.y, _facing.x)
		draw_colored_polygon(PackedVector2Array([_at + _facing * _px * 0.5, _at + side * _px * 0.18, _at - side * _px * 0.18]), c)
		_draw_held(c, side)

	## The lamp in the lamp hand, forward on the left (small at the hip when on the belt hook), its
	## flame when lit; whatever is in the free hand, forward on the right.
	func _draw_held(c: Color, side: Vector2) -> void:
		var lamp: Array = Variants.array(_hands.get("lamp", [0, 0]))
		var lamp_kind: int = int(Variants.number(lamp[0])) if not lamp.is_empty() else 0
		var edge: Color = c.darkened(0.55)
		if lamp_kind != 0:
			var hooked: bool = Variants.flag(_hands.get("hooked", false))
			var at: Vector2 = _at + (_facing * 0.28 - side * 0.42) * _px if not hooked else _at + (-_facing * 0.12 - side * 0.34) * _px
			var s: float = (0.24 if not hooked else 0.16) * _px
			var body: Rect2 = Rect2(at - Vector2(s * 0.35, s * 0.5), Vector2(s * 0.7, s))
			draw_rect(body, edge, true)
			draw_rect(body.grow(-s * 0.12), c.darkened(0.25), true)
			draw_arc(at - Vector2(0.0, s * 0.5), s * 0.25, PI, TAU, 8, edge, maxf(1.5, s * 0.08))
			if _lit and lamp_kind != ItemKinds.Kind.ELECTRIC_LAMP:
				FlameSprite.draw(self, at, _px, lamp_kind, _flame & FlameFlags.ALL, _t)
			elif _lit:
				draw_circle(at, s * 0.25, Palette.CHALK_WHITE)
		var free: Array = Variants.array(_hands.get("free", [0, 0]))
		if not free.is_empty() and int(Variants.number(free[0])) != 0:
			var at_free: Vector2 = _at + (_facing * 0.28 + side * 0.42) * _px
			draw_rect(Rect2(at_free - Vector2(0.09, 0.09) * _px, Vector2(0.18, 0.18) * _px), edge, true)
			draw_rect(Rect2(at_free - Vector2(0.06, 0.06) * _px, Vector2(0.12, 0.12) * _px), c.darkened(0.15), true)

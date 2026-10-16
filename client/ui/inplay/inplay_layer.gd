class_name InPlayLayer
extends CanvasLayer
## UI-01's in-play UI layer (Gameplay §14.3, §9.1; GDD §14.3): nothing persistent, only the design's
## private elements, each shown while its rule holds: the interaction glyph, the feel glyph and its
## arc, Check Lamp, the wheels (callouts or the job page, lamp signals, chalk, and the interact ring),
## and the Aside tag. The breath-cloud and the edge glow are drawn by WorldView's overlay (SND-06,
## VIS-06) and registered alike; captions are UI-03's. Debug and test builds check every frame that
## nothing unregistered is drawn here or in WorldView's overlay (check_frame).

const LAYER: int = 5

var glyph: InteractionGlyph = InteractionGlyph.new()
var feel: FeelGlyph = FeelGlyph.new()
var check_lamp: CheckLampOverlay = CheckLampOverlay.new()
var wheel: WheelWidget = WheelWidget.new()
var ring: WheelWidget = WheelWidget.new()
var aside: AsideTag = AsideTag.new()
## UI-06's streamer mode: the Aside tag shows only with it on.
var streamer_mode: bool = false
## The last check's violations (debug and test builds).
var violations: Array[String] = []
## The glyph's target this frame: {token, verb_key, position} or {}.
var target: Dictionary = {}
## The hold cue: when interact was pressed on the target shown, and that target's token.
var _hold_since: float = -1.0
var _hold_token: int = -1
var _was_holding: bool = false


func _init() -> void:
	layer = LAYER
	name = "InPlay"
	for element: Node in [check_lamp, glyph, feel.arc, feel, wheel, ring, aside]:
		add_child(element)


## One frame. `frame`: {view (ReceivedView), view_origin (tiles), black (the Dark), inventory, feel
## (FeelClient), router (InputRouter), store (BindingsStore), wheel_anchor (screen px), short_side
## (px), now_s}.
func update(frame: Dictionary) -> void:
	var view: ReceivedView = frame.get("view", null)
	var router: InputRouter = frame.get("router", null)
	var black: bool = Variants.flag(frame.get("black", false))
	var origin: Vector2 = frame.get("view_origin", Vector2.ZERO)
	var tile_px: float = Tuning.f(&"camera.tile_px_at_1080p")
	var now_s: float = float(Variants.number(frame.get("now_s", 0.0)))
	var own: Vector2 = view.own.get("position", Vector2.ZERO) if view != null else Vector2.ZERO
	var own_px: Vector2 = (own - origin) * tile_px
	# The interaction glyph: an identified thing in touch range with a verb.
	target = {} if black or router == null or router.picking() else InteractionGlyph.pick(view, Tuning.f(&"vision.touch_range_tiles"))
	if router != null:
		router.target_in_reach = not target.is_empty()
	var store: BindingsStore = frame.get("store", null)
	var key: String = GlyphText.label(store, "interact", router.family) if store != null and router != null else ""
	var at: Variant = null
	if not target.is_empty():
		var p: Vector2 = target["position"]
		at = (p - origin) * tile_px
	# The hold cue: interact pressed afresh on this target (as the server needs) and held on it.
	var holding: bool = router != null and (router.record.holds & InputRecord.HOLD_INTERACT) != 0
	var token: int = int(Variants.number(target.get("token", -1)))
	if not holding:
		_hold_since = -1.0
		_hold_token = -1
	elif not _was_holding and not target.is_empty():
		_hold_since = now_s
		_hold_token = token
	elif token != _hold_token:
		_hold_since = -1.0
		_hold_token = -1
	_was_holding = holding
	glyph.show_on(at, key, str(target.get("verb_key", "")), now_s - _hold_since if _hold_since >= 0.0 else 0.0)
	var felt: FeelClient = frame.get("feel", null)
	feel.update(felt, own_px, tile_px, now_s)
	if black:
		feel.visible = false
		feel.arc.visible = false
	var inventory: Dictionary = Variants.dict(frame.get("inventory", {}))
	var held: bool = router != null and (router.record.holds & InputRecord.HOLD_CHECK_LAMP) != 0
	check_lamp.update(held and not black, inventory, int(Variants.number(view.own.get("flame", 0))) if view != null else 0,
		store, router.family if router != null else "kbm")
	var anchor: Vector2 = frame.get("wheel_anchor", own_px)
	var short_side: float = float(Variants.number(frame.get("short_side", 1080.0)))
	var open_wheel: bool = router != null and router.context == InputContexts.Context.WHEEL
	var kind: String = _wheel_kind(router) if open_wheel else ""
	var coming_round: bool = router != null and router.coming_round
	wheel.show_wheel(open_wheel and not black, anchor, WheelWidget.slices_for(kind, router.wheel.job_page if router != null else false,
		coming_round), kind == "callout" and not router.wheel.job_page and not coming_round,
		router.wheel.vec if router != null else Vector2.ZERO, short_side)
	var ring_keys: Array[String] = []
	if router != null:
		for option: String in router.ring_options:
			ring_keys.append("ring.%s" % option.get_slice(":", 0))
	ring.show_wheel(not ring_keys.is_empty() and not open_wheel and not black, anchor, ring_keys, false,
		router.ring_wheel.vec if router != null else Vector2.ZERO, short_side)
	aside.update(router != null and router.aside_held, streamer_mode)


## The breath-cloud's band (Gameplay §6.2, §6.5): the band the own voice frames carry, which is the
## band the server applies (SND-07), only while they are sent (push-to-talk released or Mute: none);
## speaking in the Aside shows the whisper wisp.
static func breath_band(band: int, sending: bool, voice_enabled: bool, aside_held: bool) -> int:
	if not sending or not voice_enabled:
		return VoiceBands.Band.SILENT
	return VoiceBands.Band.WHISPER if aside_held else band


static func _wheel_kind(router: InputRouter) -> String:
	match router.wheel.kind:
		ActionRecord.Kind.CALLOUT:
			return "callout"
		ActionRecord.Kind.LAMP_SIGNAL:
			return "combined" if router.wheel.combined else "signal"
		ActionRecord.Kind.CHALK:
			return "chalk"
	return ""


## Debug and test builds: every drawn node in play is a registered element. `extra`: other in-play
## layers (WorldView's overlay).
func check_frame(extra: Array[Node] = []) -> Array[String]:
	var roots: Array[Node] = [self]
	roots.append_array(extra)
	violations = ScreenElementRegistry.violations(roots)
	return violations

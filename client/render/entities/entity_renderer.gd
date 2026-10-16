class_name EntityRenderer
extends RefCounted
## VIS-06: identity sprites (grey-box placeholders until art), drawn only for identity records
## (level 2): miners with their cap badge (colour and engraved pattern), facing and what is in their
## hands; the faceless Stythe; the moth (asleep, a heap's shape); the tapper's arm; Bess; items,
## traps, phones and fixtures; coat heaps; a gate's lever. A token (level 1) is TokenRenderer's and never shows any
## of this.

const BODY: Color = Color(0.46, 0.42, 0.38)
const DARK: Color = Color(0.22, 0.2, 0.18)


static func draw(ci: CanvasItem, e: Dictionary, at_px: Vector2, px: float, t: float) -> void:
	var kind: int = int(Variants.number(e.get("size_or_kind", 0)))
	var facing: Vector2 = ViewGeometry.facing_vector(int(Variants.number(e.get("facing", 0))))
	match kind:
		SeenKind.Kind.MINER:
			_miner(ci, e, at_px, px, facing, t)
		SeenKind.Kind.STYTHE:
			ci.draw_rect(Rect2(at_px - Vector2(0.18, 0.5) * px, Vector2(0.36, 1.0) * px), DARK)
		SeenKind.Kind.MOTH:
			ci.draw_circle(at_px, 0.5 * px, BODY)
			ci.draw_circle(at_px + facing * 0.2 * px, 0.12 * px, Palette.CHALK_WHITE.darkened(0.3))
		SeenKind.Kind.COAT_HEAP:
			ci.draw_circle(at_px, 0.5 * px, BODY)
		SeenKind.Kind.TAPPER:
			ci.draw_line(at_px, at_px + facing * 0.6 * px, DARK, 0.12 * px)
		SeenKind.Kind.BESS:
			ci.draw_rect(Rect2(at_px - Vector2(0.6, 0.3) * px, Vector2(1.2, 0.6) * px), BODY)
		SeenKind.Kind.LEVER:
			# A lever box on the wall and its handle, raised: a grey-box sign of something to work.
			ci.draw_rect(Rect2(at_px - Vector2(0.18, 0.12) * px, Vector2(0.36, 0.24) * px), DARK)
			ci.draw_line(at_px, at_px + Vector2(0.14, -0.36) * px, BODY, 0.09 * px)
			ci.draw_circle(at_px + Vector2(0.14, -0.36) * px, 0.08 * px, Palette.CHALK_WHITE.darkened(0.3))
		_:
			ci.draw_rect(Rect2(at_px - Vector2(0.15, 0.15) * px, Vector2(0.3, 0.3) * px), BODY)
			_held_flame(ci, e, at_px, px, t)


static func _miner(ci: CanvasItem, e: Dictionary, at: Vector2, px: float, facing: Vector2, t: float) -> void:
	ci.draw_circle(at, 0.32 * px, BODY)
	var side: Vector2 = Vector2(-facing.y, facing.x)
	ci.draw_colored_polygon(PackedVector2Array([at + facing * 0.45 * px, at + side * 0.16 * px, at - side * 0.16 * px]), BODY)
	var badge: int = MinerCues.badge_of(int(Variants.number(e.get("cues", 0))))
	if badge < Palette.BADGE_COLOURS.size():
		draw_badge(ci, at, px, badge)
	_held_flame(ci, e, at + facing * 0.3 * px, px, t)


## A cap badge: a glass disc in its colour, engraved with its pattern in the disc's own darker tone.
static func draw_badge(ci: CanvasItem, at: Vector2, px: float, badge: int) -> void:
	var r: float = 0.14 * px
	var c: Color = Palette.BADGE_COLOURS[badge]
	var ink: Color = c.darkened(0.6)
	var w: float = maxf(2.0, 0.035 * px)
	ci.draw_circle(at, r, c)
	match Palette.BADGE_PATTERNS[badge]:
		"cross":
			ci.draw_line(at - Vector2(r * 0.75, 0), at + Vector2(r * 0.75, 0), ink, w)
			ci.draw_line(at - Vector2(0, r * 0.75), at + Vector2(0, r * 0.75), ink, w)
		"bar":
			ci.draw_line(at - Vector2(r * 0.75, 0), at + Vector2(r * 0.75, 0), ink, w * 1.6)
		"dot":
			ci.draw_circle(at, r * 0.32, ink)
		"chevron":
			ci.draw_polyline(PackedVector2Array([at + Vector2(-r * 0.7, r * 0.3), at + Vector2(0, -r * 0.4), at + Vector2(r * 0.7, r * 0.3)]), ink, w)
		"ring":
			ci.draw_arc(at, r * 0.6, 0.0, TAU, 20, ink, w)


## The lamp-hand flame when its flame shows (the lit bit), reshaped by its states (VIS-08).
static func _held_flame(ci: CanvasItem, e: Dictionary, at: Vector2, px: float, t: float) -> void:
	var held: int = int(Variants.number(e.get("in_hand", 0)))
	var kind: int = held & 0x3F
	if (held & ItemKinds.LAMP_LIT_BIT) == 0 or not (ItemKinds.is_lamp(kind) or kind == ItemKinds.Kind.CANDLE):
		return
	# SND-12: bits 5-7 are a lamp signal under way; the rest are the flame's states (VIS-08).
	var bits: int = int(Variants.number(e.get("flame", 0)))
	var moved: Vector2 = at + LampSignalAnim.offset(LampSignalKind.of_flame(bits), t, px)
	FlameSprite.draw(ci, moved, px, kind, bits & FlameFlags.ALL, t)

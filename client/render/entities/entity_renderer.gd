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
			# Its arm out of the wall (the record sits 0.75 tiles from the face, facing out): a jointed
			# limb of coal and bone, five nails at the tip.
			var root: Vector2 = at_px - facing * 0.7 * px
			var side: Vector2 = Vector2(-facing.y, facing.x)
			var joint: Vector2 = at_px - facing * 0.15 * px + side * 0.08 * px
			var tip: Vector2 = at_px + facing * 0.35 * px
			var bone: Color = Palette.CHALK_WHITE.darkened(0.45)
			ci.draw_line(root, joint, DARK, 0.2 * px)
			ci.draw_line(joint, tip, DARK, 0.16 * px)
			ci.draw_line(root, joint, bone, 0.06 * px)
			ci.draw_line(joint, tip, bone, 0.05 * px)
			ci.draw_circle(joint, 0.09 * px, bone)
			for i: int in 5:
				var spread: float = (i - 2) * 0.07
				ci.draw_line(tip, tip + (facing * 0.16 + side * spread) * px, bone.lightened(0.2), maxf(1.5, 0.025 * px))
		SeenKind.Kind.BESS:
			ci.draw_rect(Rect2(at_px - Vector2(0.6, 0.3) * px, Vector2(1.2, 0.6) * px), BODY)
		SeenKind.Kind.LEVER:
			# A lever box on the wall and its handle, raised: a grey-box sign of something to work.
			ci.draw_rect(Rect2(at_px - Vector2(0.18, 0.12) * px, Vector2(0.36, 0.24) * px), DARK)
			ci.draw_line(at_px, at_px + Vector2(0.14, -0.36) * px, BODY, 0.09 * px)
			ci.draw_circle(at_px + Vector2(0.14, -0.36) * px, 0.08 * px, Palette.CHALK_WHITE.darkened(0.3))
		SeenKind.Kind.FIXTURE:
			draw_fixture(ci, int(Variants.number(e.get("in_hand", 0))), at_px, px, t)
		SeenKind.Kind.ITEM:
			# Its kind rides in the held field (replication's lying things): a grey-box shape per kind.
			var held: int = int(Variants.number(e.get("in_hand", 0)))
			if ItemKinds.is_load(held & 0x3F):
				draw_load(ci, held, at_px, px, facing)
			else:
				draw_item(ci, held & 0x3F, at_px, px)
			_held_flame(ci, e, at_px, px, t)
		_:
			ci.draw_rect(Rect2(at_px - Vector2(0.15, 0.15) * px, Vector2(0.3, 0.3) * px), BODY)
			_held_flame(ci, e, at_px, px, t)


## A fixture by the kind in its held field: LFT-06's paraffin tank, its sight glass marked once a can
## of capacity with the paraffin's line (a glass to read up close, never a meter); LFT-08's engine:
## the prime's pump, the throttle's lever, and the crank's wheel on the engine block, still when
## cold, shuddering at the top of a stroke, its flywheel turning when it runs.
static func draw_fixture(ci: CanvasItem, held: int, at: Vector2, px: float, t: float = 0.0) -> void:
	var w: float = maxf(1.5, 0.05 * px)
	match FixtureKinds.kind_of(held):
		FixtureKinds.Kind.ENGINE_PRIME:
			ci.draw_rect(Rect2(at - Vector2(0.12, 0.25) * px, Vector2(0.24, 0.5) * px), DARK)
			ci.draw_line(at - Vector2(0.0, 0.25) * px, at - Vector2(0.0, 0.42) * px, BODY, w * 1.6)
		FixtureKinds.Kind.ENGINE_THROTTLE:
			ci.draw_rect(Rect2(at - Vector2(0.15, 0.1) * px, Vector2(0.3, 0.2) * px), DARK)
			ci.draw_line(at, at + Vector2(0.18, -0.3) * px, BODY, w * 1.6)
		FixtureKinds.Kind.ENGINE_CRANK:
			var look: FixtureKinds.Look = FixtureKinds.look_of(held)
			var shake: Vector2 = Vector2(sin(t * 47.0), cos(t * 53.0)) * 0.03 * px if look == FixtureKinds.Look.SHUDDER else Vector2.ZERO
			var block: Vector2 = at + shake
			ci.draw_rect(Rect2(block - Vector2(0.42, 0.32) * px, Vector2(0.84, 0.64) * px), DARK)
			var spin: float = t * TAU * 1.5 if look == FixtureKinds.Look.RUNNING else 0.0
			ci.draw_arc(block, 0.22 * px, 0.0, TAU, 18, BODY, w * 1.4)
			ci.draw_line(block, block + Vector2.from_angle(spin) * 0.22 * px, BODY, w * 1.4)
		FixtureKinds.Kind.TANK_GLASS:
			var glass: Dictionary = FixtureKinds.read_tank_glass(held)
			var cans: int = maxi(1, int(Variants.number(glass["cans"])))
			var fills: int = int(Variants.number(glass["fills"]))
			ci.draw_rect(Rect2(at - Vector2(0.4, 0.35) * px, Vector2(0.8, 0.7) * px), DARK)
			var tube: Rect2 = Rect2(at + Vector2(0.18, -0.3) * px, Vector2(0.12, 0.6) * px)
			ci.draw_rect(tube, Palette.CHALK_WHITE.darkened(0.6))
			var share: float = clampf(float(fills) / float(cans * 4), 0.0, 1.0)
			ci.draw_rect(Rect2(tube.position + Vector2(0.0, tube.size.y * (1.0 - share)), Vector2(tube.size.x, tube.size.y * share)),
				Color(0.62, 0.52, 0.28))
			for k: int in range(1, cans + 1):
				var y: float = tube.end.y - tube.size.y * k / cans
				ci.draw_line(Vector2(tube.position.x - 0.03 * px, y), Vector2(tube.position.x, y), Palette.CHALK_WHITE.darkened(0.3),
					maxf(1.0, 0.02 * px))
		_:
			ci.draw_rect(Rect2(at - Vector2(0.15, 0.15) * px, Vector2(0.3, 0.3) * px), BODY)


## MNR-14's loads at their heading: a 2-tile stretcher (two poles and its canvas), the drum gear
## (a toothed wheel on its 1.5-tile carrying bar) and a tub (a box on the rails, its cans as discs).
static func draw_load(ci: CanvasItem, held: int, at: Vector2, px: float, facing: Vector2) -> void:
	var along: Vector2 = facing * px
	var side: Vector2 = Vector2(-facing.y, facing.x) * px
	var w: float = maxf(1.5, 0.06 * px)
	match held & 0x3F:
		ItemKinds.Kind.STRETCHER:
			ci.draw_colored_polygon(PackedVector2Array([at + along * 0.8 + side * 0.24, at + along * 0.8 - side * 0.24,
				at - along * 0.8 - side * 0.24, at - along * 0.8 + side * 0.24]), BODY)
			for s: float in [0.28, -0.28]:
				ci.draw_line(at + along + side * s, at - along + side * s, DARK, w * 1.6)
		ItemKinds.Kind.DRUM_GEAR:
			ci.draw_line(at + along * 0.75, at - along * 0.75, DARK, w * 1.8)
			for i: int in 20:
				var a: float = TAU * i / 20.0
				ci.draw_line(at + Vector2.from_angle(a) * 0.42 * px, at + Vector2.from_angle(a) * 0.5 * px, DARK, w * 1.4)
			ci.draw_circle(at, 0.42 * px, BODY)
			ci.draw_circle(at, 0.1 * px, DARK)
		ItemKinds.Kind.TUB:
			ci.draw_colored_polygon(PackedVector2Array([at + along * 0.5 + side * 0.4, at + along * 0.5 - side * 0.4,
				at - along * 0.5 - side * 0.4, at - along * 0.5 + side * 0.4]), DARK)
			ci.draw_colored_polygon(PackedVector2Array([at + along * 0.42 + side * 0.32, at + along * 0.42 - side * 0.32,
				at - along * 0.42 - side * 0.32, at - along * 0.42 + side * 0.32]), BODY)
			var cans: int = (held >> ItemKinds.TUB_CANS_SHIFT) & 0xFF
			for i: int in mini(cans, 4):
				var spot: Vector2 = at + along * (-0.24 + 0.16 * i)
				ci.draw_circle(spot, 0.07 * px, Palette.CHALK_WHITE.darkened(0.25))


## A grey-box shape for each item kind (art replaces them), so a spanner reads apart from a fuse.
## Unknown kinds keep the plain square.
static func draw_item(ci: CanvasItem, kind: int, at: Vector2, px: float) -> void:
	var w: float = maxf(1.5, 0.06 * px)
	var light: Color = Palette.CHALK_WHITE.darkened(0.25)
	match kind:
		ItemKinds.Kind.GAUZE_LAMP, ItemKinds.Kind.ELECTRIC_LAMP:
			var body: Rect2 = Rect2(at - Vector2(0.12, 0.16) * px, Vector2(0.24, 0.32) * px)
			ci.draw_rect(body, DARK, true)
			ci.draw_rect(body.grow(-0.04 * px), BODY if kind == ItemKinds.Kind.GAUZE_LAMP else light, true)
			ci.draw_arc(at - Vector2(0.0, 0.16) * px, 0.08 * px, PI, TAU, 8, DARK, w)
		ItemKinds.Kind.CANDLE:
			ci.draw_rect(Rect2(at - Vector2(0.05, 0.16) * px, Vector2(0.1, 0.32) * px), light, true)
		ItemKinds.Kind.FLARE:
			ci.draw_line(at - Vector2(0.18, 0.0) * px, at + Vector2(0.18, 0.0) * px, BODY, 0.09 * px)
			ci.draw_circle(at + Vector2(0.2, 0.0) * px, 0.06 * px, light)
		ItemKinds.Kind.STONE:
			ci.draw_circle(at, 0.11 * px, BODY)
		ItemKinds.Kind.OIL_FLASK:
			ci.draw_rect(Rect2(at - Vector2(0.1, 0.08) * px, Vector2(0.2, 0.22) * px), BODY, true)
			ci.draw_rect(Rect2(at - Vector2(0.04, 0.18) * px, Vector2(0.08, 0.1) * px), DARK, true)
		ItemKinds.Kind.PARAFFIN_CAN:
			ci.draw_rect(Rect2(at - Vector2(0.18, 0.16) * px, Vector2(0.36, 0.32) * px), BODY, true)
			ci.draw_line(at + Vector2(0.1, -0.16) * px, at + Vector2(0.2, -0.26) * px, DARK, w)
		ItemKinds.Kind.HEALING_KIT:
			ci.draw_rect(Rect2(at - Vector2(0.16, 0.12) * px, Vector2(0.32, 0.24) * px), light, true)
			ci.draw_line(at - Vector2(0.08, 0.0) * px, at + Vector2(0.08, 0.0) * px, DARK, w * 1.4)
			ci.draw_line(at - Vector2(0.0, 0.08) * px, at + Vector2(0.0, 0.08) * px, DARK, w * 1.4)
		ItemKinds.Kind.SPANNER:
			ci.draw_line(at - Vector2(0.16, 0.0) * px, at + Vector2(0.12, 0.0) * px, BODY, w * 1.4)
			ci.draw_arc(at + Vector2(0.16, 0.0) * px, 0.06 * px, -PI * 0.7, PI * 0.7, 8, BODY, w * 1.4)
		ItemKinds.Kind.HAMMER:
			ci.draw_line(at + Vector2(0.0, 0.18) * px, at - Vector2(0.0, 0.1) * px, BODY, w * 1.4)
			ci.draw_rect(Rect2(at - Vector2(0.14, 0.18) * px, Vector2(0.28, 0.1) * px), DARK, true)
		ItemKinds.Kind.CROWBAR:
			ci.draw_line(at - Vector2(0.22, 0.0) * px, at + Vector2(0.18, 0.0) * px, BODY, w * 1.4)
			ci.draw_arc(at + Vector2(0.18, -0.05) * px, 0.05 * px, -PI * 0.5, PI * 0.5, 6, BODY, w * 1.4)
		ItemKinds.Kind.WIRE_CUTTERS:
			ci.draw_line(at - Vector2(0.14, 0.14) * px, at + Vector2(0.14, 0.14) * px, BODY, w * 1.4)
			ci.draw_line(at - Vector2(0.14, -0.14) * px, at + Vector2(0.14, -0.14) * px, BODY, w * 1.4)
		ItemKinds.Kind.FUSE:
			ci.draw_rect(Rect2(at - Vector2(0.12, 0.05) * px, Vector2(0.24, 0.1) * px), light, true)
			ci.draw_rect(Rect2(at - Vector2(0.12, 0.05) * px, Vector2(0.04, 0.1) * px), DARK, true)
			ci.draw_rect(Rect2(at + Vector2(0.08, -0.05) * px, Vector2(0.04, 0.1) * px), DARK, true)
		ItemKinds.Kind.ROPE_CLAMP:
			ci.draw_arc(at, 0.1 * px, 0.0, TAU, 12, BODY, w * 1.4)
		ItemKinds.Kind.MAGNETO:
			ci.draw_rect(Rect2(at - Vector2(0.18, 0.14) * px, Vector2(0.36, 0.28) * px), DARK, true)
			ci.draw_circle(at, 0.09 * px, BODY)
		ItemKinds.Kind.DRIVE_BELT:
			ci.draw_arc(at, 0.16 * px, 0.0, TAU, 16, DARK, w * 1.8)
		ItemKinds.Kind.BRAKE_SHOE:
			ci.draw_arc(at + Vector2(0.0, 0.1) * px, 0.18 * px, PI * 1.15, PI * 1.85, 10, BODY, w * 2.2)
		ItemKinds.Kind.REVOLVER:
			ci.draw_line(at - Vector2(0.14, 0.0) * px, at + Vector2(0.14, 0.0) * px, DARK, w * 1.6)
			ci.draw_line(at - Vector2(0.1, 0.0) * px, at - Vector2(0.14, -0.14) * px, DARK, w * 1.6)
		ItemKinds.Kind.ROUNDS:
			ci.draw_rect(Rect2(at - Vector2(0.1, 0.07) * px, Vector2(0.2, 0.14) * px), BODY, true)
			for i: int in 3:
				ci.draw_circle(at + Vector2(-0.05 + i * 0.05, 0.0) * px, 0.018 * px, light)
		ItemKinds.Kind.CANARY:
			ci.draw_rect(Rect2(at - Vector2(0.14, 0.16) * px, Vector2(0.28, 0.32) * px), DARK, false, w)
			ci.draw_circle(at, 0.06 * px, light)
		ItemKinds.Kind.NOTE:
			ci.draw_rect(Rect2(at - Vector2(0.1, 0.13) * px, Vector2(0.2, 0.26) * px), light, true)
		_:
			ci.draw_rect(Rect2(at - Vector2(0.15, 0.15) * px, Vector2(0.3, 0.3) * px), BODY)


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

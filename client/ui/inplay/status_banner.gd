class_name StatusBanner
extends Node2D
## A standard status line at the top of the screen (the first playtest: being pinned, knocked out or
## coming round explained nothing): what holds the own miner and what can end it. Pinned, dragged
## or caught: who can free them; unconscious: a teammate's carry to a medbay table, or the solo
## self-revive coming (a ring fills over its count, RSC-09; never a number); coming round; dead. A
## moment's line on breaking free or coming round. Its content: the own block's life
## (DarkView.life_of), the coming-round window, and the own status (StatusWire).

var title_key: String = ""
var sub_key: String = ""
## The self-revive's count shown as a ring: 0..1, or -1 for none.
var ring: float = -1.0
var _last_life: int = -1
var _flash_key: String = ""
var _flash_until: float = -1.0


func _init() -> void:
	ScreenElementRegistry.mark(self, &"status")
	visible = false


## One frame. `life`: the own block's life (StatusWire.LIFE_*); `in_window`: coming round; `status`: StatusWire.decode;
## `server_tick`: the last frame's tick (for the self-revive's ring).
func update(shown: bool, life: int, in_window: bool, status: Dictionary, server_tick: int, now_s: float) -> void:
	var cues: int = int(Variants.number(status.get("cues", 0)))
	var flags: int = int(Variants.number(status.get("flags", 0)))
	title_key = ""
	sub_key = ""
	ring = -1.0
	match life:
		StatusWire.LIFE_GRABBED:
			title_key = "status.pinned" if (cues & MinerCues.HALF_IN_WALL) != 0 else ("status.dragged" if (cues & MinerCues.DRAGGED) != 0 else "status.held")
			if (flags & StatusWire.STRUGGLE) == 0:
				sub_key = "status.sub.teammate_pull"
		StatusWire.LIFE_CAUGHT:
			title_key = "status.caught"
			if (cues & MinerCues.HELD_JAWS) != 0:
				title_key = "status.caught_jaws"
			elif (cues & MinerCues.HELD_PROP) != 0:
				title_key = "status.caught_prop"
			elif (cues & MinerCues.HELD_PIT) != 0:
				title_key = "status.caught_pit"
			sub_key = "status.sub.teammate_free"
		StatusWire.LIFE_UNCONSCIOUS:
			if in_window:
				title_key = "status.coming_round"
			else:
				title_key = "status.unconscious"
				if (flags & StatusWire.REVIVE_COUNTING) != 0:
					sub_key = "status.sub.self_revive"
					var total: int = maxi(1, int(Variants.number(status.get("revive_ticks", 1))))
					var due: int = int(Variants.number(status.get("revive_due_tick", 0)))
					ring = clampf(1.0 - float(due - server_tick) / float(total), 0.0, 1.0)
				elif (flags & StatusWire.REVIVE_WAITING) != 0:
					sub_key = "status.sub.revive_waits"
				else:
					sub_key = "status.sub.carry"
		StatusWire.LIFE_DEAD:
			title_key = "status.dead"
		_:
			if _last_life == StatusWire.LIFE_GRABBED or _last_life == StatusWire.LIFE_CAUGHT:
				_flash("status.broke_free", now_s)
			elif _last_life == StatusWire.LIFE_UNCONSCIOUS:
				_flash("status.came_round", now_s)
	_last_life = life
	if title_key.is_empty() and now_s < _flash_until:
		title_key = _flash_key
	visible = shown and not title_key.is_empty()
	queue_redraw()


func _flash(key: String, now_s: float) -> void:
	_flash_key = key
	_flash_until = now_s + Tuning.f(&"camera.status_flash_s")


func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	var size: int = ScreenElementRegistry.min_font_px()
	var big: int = roundi(size * 1.6)
	var cx: float = ScreenElementRegistry.CANVAS.x * 0.5
	var y: float = 120.0
	var w: float = font.get_string_size(UiText.text(title_key), HORIZONTAL_ALIGNMENT_LEFT, -1, big).x
	draw_rect(Rect2(cx - w * 0.5 - 24.0, y - big - 8.0, w + 48.0, big + 20.0), ScreenElementRegistry.PANEL, true)
	draw_string(font, Vector2(cx - w * 0.5, y), UiText.text(title_key), HORIZONTAL_ALIGNMENT_LEFT, -1, big, ScreenElementRegistry.INK)
	if sub_key.is_empty():
		return
	var sw: float = font.get_string_size(UiText.text(sub_key), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var sy: float = y + size + 18.0
	draw_rect(Rect2(cx - sw * 0.5 - 16.0, sy - size - 6.0, sw + 32.0, size + 14.0), ScreenElementRegistry.PANEL, true)
	draw_string(font, Vector2(cx - sw * 0.5, sy), UiText.text(sub_key), HORIZONTAL_ALIGNMENT_LEFT, -1, size, ScreenElementRegistry.DIM)
	if ring >= 0.0:
		var c: Vector2 = Vector2(cx + sw * 0.5 + 34.0, sy - size * 0.35)
		draw_arc(c, 12.0, 0.0, TAU, 24, ScreenElementRegistry.PANEL, 6.0, true)
		draw_arc(c, 12.0, -PI * 0.5, -PI * 0.5 + TAU * ring, 24, ScreenElementRegistry.INK, 4.0, true)

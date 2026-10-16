class_name ManualCloseup
extends SheetCloseup
## LFT-03: the Manual at its lectern (Gameplay §3.3, §14.3): 'EMERGENCY WINDER: Instructions for
## Restoring to Service', printing only this run's jobs, in the Company's order and voice, with a
## plate of each part and tool, and the crew's own pencil over it (the Manual's sheet, SheetKind.
## MANUAL: ticks, crossings-out, margin notes such as 'fuses: east cabin?'). It never ticks itself:
## its ticks are only the crew's word. It names the kind of place a part is kept, never where that
## place is, and counts cans; it is sent nothing else (the server's MANUAL: kind, cans, jobs).
##
## The page is laid out in sheet units, the same on every screen, so a tick made beside a line on
## one client sits beside it on every other; the view only scales it (UI-06's text size is a zoom).
## It opens fitted to the page's width at its top; pan scrolls it, zoom enlarges it up to 3x.

## The page in sheet units (a 1:1.41 sheet), and its margins and columns.
const PAGE: Rect2 = Rect2(-1024, -1448, 2048, 2896)
const MARGIN: float = 128.0
const PLATE_W: float = 400.0
const PLATE_H: float = 104.0
const PLATE_GAP: float = 24.0
const GUTTER: float = 40.0
## Type sizes in sheet units; layout is measured at REF_PX and scaled.
const TITLE_UNITS: float = 64.0
const SUB_UNITS: float = 48.0
const BODY_UNITS: float = 40.0
const PLATE_TEXT_UNITS: float = 30.0
const LINE: float = 1.3
const REF_PX: int = 64
const PAGE_TONE: Color = Color(0.93, 0.90, 0.80)

## The run's list as the server sent it: () -> {kind, cans, jobs} ({} before it arrives).
var manual_list: Callable = Callable()
## The laid-out page: [{text, at (units, baseline left), units}] and plates [{rect, text}].
var _lines: Array[Dictionary] = []
var _plates: Array[Dictionary] = []
var _laid_for: Dictionary = {}
var _laid: bool = false


func on_open(context: Dictionary) -> void:
	_fit_width()
	centre = Vector2(PAGE.get_center().x, PAGE.position.y)
	clamp_view()
	super.on_open(context)


## Fitted to the page's width with its margins.
func _fit_width() -> void:
	var w: float = maxf(1.0, size.x)
	view_units = minf(size.x, size.y) * (PAGE.size.x + MARGIN) / w


func view_limits() -> Vector2:
	var fit: float = minf(size.x, size.y) * (PAGE.size.x + MARGIN) / maxf(1.0, size.x)
	return Vector2(fit / 3.0, fit)


## The page stays in view: never scrolled past its top or bottom, centred while it fits.
func clamp_view() -> void:
	var half: Vector2 = size * 0.5 / zoom()
	var lo: Vector2 = PAGE.position + half - Vector2(MARGIN, MARGIN) * 0.5
	var hi: Vector2 = PAGE.end - half + Vector2(MARGIN, MARGIN) * 0.5
	centre.x = PAGE.get_center().x if lo.x > hi.x else clampf(centre.x, lo.x, hi.x)
	centre.y = PAGE.get_center().y if lo.y > hi.y else clampf(centre.y, lo.y, hi.y)


## What the page prints now: [{text, at, units}], laid out for the list as sent (tests read it).
func printed_lines() -> Array[Dictionary]:
	_layout()
	return _lines


func printed_plates() -> Array[Dictionary]:
	_layout()
	return _plates


func step(delta: float) -> void:
	super.step(delta)
	if visible:
		_layout()


## The page: the Company's print and the plates, under the crew's pencil.
func _draw_paper() -> void:
	_layout()
	var page: Rect2 = Rect2(to_screen(PAGE.position), PAGE.size * zoom())
	draw_rect(page, PAGE_TONE)
	draw_rect(page, PRINT_INK, false, maxf(1.0, 3.0 * zoom()))
	var font: Font = ThemeDB.fallback_font
	for line: Dictionary in _lines:
		var px: int = roundi(float(Variants.number(line["units"])) * zoom())
		if px < 4:
			continue
		var at: Vector2 = line["at"]
		draw_string(font, to_screen(at), str(line["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, px, PRINT_INK)
	for plate: Dictionary in _plates:
		var r: Rect2 = plate["rect"]
		var screen: Rect2 = Rect2(to_screen(r.position), r.size * zoom())
		draw_rect(screen, PRINT_INK, false, maxf(1.0, 2.0 * zoom()))
		var px: int = roundi(PLATE_TEXT_UNITS * zoom())
		if px >= 4:
			draw_string(font, to_screen(r.position + Vector2(16, r.size.y - 24)), str(plate["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1,
				px, PRINT_INK)


## Lays the page out in sheet units for the list as sent, once a list.
func _layout() -> void:
	var list: Dictionary = Variants.dict(manual_list.call()) if manual_list.is_valid() else {}
	if _laid and list == _laid_for:
		return
	_laid = true
	_laid_for = list.duplicate(true)
	_lines.clear()
	_plates.clear()
	var x0: float = PAGE.position.x + MARGIN
	var full_w: float = PAGE.size.x - 2.0 * MARGIN
	var text_w: float = full_w - PLATE_W - GUTTER
	var y: float = PAGE.position.y + MARGIN + TITLE_UNITS
	y = _centred(UiText.text("manual.title"), TITLE_UNITS, y)
	y = _centred(UiText.text("manual.subtitle"), SUB_UNITS, y + SUB_UNITS * 0.4)
	y = _centred(UiText.text("manual.kept"), BODY_UNITS, y + BODY_UNITS * 0.2)
	y += BODY_UNITS * LINE
	var jobs: Array = Variants.array(list.get("jobs", []))
	var cans: int = int(Variants.number(list.get("cans", 0)))
	for i: int in jobs.size():
		var job: String = str(jobs[i])
		var text: String = UiText.text("manual.job.%s.text" % job).replace("{cans}", UiText.text("manual.cans.%d" % cans))
		var head: String = "%d. %s " % [i + 1, UiText.text("manual.job.%s.name" % job)]
		var top: float = y - BODY_UNITS
		y = _wrapped(head + text, BODY_UNITS, x0, text_w, y)
		var plate_y: float = top
		for raw: Variant in Variants.array(RepairJobs.PLATES.get(StringName(job), [])):
			_plates.append({"rect": Rect2(x0 + text_w + GUTTER, plate_y, PLATE_W, PLATE_H),
				"text": UiText.text("manual.plate.%s" % str(raw))})
			plate_y += PLATE_H + PLATE_GAP
		y = maxf(y, plate_y + BODY_UNITS) + BODY_UNITS * 0.6
	_wrapped(UiText.text("manual.footer"), BODY_UNITS, x0, full_w, maxf(y + BODY_UNITS, PAGE.end.y - MARGIN - BODY_UNITS * LINE * 5.0))
	queue_redraw()


func _centred(text: String, units: float, y: float) -> float:
	var w: float = _width(text, units)
	_lines.append({"text": text, "at": Vector2(PAGE.get_center().x - w * 0.5, y), "units": units})
	return y + units * LINE


## Greedy word wrap to `width` units; returns the baseline after the last line.
func _wrapped(text: String, units: float, x: float, width: float, y: float) -> float:
	var line: String = ""
	for word: String in text.split(" ", false):
		var trial: String = word if line.is_empty() else line + " " + word
		if not line.is_empty() and _width(trial, units) > width:
			_lines.append({"text": line, "at": Vector2(x, y), "units": units})
			y += units * LINE
			line = word
		else:
			line = trial
	if not line.is_empty():
		_lines.append({"text": line, "at": Vector2(x, y), "units": units})
		y += units * LINE
	return y


## A string's width in sheet units at `units` high (the font measured at REF_PX, then scaled).
func _width(text: String, units: float) -> float:
	var font: Font = ThemeDB.fallback_font
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, REF_PX).x * units / REF_PX

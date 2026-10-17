class_name SwitchboardCloseup
extends CloseupBase
## LFT-13 (Gameplay §4.10, §6.6, §14.3; GDD §14.2): the switchboard's close-up, filling the operator's
## screen: 99 numbered drops in brass, the cord, the hold and ring keys. A calling line's flap is down,
## a cut line's dark, a held call marked; the cord shows the line it is in. Before Power the board is
## inert and says so. It never shows where a phone is or who is calling: the server sends only the
## flaps (Protocol.Msg.BOARD, BoardWire), and a drop the rock fakes for this operator alone (CRT-11's
## illusion) is laid over them here, never on anyone else's screen. While the operator's own frame
## carries VIS-09's dust flag, dust sifts over the brass, evenly over the whole face and never from a
## side, so it says only that the Moth is near, never where.
##
## Input (UI-02's close-up actions): the mouse or the right stick picks a drop; left mouse or A
## plugs into it (or pulls the cord from the line it is in); right mouse or X holds the call; R or Y
## rings it. Each ask goes up as ActionRecord.Kind.BOARD (BoardWire.ask): the server decides.

const COLUMNS: int = 11
const ROWS: int = 9
const EBONITE: Color = Color(0.12, 0.1, 0.09)
const LIT: Color = Color(0.95, 0.9, 0.72)
const DARKENED: Color = Color(0.05, 0.05, 0.05)
const HELD_MARK: Color = Color(0.85, 0.55, 0.15)
const CORD: Color = Color(0.45, 0.12, 0.08)
## How often the stick steps the selection while held over (s).
const STICK_STEP_S: float = 0.18
const DUST: Color = Color(0.74, 0.7, 0.62, 0.6)
## Specks sifting over the face at once, and the slowest one's fall from top to bottom (s).
const DUST_SPECKS: int = 40
const DUST_FALL_S: float = 6.0

## The board as last told (BoardWire.decode): {awake, cord, flaps}.
var board: Dictionary = {}
## CRT-11: the drops the rock shows this operator alone (number -> true), laid over the real flaps.
var illusion_flaps: Dictionary = {}
## The drop under the mouse or the stick (1-99).
var selected: int = 1
## Asks for the server this frame (ActionRecord.Kind.BOARD arguments); client_main sends them.
var asks: Array[int] = []
## VIS-09: the operator's own dust flag (ReceivedView.dust), as client_main passes it on.
var dust: bool = false
var _stick_wait: float = 0.0
var _dust_t: float = 0.0


func on_open(_context: Dictionary) -> void:
	selected = clampi(selected, 1, BoardWire.DROPS)
	asks.clear()
	queue_redraw()


func on_close() -> void:
	asks.clear()


## The flap of line `n` as this operator sees it: the server's, or the rock's drop over an idle one.
func flap_of(n: int) -> int:
	var flaps: PackedByteArray = board.get("flaps", PackedByteArray())
	var real: int = flaps[n - 1] if n >= 1 and n <= flaps.size() else BoardWire.Flap.UP
	if real == BoardWire.Flap.UP and illusion_flaps.has(n) and Variants.flag(board.get("awake", false)):
		return BoardWire.Flap.DOWN
	return real


func set_board(view: Dictionary) -> void:
	if view != board:
		board = view
		queue_redraw()


func set_dust(on: bool) -> void:
	if on != dust:
		dust = on
		queue_redraw()


## The cabinet's face: the drops and their ebonite surround.
func face() -> Rect2:
	return _grid().grow(8.0)


## The dust's specks `t` seconds in (none without the flag): one to a column, the columns spread
## evenly across the face, each sifting straight down at its own pace.
func dust_specks(t: float) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	if not dust:
		return out
	var area: Rect2 = face()
	for i: int in DUST_SPECKS:
		var across: float = (float(i) + 0.5) / DUST_SPECKS
		var pace: float = DUST_FALL_S * (0.6 + 0.4 * fposmod(float(i) * 0.381966, 1.0))
		var down: float = fposmod(fposmod(float(i) * 0.618034, 1.0) + t / pace, 1.0)
		out.append(area.position + Vector2(across * area.size.x, down * area.size.y))
	return out


func handle(action: String) -> bool:
	match action:
		"plug":
			asks.append(BoardWire.ask(BoardWire.Verb.PLUG, selected))
		"hold_line":
			asks.append(BoardWire.ask(BoardWire.Verb.HOLD, selected))
		"ring_line":
			asks.append(BoardWire.ask(BoardWire.Verb.RING, selected))
		_:
			return false
	return true


## The drop at a point of this close-up (0: none).
func drop_at(at: Vector2) -> int:
	var grid: Rect2 = _grid()
	if not grid.has_point(at):
		return 0
	var col: int = clampi(floori((at.x - grid.position.x) / (grid.size.x / COLUMNS)), 0, COLUMNS - 1)
	var row: int = clampi(floori((at.y - grid.position.y) / (grid.size.y / ROWS)), 0, ROWS - 1)
	var n: int = row * COLUMNS + col + 1
	return n if n <= BoardWire.DROPS else 0


## The selection one step over (the stick's direction).
func step_selection(dir: Vector2i) -> void:
	var i: int = selected - 1
	var col: int = clampi(i % COLUMNS + dir.x, 0, COLUMNS - 1)
	var row: int = clampi(i / COLUMNS + dir.y, 0, ROWS - 1)
	selected = clampi(row * COLUMNS + col + 1, 1, BoardWire.DROPS)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion != null:
		var n: int = drop_at(motion.position)
		if n != 0 and n != selected:
			selected = n
			queue_redraw()


func _process(delta: float) -> void:
	if not visible:
		return
	if dust:
		_dust_t += delta
		queue_redraw()
	var v: Vector2 = Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	_stick_wait = maxf(0.0, _stick_wait - delta)
	if v.length() < 0.5 or _stick_wait > 0.0:
		return
	var dir: Vector2i = Vector2i(signi(roundi(v.x)), signi(roundi(v.y)))
	if dir != Vector2i.ZERO:
		step_selection(dir)
		_stick_wait = STICK_STEP_S


## The drops' area: the cabinet's face below the title, above the keys.
func _grid() -> Rect2:
	var edge: float = maxf(8.0, minf(size.x, size.y) * 0.02)
	var top: float = edge * 3.0 + maxi(24, roundi(minf(size.x, size.y) * 0.05)) + edge
	var bottom: float = size.y * 0.82
	return Rect2(Vector2(size.x * 0.1, top), Vector2(size.x * 0.8, maxf(10.0, bottom - top)))


func _draw() -> void:
	super._draw()
	var grid: Rect2 = _grid()
	draw_rect(grid.grow(8.0), EBONITE)
	var cell: Vector2 = Vector2(grid.size.x / COLUMNS, grid.size.y / ROWS)
	var font: Font = ThemeDB.fallback_font
	var font_size: int = maxi(12, roundi(minf(cell.x, cell.y) * 0.32))
	var awake: bool = Variants.flag(board.get("awake", false))
	var plugged: int = int(Variants.number(board.get("cord", 0)))
	for n: int in range(1, BoardWire.DROPS + 1):
		var i: int = n - 1
		var r: Rect2 = Rect2(grid.position + Vector2(i % COLUMNS, i / COLUMNS) * cell, cell).grow(-cell.x * 0.08)
		var f: int = flap_of(n)
		var plate: Color = BRASS if f != BoardWire.Flap.DARK else DARKENED
		draw_rect(r, plate)
		if f == BoardWire.Flap.DOWN:
			# The flap fallen: a lit shutter below the number.
			draw_rect(Rect2(r.position + Vector2(0, r.size.y * 0.5), Vector2(r.size.x, r.size.y * 0.5)), LIT)
		elif f == BoardWire.Flap.HELD:
			draw_circle(r.position + Vector2(r.size.x * 0.85, r.size.y * 0.2), maxf(2.0, r.size.x * 0.08), HELD_MARK)
		var label: String = str(n)
		var w: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		draw_string(font, r.position + Vector2((r.size.x - w) * 0.5, r.size.y * 0.42), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
			PRINT if f != BoardWire.Flap.DARK else BRASS.darkened(0.6))
		if n == selected:
			draw_rect(r.grow(cell.x * 0.05), LIT, false, maxf(2.0, cell.x * 0.05))
		if n == plugged:
			var jack: Vector2 = Vector2(size.x * 0.5, size.y * 0.9)
			draw_line(jack, r.get_center(), CORD, maxf(3.0, cell.x * 0.08))
	for p: Vector2 in dust_specks(_dust_t):
		draw_circle(p, maxf(1.0, cell.x * 0.03), DUST)
	if not awake:
		var dead: String = UiText.text("board.dead")
		var w2: float = font.get_string_size(dead, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size * 2).x
		draw_string(font, Vector2((size.x - w2) * 0.5, size.y * 0.9), dead, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size * 2, PRINT)

class_name CloseupManager
extends CanvasLayer
## UI-02: the client's close-ups (Gameplay §14.3). The server says which one this miner reads
## (Protocol.Msg.CLOSE_UP); the manager opens it full-screen and opaque over everything in play,
## easing in over camera.closeup_transition_s. Once it covers the screen the world view stops
## drawing beneath it (no world pixel shows, and the Deck's GPU rests), UI-01's in-play elements
## hide, and the input context switches (CloseupInputContext). UI-03's captions stay above it on
## CAPTIONS_LAYER, since the sound goes on; game audio is never touched here.
##
## It asks the server with ActionRecord.Kind.CLOSE_UP (CloseupKind.Ask): the Pocket Book's press
## opens it anywhere; Esc or B closes, or at the board starts the 2 s stand, which A cancels. A
## close-up's own actions go to its content (CloseupBase.handle). Nothing opens before the server
## agrees, so a refused open never shows.

signal opened(kind: CloseupKind.Kind)
signal closed(kind: CloseupKind.Kind)

## Above UI-01's in-play layer (5), below the menus (20).
const LAYER: int = 10
## UI-03's captions and arcs: above any close-up.
const CAPTIONS_LAYER: int = 12

var kind: CloseupKind.Kind = CloseupKind.Kind.NONE
var seat: CloseupKind.Seat = CloseupKind.Seat.NONE
var input_context: CloseupInputContext = CloseupInputContext.new()
## UI-01's layer, hidden beneath an open close-up (the world view stops through covers_world()).
var in_play_layer: CanvasLayer = null
## MOD-06's offline Night Shift run: the only place a pause exists (UI-05 draws it).
var offline_night_shift: bool = false
## kind -> CloseupBase; a kind without content shows the placeholder.
var contents: Dictionary = {}
var _current: CloseupBase = null
var _coverage: float = 0.0
var _target: float = 0.0
var _pocket_presses_seen: int = 0
var _asks: Array[int] = []


func _init() -> void:
	layer = LAYER


## A content ticket's close-up for its kind.
func register(of_kind: CloseupKind.Kind, content: CloseupBase) -> void:
	content.kind = of_kind
	content.visible = false
	content.close_requested.connect(func() -> void: _ask(CloseupKind.Ask.CLOSE))
	contents[of_kind] = content
	if content.get_parent() == null:
		add_child(content)


func content_for(of_kind: CloseupKind.Kind) -> CloseupBase:
	if not contents.has(of_kind):
		var scene: PackedScene = load("res://client/ui/closeup/closeup_base.tscn")
		var placeholder: CloseupBase = scene.instantiate()
		register(of_kind, placeholder)
	return contents[of_kind]


## The server's word: {kind, seat} (CloseupKind.decode).
func apply(state: Dictionary) -> void:
	if state.is_empty():
		return
	var new_kind: int = state["kind"]
	var new_seat: int = state["seat"]
	seat = new_seat as CloseupKind.Seat
	if new_kind == kind:
		return
	if kind != CloseupKind.Kind.NONE:
		_close()
	if new_kind != CloseupKind.Kind.NONE:
		_open(new_kind as CloseupKind.Kind)


## One client frame of input (after InputRouter.sample): the asks to send this tick, as
## CloseupKind.Ask values (ActionRecord.Kind.CLOSE_UP's argument).
func process_input(router: InputRouter) -> Array[int]:
	if router.pocket_book_presses > _pocket_presses_seen and kind == CloseupKind.Kind.NONE:
		_ask(CloseupKind.Ask.OPEN_POCKET_BOOK)
	_pocket_presses_seen = router.pocket_book_presses
	if kind != CloseupKind.Kind.NONE:
		for action: String in router.close_up_events:
			if action == "close":
				# A content may back out of its own step first (the map table's label field).
				if _current == null or not _current.handle(action):
					_ask(CloseupKind.Ask.CLOSE)
			elif action == "close_up_open" and seat == CloseupKind.Seat.STANDING:
				_ask(CloseupKind.Ask.STAY_SEATED)
			elif _current != null:
				_current.handle(action)
	var out: Array[int] = _asks.duplicate()
	_asks.clear()
	return out


## True once an open close-up covers the whole screen: the world view draws nothing beneath it.
func covers_world() -> bool:
	return kind != CloseupKind.Kind.NONE and _coverage >= 1.0


## UI-05's pause control exists only offline in Night Shift, behind the Pocket Book.
func pause_available() -> bool:
	return offline_night_shift and kind == CloseupKind.Kind.POCKET_BOOK


func current() -> CloseupBase:
	return _current


func _process(delta: float) -> void:
	step(delta)


## Eases the open or close; tests call it directly.
func step(delta: float) -> void:
	if _current == null:
		return
	var span: float = Tuning.f(&"camera.closeup_transition_s") if Tuning.current.has_key(&"camera.closeup_transition_s") else 0.0
	_coverage = _target if span <= 0.0 else move_toward(_coverage, _target, delta / span)
	_current.modulate.a = _coverage
	if _coverage <= 0.0 and _target <= 0.0:
		_current.visible = false
		_current = null


func _open(of_kind: CloseupKind.Kind) -> void:
	if _current != null:
		_current.visible = false
		_current.modulate.a = 1.0
	kind = of_kind
	_current = content_for(of_kind)
	_current.visible = true
	_current.modulate.a = _coverage
	_target = 1.0
	_current.on_open({"kind": of_kind})
	input_context.enter()
	_set_in_play(false)
	opened.emit(of_kind)


func _close() -> void:
	var was: CloseupKind.Kind = kind
	kind = CloseupKind.Kind.NONE
	seat = CloseupKind.Seat.NONE
	_target = 0.0
	if _current != null:
		_current.on_close()
	input_context.leave()
	_set_in_play(true)
	closed.emit(was)


func _set_in_play(on: bool) -> void:
	if in_play_layer != null:
		in_play_layer.visible = on


func _ask(ask: CloseupKind.Ask) -> void:
	if not _asks.has(ask):
		_asks.append(ask)

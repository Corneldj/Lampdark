extends GutTest
## UI-02's client close-ups: opened only on the server's word, full-screen over UI-01's layer, the
## world covered once the transition ends; Esc or B asks to close (at the board, to stand), A
## cancels a stand, the Pocket Book's press asks to open it; content gets its own actions; the pause
## exists only offline in Night Shift behind the Pocket Book.


## A content stand-in that keeps what it was given.
class Content:
	extends CloseupBase
	var got: Array[String] = []
	var opens: int = 0
	var closes: int = 0

	func on_open(_context: Dictionary) -> void:
		opens += 1

	func on_close() -> void:
		closes += 1

	func handle(action: String) -> bool:
		got.append(action)
		return true


var m: CloseupManager = null
var router: InputRouter = null
var camera: LampCamera = null
var in_play: CanvasLayer = null


func before_all() -> void:
	assert_true(Tuning.load_server())


func before_each() -> void:
	router = InputRouter.new()
	camera = LampCamera.new()
	add_child_autofree(camera)
	in_play = CanvasLayer.new()
	add_child_autofree(in_play)
	m = CloseupManager.new()
	m.input_context = CloseupInputContext.new(router, camera)
	m.in_play_layer = in_play
	add_child_autofree(m)


func _state(kind: CloseupKind.Kind, seat: CloseupKind.Seat = CloseupKind.Seat.NONE) -> Dictionary:
	return CloseupKind.decode(CloseupKind.encode(kind, seat))


func test_each_kind_opens_full_screen_and_covers_once_eased_in() -> void:
	for kind: CloseupKind.Kind in [CloseupKind.Kind.MAP_TABLE, CloseupKind.Kind.POCKET_BOOK, CloseupKind.Kind.MANUAL,
			CloseupKind.Kind.SWITCHBOARD]:
		m.apply(_state(kind))
		var c: CloseupBase = m.current()
		assert_not_null(c)
		assert_eq(c.kind, kind)
		assert_true(c.visible)
		assert_eq(c.anchor_right, 1.0)
		assert_eq(c.anchor_bottom, 1.0)
		assert_false(m.covers_world(), "not yet: it eases in over camera.closeup_transition_s")
		m.step(Tuning.f(&"camera.closeup_transition_s"))
		assert_true(m.covers_world())
		assert_eq(c.modulate.a, 1.0, "fully opaque")
		assert_false(in_play.visible, "UI-01's elements hide beneath it")
		assert_eq(router.context, InputContexts.Context.CLOSE_UP)
		assert_eq(camera.state, LampCamera.State.CLOSE_UP)
		m.apply(_state(CloseupKind.Kind.NONE))
		assert_false(m.covers_world(), "the mine draws again at once")
		assert_true(in_play.visible)
		assert_eq(router.context, InputContexts.Context.MINE)
		assert_eq(camera.state, LampCamera.State.MINE)
		m.step(1.0)
		assert_false(c.visible, "faded off")
	assert_eq(m.layer, CloseupManager.LAYER)
	assert_lt(CloseupManager.LAYER, CloseupManager.CAPTIONS_LAYER, "UI-03's captions stay above every close-up")
	assert_gt(CloseupManager.LAYER, InPlayLayer.LAYER)


func test_asks_go_to_the_server_and_actions_to_the_content() -> void:
	var content: Content = Content.new()
	m.register(CloseupKind.Kind.MAP_TABLE, content)
	router.pocket_book_presses += 1
	assert_eq(m.process_input(router), [CloseupKind.Ask.OPEN_POCKET_BOOK] as Array[int], "M or View asks for the Pocket Book")
	assert_eq(m.kind, CloseupKind.Kind.NONE, "nothing opens before the server agrees")
	assert_eq(m.process_input(router), [] as Array[int], "one press, one ask")
	m.apply(_state(CloseupKind.Kind.MAP_TABLE))
	assert_eq(content.opens, 1)
	router.close_up_events.assign(["pencil", "rubber", "close"])
	assert_eq(m.process_input(router), [CloseupKind.Ask.CLOSE] as Array[int], "Esc or B asks to close")
	assert_eq(content.got, ["pencil", "rubber"] as Array[String], "the close-up's own actions reach its content")
	router.pocket_book_presses += 1
	router.close_up_events.clear()
	assert_eq(m.process_input(router), [] as Array[int], "no Pocket Book over an open close-up")
	content.request_close()
	assert_eq(m.process_input(router), [CloseupKind.Ask.CLOSE] as Array[int], "content may ask to close")
	m.apply(_state(CloseupKind.Kind.NONE))
	assert_eq(content.closes, 1)


func test_the_board_stands_on_b_and_sits_back_on_a() -> void:
	m.apply(_state(CloseupKind.Kind.SWITCHBOARD))
	router.close_up_events.assign(["close"])
	assert_eq(m.process_input(router), [CloseupKind.Ask.CLOSE] as Array[int], "B starts the stand (the server times it)")
	m.apply(_state(CloseupKind.Kind.SWITCHBOARD, CloseupKind.Seat.STANDING))
	assert_eq(m.kind, CloseupKind.Kind.SWITCHBOARD, "still at the board while standing up")
	router.close_up_events.assign(["close_up_open"])
	assert_eq(m.process_input(router), [CloseupKind.Ask.STAY_SEATED] as Array[int], "A cancels the stand")


func test_the_pause_exists_only_offline_behind_the_pocket_book() -> void:
	for offline: bool in [false, true]:
		m.offline_night_shift = offline
		for kind: CloseupKind.Kind in [CloseupKind.Kind.NONE, CloseupKind.Kind.MAP_TABLE, CloseupKind.Kind.POCKET_BOOK,
				CloseupKind.Kind.MANUAL, CloseupKind.Kind.SWITCHBOARD]:
			m.apply(_state(kind))
			assert_eq(m.pause_available(), offline and kind == CloseupKind.Kind.POCKET_BOOK, "offline %s, %s" % [offline, kind])
		m.apply(_state(CloseupKind.Kind.NONE))


func test_the_wire_form() -> void:
	assert_eq(CloseupKind.decode(CloseupKind.encode(CloseupKind.Kind.MANUAL, CloseupKind.Seat.NONE)), {"kind": 3, "seat": 0})
	assert_eq(CloseupKind.decode(PackedByteArray([9, 0])), {}, "an unknown kind is refused")
	assert_eq(CloseupKind.decode(PackedByteArray([1])), {}, "short")
	assert_eq(CloseupKind.decode(PackedByteArray([1, 3])), {}, "an unknown seat")

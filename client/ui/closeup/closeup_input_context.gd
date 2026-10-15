class_name CloseupInputContext
extends RefCounted
## UI-02: input into a close-up and back out. MNR-15's router reads only the close-up's actions (left
## mouse the pencil or the cord; movement, wheels and the lamp keys inert), STM-06's Steam Input
## action set switches to "close_up", and VIS-01's camera holds still. Leaving restores the mine's.

const STEAM_SET_MINE: String = "mine"
const STEAM_SET_CLOSE_UP: String = "close_up"

var router: InputRouter = null
var camera: LampCamera = null
## STM-06's action-set switch, (set_name: String) -> void. Until STM-06 lands only the request is
## kept (active_steam_set), which the tests read.
var activate_steam_set: Callable = Callable()
var active_steam_set: String = STEAM_SET_MINE


func _init(input_router: InputRouter = null, lamp_camera: LampCamera = null) -> void:
	router = input_router
	camera = lamp_camera


func enter() -> void:
	if router != null:
		router.open_close_up()
	if camera != null:
		camera.state = LampCamera.State.CLOSE_UP
	_steam(STEAM_SET_CLOSE_UP)


func leave() -> void:
	if router != null:
		router.close_close_up()
	if camera != null:
		camera.state = LampCamera.State.MINE
	_steam(STEAM_SET_MINE)


func _steam(set_name: String) -> void:
	active_steam_set = set_name
	if activate_steam_set.is_valid():
		activate_steam_set.call(set_name)

extends SteamApi
## STM-01's fake Steam for tests: a scripted init status, identity, overlay and hardware, and a
## record of every call (so a test can prove nothing is called after a failed init).

var loaded_value: bool = true
var restart_value: bool = false
var init_status: int = Init.OK
var id: int = 76561197960287930
var persona: String = "Ann"
var friends: Dictionary = {}
var overlay_on: bool = true
var language: String = "english"
var hardware_value: Hardware = Hardware.NONE
## Every call by name, in order.
var calls: Array[String] = []
var _up: bool = false


func loaded() -> bool:
	calls.append("loaded")
	return loaded_value


func restart_app_if_necessary(_app_id: int) -> bool:
	calls.append("restart_app_if_necessary")
	return restart_value


func init(_app_id: int) -> Dictionary:
	calls.append("init")
	_up = init_status == Init.OK
	return {"status": init_status, "verbal": "fake"}


func run_callbacks() -> void:
	calls.append("run_callbacks")


func shutdown() -> void:
	calls.append("shutdown")
	_up = false


func steam_id() -> int:
	calls.append("steam_id")
	return id if _up else 0


func persona_name() -> String:
	calls.append("persona_name")
	return persona if _up else ""


func friend_persona_name(steam_id_of: int) -> String:
	calls.append("friend_persona_name")
	return str(friends.get(steam_id_of, "")) if _up else ""


func overlay_enabled() -> bool:
	calls.append("overlay_enabled")
	return _up and overlay_on


func game_language() -> String:
	calls.append("game_language")
	return language if _up else ""


func hardware() -> Hardware:
	calls.append("hardware")
	return hardware_value if _up else Hardware.NONE


## Test drivers: what Steam's callbacks would deliver.
func toggle_overlay(active: bool) -> void:
	overlay_toggled.emit(active)


func change_persona(steam_id_of: int, new_name: String) -> void:
	if steam_id_of == id:
		persona = new_name
	else:
		friends[steam_id_of] = new_name
	persona_changed.emit(steam_id_of)

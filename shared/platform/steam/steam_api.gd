class_name SteamApi
extends RefCounted
## STM-01's adapter: the only file that calls GodotSteam (the `Steam` singleton). SteamService and
## every later Steam ticket go through it; FakeSteamApi stands in for it in tests. Servers never
## create one (GDD §15.1: servers use the game-server API or nothing, STM-04 and STM-09).

## steamInitEx's statuses (ESteamAPIInitResult).
enum Init { OK = 0, FAILED_GENERIC = 1, NO_STEAM_CLIENT = 2, VERSION_MISMATCH = 3 }
## IsRunningOnSteamHardware's answers (Steamworks SDK 1.65).
enum Hardware { NONE = 0, STEAM_DECK = 1, STEAM_MACHINE = 2, STEAM_FRAME = 3 }

const SINGLETON: StringName = &"Steam"

signal overlay_toggled(active: bool)
signal persona_changed(steam_id: int)

var _steam: Object = null


## Whether GodotSteam is loaded (a server export, or a platform without it, has none).
func loaded() -> bool:
	return Engine.has_singleton(SINGLETON)


## Release builds only: true when Steam is relaunching the game, which must then quit at once.
func restart_app_if_necessary(app_id: int) -> bool:
	return loaded() and Variants.flag(Engine.get_singleton(SINGLETON).call(&"restartAppIfNecessary", app_id))


## steamInitEx with the app ID first and callbacks not embedded (SteamService pumps them).
## Returns {status (Init), verbal}.
func init(app_id: int) -> Dictionary:
	if not loaded():
		return {"status": Init.FAILED_GENERIC, "verbal": "GodotSteam is not loaded"}
	_steam = Engine.get_singleton(SINGLETON)
	var r: Dictionary = Variants.dict(_steam.call(&"steamInitEx", app_id, false))
	var status: int = int(Variants.number(r.get("status", Init.FAILED_GENERIC)))
	if status == Init.OK:
		_steam.connect(&"overlay_toggled", _on_overlay_toggled)
		_steam.connect(&"persona_state_change", _on_persona_state_change)
	else:
		_steam = null
	return {"status": status, "verbal": str(r.get("verbal", ""))}


func run_callbacks() -> void:
	if _steam != null:
		_steam.call(&"run_callbacks")


func shutdown() -> void:
	if _steam != null:
		_steam.disconnect(&"overlay_toggled", _on_overlay_toggled)
		_steam.disconnect(&"persona_state_change", _on_persona_state_change)
		_steam.call(&"steamShutdown")
		_steam = null


func steam_id() -> int:
	return int(Variants.number(_steam.call(&"getSteamID"))) if _steam != null else 0


func persona_name() -> String:
	return str(_steam.call(&"getPersonaName")) if _steam != null else ""


func friend_persona_name(steam_id_of: int) -> String:
	return str(_steam.call(&"getFriendPersonaName", steam_id_of)) if _steam != null else ""


func overlay_enabled() -> bool:
	return _steam != null and Variants.flag(_steam.call(&"isOverlayEnabled"))


## Steam's current game language ("english", "schinese", ...), for UI-07's default.
func game_language() -> String:
	return str(_steam.call(&"getCurrentGameLanguage")) if _steam != null else ""


func hardware() -> Hardware:
	if _steam == null:
		return Hardware.NONE
	return clampi(int(Variants.number(_steam.call(&"isRunningOnSteamHardware"))), 0, Hardware.STEAM_FRAME) as Hardware


func _on_overlay_toggled(active: bool, _user_initiated: bool, _app_id: int) -> void:
	overlay_toggled.emit(active)


func _on_persona_state_change(steam_id_of: int, _flags: int) -> void:
	persona_changed.emit(steam_id_of)

class_name SteamServerApi
extends SteamApi
## STM-04's Path A: the game-server side of STM-01's adapter. The only file besides steam_api.gd that
## calls a GodotSteam singleton. A private host's server process loads GodotSteam Server at run time
## (it cannot share a project with GodotSteam: both register SteamProjectSettings), initialises the
## game-server API on loopback, logs on anonymously and unlisted, and then serves STM-03's Steam
## Networking Sockets calls (the same names on SteamServer) under its own game-server SteamID.

const SERVER_SINGLETON: StringName = &"SteamServer"
## eServerMode: authentication (Steam checks every client's licence, no VAC).
const MODE_AUTHENTICATION: int = 2
## Let Steam share the game socket for queries: no extra port is bound.
const QUERY_PORT_SHARED: int = 0xFFFF

signal logged_on(ok: bool, detail: String)

var _logged_on: bool = false


## GodotSteam Server's .gdextension, loaded from beside the executable (exports) or from `path`.
## False where GodotSteam is already loaded (an editor or source run): the two cannot share a process.
static func load_extension(path: String) -> bool:
	if Engine.has_singleton(SERVER_SINGLETON):
		return true
	if Engine.has_singleton(SINGLETON):
		return false
	if not FileAccess.file_exists(path):
		return false
	GDExtensionManager.load_extension(path)
	return Engine.has_singleton(SERVER_SINGLETON)


func loaded() -> bool:
	return Engine.has_singleton(SERVER_SINGLETON)


## serverInitEx on loopback, unlisted; then an anonymous logon, answered by `logged_on`.
## Returns {status (Init), verbal}.
func init(_app_id: int) -> Dictionary:
	if not loaded():
		return {"status": Init.FAILED_GENERIC, "verbal": "GodotSteam Server is not loaded"}
	_steam = Engine.get_singleton(SERVER_SINGLETON)
	var r: Dictionary = Variants.dict(_steam.call(&"serverInitEx", "127.0.0.1", 0, QUERY_PORT_SHARED, MODE_AUTHENTICATION, Protocol.build_id()))
	var status: int = Variants.whole(r.get("status", Init.FAILED_GENERIC))
	if status != Init.OK:
		_steam = null
		return {"status": status, "verbal": str(r.get("verbal", ""))}
	_steam.connect(&"server_connected", _on_server_connected)
	_steam.connect(&"server_connect_failure", _on_server_connect_failure)
	_steam.connect(&"network_connection_status_changed", _on_network_connection_status_changed)
	_steam.connect(&"relay_network_status", _on_relay_network_status)
	_steam.call(&"setAdvertiseServerActive", false)
	_steam.call(&"logOnAnonymous")
	return {"status": status, "verbal": str(r.get("verbal", ""))}


func is_logged_on() -> bool:
	return _logged_on


func shutdown() -> void:
	if _steam != null:
		_steam.disconnect(&"server_connected", _on_server_connected)
		_steam.disconnect(&"server_connect_failure", _on_server_connect_failure)
		_steam.disconnect(&"network_connection_status_changed", _on_network_connection_status_changed)
		_steam.disconnect(&"relay_network_status", _on_relay_network_status)
		_steam.call(&"serverShutdown")
		_steam = null
	_logged_on = false


func _on_server_connected() -> void:
	_logged_on = true
	logged_on.emit(true, "")


func _on_server_connect_failure(result: int, retrying: bool) -> void:
	if not retrying:
		logged_on.emit(false, "logon failed (EResult %d)" % result)

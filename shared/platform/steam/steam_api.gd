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
## STM-02's lobby callbacks: created (ok, lobby), entered (lobby, ChatRoomEnterResponse), changed
## (members or data), a search's results, and an invite or friends-list join to act on.
signal lobby_created(ok: bool, lobby_id: int)
signal lobby_entered(lobby_id: int, response: int)
signal lobby_changed(lobby_id: int)
signal lobby_list(lobby_ids: PackedInt64Array)
signal join_requested(lobby_id: int)
## STM-03's Steam Networking Sockets: a connection's state changed (info as GodotSteam reports it:
## identity, listen_socket, connection_state, end_reason, end_debug, info_flags ...), and the relay
## network's availability (k_ESteamNetworkingAvailability: 100 is current).
signal sns_status_changed(handle: int, info: Dictionary, old_state: int)
signal relay_status(available: int, debug_message: String)

## ELobbyType and ELobbyDistanceFilter values (STM-02).
const LOBBY_PUBLIC: int = 2
const DISTANCE_WORLDWIDE: int = 3
const COMPARISON_EQUAL: int = 0
const RESULT_OK: int = 1
const FRIEND_FLAG_IMMEDIATE: int = 4

## Steam Networking Sockets (STM-03): connection states, send flags, info flags and config keys.
enum SnsState { NONE = 0, CONNECTING = 1, FINDING_ROUTE = 2, CONNECTED = 3, CLOSED_BY_PEER = 4, PROBLEM = 5 }
const SNS_SEND_UNRELIABLE: int = 0
const SNS_SEND_RELIABLE: int = 8
const SNS_INFO_UNAUTHENTICATED: int = 1
const SNS_INFO_UNENCRYPTED: int = 2
const SNS_INFO_RELAYED: int = 16
const SNS_CONFIG_ICE_ENABLE: int = 104
const SNS_ICE_DISABLE: int = 0
const SNS_CONFIG_TIMEOUT_INITIAL: int = 24
const SNS_CONFIG_TIMEOUT_CONNECTED: int = 25
const SNS_CONFIG_FAKE_LOSS_SEND: int = 2
const SNS_CONFIG_FAKE_LOSS_RECV: int = 3
const SNS_CONFIG_FAKE_LAG_SEND: int = 4
const SNS_CONFIG_FAKE_LAG_RECV: int = 5
const SNS_CONFIG_FAKE_REORDER_SEND: int = 6
const SNS_CONFIG_FAKE_REORDER_TIME: int = 8
const SNS_END_APP_GENERIC: int = 1000

const _LOBBY_SIGNALS: Array[StringName] = [&"lobby_created", &"lobby_joined", &"lobby_chat_update", &"lobby_data_update",
	&"lobby_match_list", &"join_requested"]

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
	var status: int = Variants.whole(r.get("status", Init.FAILED_GENERIC))
	if status == Init.OK:
		_steam.connect(&"overlay_toggled", _on_overlay_toggled)
		_steam.connect(&"persona_state_change", _on_persona_state_change)
		for sig: StringName in _LOBBY_SIGNALS:
			_steam.connect(sig, Callable(self, "_on_" + str(sig)))
		_steam.connect(&"network_connection_status_changed", _on_network_connection_status_changed)
		_steam.connect(&"relay_network_status", _on_relay_network_status)
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
		for sig: StringName in _LOBBY_SIGNALS:
			_steam.disconnect(sig, Callable(self, "_on_" + str(sig)))
		_steam.disconnect(&"network_connection_status_changed", _on_network_connection_status_changed)
		_steam.disconnect(&"relay_network_status", _on_relay_network_status)
		_steam.call(&"steamShutdown")
		_steam = null


func steam_id() -> int:
	return Variants.whole(_steam.call(&"getSteamID")) if _steam != null else 0


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
	return clampi(Variants.whole(_steam.call(&"isRunningOnSteamHardware")), 0, Hardware.STEAM_FRAME) as Hardware


## STM-02: ISteamMatchmaking and the overlay's invite dialog. Results arrive as the signals above.
func create_lobby(max_members: int) -> void:
	if _steam != null:
		_steam.call(&"createLobby", LOBBY_PUBLIC, max_members)


func join_lobby(lobby_id: int) -> void:
	if _steam != null:
		_steam.call(&"joinLobby", lobby_id)


func leave_lobby(lobby_id: int) -> void:
	if _steam != null:
		_steam.call(&"leaveLobby", lobby_id)


func set_lobby_data(lobby_id: int, key: String, value: String) -> void:
	if _steam != null:
		_steam.call(&"setLobbyData", lobby_id, key, value)


func lobby_data(lobby_id: int, key: String) -> String:
	return str(_steam.call(&"getLobbyData", lobby_id, key)) if _steam != null else ""


func set_lobby_member_data(lobby_id: int, key: String, value: String) -> void:
	if _steam != null:
		_steam.call(&"setLobbyMemberData", lobby_id, key, value)


func lobby_member_data(lobby_id: int, member: int, key: String) -> String:
	return str(_steam.call(&"getLobbyMemberData", lobby_id, member, key)) if _steam != null else ""


func lobby_members(lobby_id: int) -> PackedInt64Array:
	var out: PackedInt64Array = PackedInt64Array()
	if _steam == null:
		return out
	for i: int in Variants.whole(_steam.call(&"getNumLobbyMembers", lobby_id)):
		out.append(Variants.whole(_steam.call(&"getLobbyMemberByIndex", lobby_id, i)))
	return out


func lobby_owner(lobby_id: int) -> int:
	return Variants.whole(_steam.call(&"getLobbyOwner", lobby_id)) if _steam != null else 0


func set_lobby_joinable(lobby_id: int, joinable: bool) -> void:
	if _steam != null:
		_steam.call(&"setLobbyJoinable", lobby_id, joinable)


func set_lobby_member_limit(lobby_id: int, limit: int) -> void:
	if _steam != null:
		_steam.call(&"setLobbyMemberLimit", lobby_id, limit)


## A search with string-equality filters, worldwide (Steam's default searches nearby regions only).
func request_lobby_list(filters: Dictionary) -> void:
	if _steam == null:
		return
	for key: Variant in filters.keys():
		_steam.call(&"addRequestLobbyListStringFilter", str(key), str(filters[key]), COMPARISON_EQUAL)
	_steam.call(&"addRequestLobbyListDistanceFilter", DISTANCE_WORLDWIDE)
	_steam.call(&"requestLobbyList")


func invite_dialog(lobby_id: int) -> void:
	if _steam != null:
		_steam.call(&"activateGameOverlayInviteDialog", lobby_id)


## Whether `steam_id_of` is the user's Steam friend (an admission vouch, STM-02).
func is_friend(steam_id_of: int) -> bool:
	return _steam != null and Variants.flag(_steam.call(&"hasFriend", steam_id_of, FRIEND_FLAG_IMMEDIATE))


## STM-03: Steam Networking Sockets (the user's interface; a game-server identity is STM-04's).
## Authentication and relay access warmed up at boot, so a first connect does not wait on them.
func sns_warm_up() -> void:
	if _steam != null:
		_steam.call(&"initAuthentication")
		_steam.call(&"initRelayNetworkAccess")


func sns_relay_status() -> int:
	return Variants.whole(_steam.call(&"getRelayNetworkStatus")) if _steam != null else 0


func sns_set_global_int(config: int, value: int) -> bool:
	return _steam != null and Variants.flag(_steam.call(&"setGlobalConfigValueInt32", config, value))


func sns_set_global_float(config: int, value: float) -> bool:
	return _steam != null and Variants.flag(_steam.call(&"setGlobalConfigValueFloat", config, value))


func sns_listen(virtual_port: int) -> int:
	return Variants.whole(_steam.call(&"createListenSocketP2P", virtual_port, {})) if _steam != null else 0


func sns_close_listen(socket: int) -> void:
	if _steam != null:
		_steam.call(&"closeListenSocket", socket)


func sns_connect(remote_steam_id: int, virtual_port: int) -> int:
	return Variants.whole(_steam.call(&"connectP2P", remote_steam_id, virtual_port, {})) if _steam != null else 0


func sns_accept(handle: int) -> int:
	return Variants.whole(_steam.call(&"acceptConnection", handle)) if _steam != null else 0


func sns_close(handle: int, reason: int, message: String, linger: bool) -> void:
	if _steam != null:
		_steam.call(&"closeConnection", handle, reason, message, linger)


## EResult (1 is OK).
func sns_send(handle: int, data: PackedByteArray, flags: int) -> int:
	if _steam == null:
		return 0
	var r: Dictionary = Variants.dict(_steam.call(&"sendMessageToConnection", handle, data, flags))
	return Variants.whole(r.get("result", 0))


## The waiting messages, as [{payload: PackedByteArray, ...}].
func sns_receive(handle: int, max_messages: int) -> Array:
	return Variants.array(_steam.call(&"receiveMessagesOnConnection", handle, max_messages)) if _steam != null else []


func sns_flush(handle: int) -> void:
	if _steam != null:
		_steam.call(&"flushMessagesOnConnection", handle)


func sns_info(handle: int) -> Dictionary:
	return Variants.dict(_steam.call(&"getConnectionInfo", handle)) if _steam != null else {}


## Real-time status: ping, connection quality, bytes and packets per second, pending bytes.
func sns_status(handle: int) -> Dictionary:
	return Variants.dict(_steam.call(&"getConnectionRealTimeStatus", handle, 0, true)) if _steam != null else {}


func _on_network_connection_status_changed(handle: int, info: Dictionary, old_state: int) -> void:
	sns_status_changed.emit(handle, info, old_state)


func _on_relay_network_status(available: int, _ping: int, _config: int, _relay: int, message: String) -> void:
	relay_status.emit(available, message)


func _on_lobby_created(result: int, lobby_id: int) -> void:
	lobby_created.emit(result == RESULT_OK, lobby_id)


func _on_lobby_joined(lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
	lobby_entered.emit(lobby_id, response)


func _on_lobby_chat_update(lobby_id: int, _changed_id: int, _making_change_id: int, _chat_state: int) -> void:
	lobby_changed.emit(lobby_id)


func _on_lobby_data_update(_success: int, lobby_id: int, _member_id: int) -> void:
	lobby_changed.emit(lobby_id)


func _on_lobby_match_list(lobbies: Array) -> void:
	var ids: PackedInt64Array = PackedInt64Array()
	for raw: Variant in lobbies:
		ids.append(Variants.whole(raw))
	lobby_list.emit(ids)


func _on_join_requested(lobby_id: int, _steam_id: int) -> void:
	join_requested.emit(lobby_id)


func _on_overlay_toggled(active: bool, _user_initiated: bool, _app_id: int) -> void:
	overlay_toggled.emit(active)


func _on_persona_state_change(steam_id_of: int, _flags: int) -> void:
	persona_changed.emit(steam_id_of)

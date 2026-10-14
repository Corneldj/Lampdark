class_name LobbyBackend
extends RefCounted
## STM-02: what LobbyService needs from a lobby system. SteamLobbyBackend speaks ISteamMatchmaking
## through STM-01's adapter; FakeLobbyBackend speaks to the dev server's rendezvous (dev mode, bots,
## tests), so --no-steam sessions behave like Steam lobbies.

## Both backends report Steam's ChatRoomEnterResponse values (LobbyBackendEnter).

signal created(ok: bool, lobby_id: int)
signal entered(lobby_id: int, response: int)
## Members or data changed in the current lobby.
signal changed(lobby_id: int)
signal search_done(lobby_ids: PackedInt64Array)
## Steam's join-requested: an accepted invite, or "Join Game" from the friends list.
signal join_requested(lobby_id: int)

## The lobby we are in (0 when none).
var lobby_id: int = 0


func poll() -> void:
	pass


func self_id() -> int:
	return 0


func create(_limit: int) -> void:
	pass


func join(_lobby_id: int) -> void:
	pass


func leave() -> void:
	pass


func set_data(_key: String, _value: String) -> void:
	pass


func data(_key: String) -> String:
	return ""


func set_member_data(_key: String, _value: String) -> void:
	pass


func member_data(_member: int, _key: String) -> String:
	return ""


func members() -> PackedInt64Array:
	return PackedInt64Array()


func owner() -> int:
	return 0


func set_joinable(_on: bool) -> void:
	pass


func set_limit(_limit: int) -> void:
	pass


## String-equality filters, worldwide.
func search(_filters: Dictionary) -> void:
	pass


## The overlay's invite dialog; false when there is none (dev mode, or the overlay disabled).
func invite_dialog() -> bool:
	return false


func is_friend(_steam_id: int) -> bool:
	return false


## A member's persona as the backend knows it (the fake backend's --name; Steam's persona).
func member_name(_steam_id: int) -> String:
	return ""


## Every lobby key's current value.
func all_data() -> Dictionary:
	var out: Dictionary = {}
	for key: String in LobbyMetadata.LOBBY_KEYS:
		out[key] = data(key)
	return out

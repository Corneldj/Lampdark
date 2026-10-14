class_name SteamLobbyBackend
extends LobbyBackend
## STM-02's Steam lobbies: Public, joinable, limited to modes.friends_lobby_max (Public is the only
## type both a code search and a friends-list join can find), through STM-01's adapter.

var api: SteamApi = null
var _limit: int = 5


func _init(steam_api: SteamApi) -> void:
	api = steam_api
	api.lobby_created.connect(_on_created)
	api.lobby_entered.connect(_on_entered)
	api.lobby_changed.connect(func(id: int) -> void:
		if id == lobby_id:
			changed.emit(id))
	api.lobby_list.connect(func(ids: PackedInt64Array) -> void: search_done.emit(ids))
	api.join_requested.connect(func(id: int) -> void: join_requested.emit(id))


func self_id() -> int:
	return api.steam_id()


func create(limit: int) -> void:
	_limit = limit
	api.create_lobby(limit)


func _on_created(ok: bool, id: int) -> void:
	if ok:
		lobby_id = id
		api.set_lobby_member_limit(id, _limit)
	created.emit(ok, id)


func _on_entered(id: int, response: int) -> void:
	if response == LobbyBackendEnter.SUCCESS:
		lobby_id = id
	entered.emit(id, response)


func join(id: int) -> void:
	api.join_lobby(id)


func leave() -> void:
	if lobby_id != 0:
		api.leave_lobby(lobby_id)
		lobby_id = 0


func set_data(key: String, value: String) -> void:
	api.set_lobby_data(lobby_id, key, value)


func data(key: String) -> String:
	return api.lobby_data(lobby_id, key)


func set_member_data(key: String, value: String) -> void:
	api.set_lobby_member_data(lobby_id, key, value)


func member_data(member: int, key: String) -> String:
	return api.lobby_member_data(lobby_id, member, key)


func members() -> PackedInt64Array:
	return api.lobby_members(lobby_id)


func owner() -> int:
	return api.lobby_owner(lobby_id)


func set_joinable(on: bool) -> void:
	api.set_lobby_joinable(lobby_id, on)


func set_limit(limit: int) -> void:
	api.set_lobby_member_limit(lobby_id, limit)


func search(filters: Dictionary) -> void:
	api.request_lobby_list(filters)


func invite_dialog() -> bool:
	if lobby_id == 0 or not api.overlay_enabled():
		return false
	api.invite_dialog(lobby_id)
	return true


func is_friend(steam_id: int) -> bool:
	return api.is_friend(steam_id)


func member_name(steam_id: int) -> String:
	return api.persona_name() if steam_id == self_id() else api.friend_persona_name(steam_id)

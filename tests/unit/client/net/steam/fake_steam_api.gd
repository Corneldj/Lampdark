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


## STM-02: a scripted Steam lobby system, answering at once as Steam's callbacks would.
var lobbies: Dictionary = {}
var join_response: int = 1
var next_lobby: int = 109775240000000100
var invites_opened: int = 0
var friends_of: Dictionary = {}


func create_lobby(max_members: int) -> void:
	calls.append("create_lobby")
	var lid: int = next_lobby
	next_lobby += 1
	lobbies[lid] = {"owner": id, "limit": max_members, "joinable": true, "data": {}, "members": [id], "member_data": {}}
	lobby_created.emit(true, lid)
	lobby_entered.emit(lid, 1)


func join_lobby(lobby_id: int) -> void:
	calls.append("join_lobby")
	if join_response == 1 and lobbies.has(lobby_id):
		Variants.array(Variants.dict(lobbies[lobby_id])["members"]).append(id)
	lobby_entered.emit(lobby_id, join_response if lobbies.has(lobby_id) else 2)


func leave_lobby(lobby_id: int) -> void:
	calls.append("leave_lobby")
	if lobbies.has(lobby_id):
		Variants.array(Variants.dict(lobbies[lobby_id])["members"]).erase(id)


func set_lobby_data(lobby_id: int, key: String, value: String) -> void:
	Variants.dict(Variants.dict(lobbies[lobby_id])["data"])[key] = value


func lobby_data(lobby_id: int, key: String) -> String:
	return str(Variants.dict(Variants.dict(lobbies.get(lobby_id, {"data": {}}))["data"]).get(key, ""))


func set_lobby_member_data(lobby_id: int, key: String, value: String) -> void:
	var md: Dictionary = Variants.dict(lobbies[lobby_id])["member_data"]
	Variants.dict(md.get_or_add(id, {}))[key] = value


func lobby_member_data(lobby_id: int, member: int, key: String) -> String:
	var md: Dictionary = Variants.dict(Variants.dict(lobbies.get(lobby_id, {"member_data": {}}))["member_data"])
	return str(Variants.dict(md.get(member, {})).get(key, ""))


func lobby_members(lobby_id: int) -> PackedInt64Array:
	var out: PackedInt64Array = PackedInt64Array()
	for raw: Variant in Variants.array(Variants.dict(lobbies.get(lobby_id, {"members": []}))["members"]):
		out.append(Variants.whole(raw))
	return out


func lobby_owner(lobby_id: int) -> int:
	return Variants.whole(Variants.dict(lobbies.get(lobby_id, {"owner": 0}))["owner"])


func set_lobby_joinable(lobby_id: int, joinable: bool) -> void:
	Variants.dict(lobbies[lobby_id])["joinable"] = joinable


func set_lobby_member_limit(lobby_id: int, limit: int) -> void:
	Variants.dict(lobbies[lobby_id])["limit"] = limit


func request_lobby_list(filters: Dictionary) -> void:
	calls.append("request_lobby_list")
	var ids: PackedInt64Array = PackedInt64Array()
	for raw: Variant in lobbies.keys():
		var d: Dictionary = Variants.dict(lobbies[raw])["data"]
		var hit: bool = true
		for k: Variant in filters.keys():
			if str(d.get(k, "")) != str(filters[k]):
				hit = false
		if hit:
			ids.append(Variants.whole(raw))
	lobby_list.emit(ids)


func invite_dialog(_lobby_id: int) -> void:
	invites_opened += 1


func is_friend(steam_id_of: int) -> bool:
	return friends_of.has(steam_id_of)


## Test driver: an invite accepted, or "Join Game" from the friends list.
func request_join(lobby_id: int) -> void:
	join_requested.emit(lobby_id)


## Test driver: someone else's lobby, with its data; returns its id.
func add_lobby(owner: int, data: Dictionary) -> int:
	var lid: int = next_lobby
	next_lobby += 1
	lobbies[lid] = {"owner": owner, "limit": 5, "joinable": true, "data": data.duplicate(), "members": [owner], "member_data": {}}
	return lid

class_name LobbyRendezvous
extends RefCounted
## STM-02's dev-mode lobbies: Steam-like lobbies on dev, QA and kill-test servers, which the client's
## fake lobby backend reaches over NET-02's transport on the game port plus net.dev_lobby_port_offset.
## It knows only what clients tell it: their (fake) SteamID and name, and lobby and member data. IDs
## travel as strings (JSON numbers are doubles). Never on a release server.

const FIRST_LOBBY: int = 109775240000000000

var transport: Transport = null
## lobby id -> {owner, limit, joinable, data: {}, members: [id], member_data: {id: {}}}
var lobbies: Dictionary = {}
## peer -> {id, name, lobby}
var peers: Dictionary = {}
var _next: int = FIRST_LOBBY


func _init(listening: Transport) -> void:
	transport = listening


func poll() -> void:
	for ev: TransportEvent in transport.poll():
		match ev.kind:
			TransportEvent.Kind.CONNECTED:
				peers[ev.peer] = {"id": 0, "name": "", "lobby": 0}
			TransportEvent.Kind.DROPPED:
				_leave(ev.peer)
				peers.erase(ev.peer)
			TransportEvent.Kind.MESSAGE:
				if ev.lane == Lane.Id.CONTROL and peers.has(ev.peer):
					_handle(ev.peer, LobbyRendezvousWire.decode(ev.data))
	transport.flush()


func _handle(peer: int, m: Dictionary) -> void:
	var p: Dictionary = peers[peer]
	var lobby: int = Variants.whole(p["lobby"])
	match str(m.get("t", "")):
		"hello":
			p["id"] = str(m.get("id", "0")).to_int()
			p["name"] = str(m.get("name", ""))
		"create":
			_leave(peer)
			var id: int = _next
			_next += 1
			lobbies[id] = {"owner": p["id"], "limit": maxi(1, Variants.whole(m.get("limit", 5))), "joinable": true, "data": {},
				"members": [p["id"]], "member_data": {}}
			p["lobby"] = id
			_send(peer, {"t": "created", "lobby": str(id), "ok": true})
			_send(peer, {"t": "entered", "lobby": str(id), "response": LobbyBackendEnter.SUCCESS})
			_broadcast(id)
		"join":
			var id: int = str(m.get("lobby", "0")).to_int()
			var response: int = _admit(id)
			if response == LobbyBackendEnter.SUCCESS:
				_leave(peer)
				var l: Dictionary = lobbies[id]
				Variants.array(l["members"]).append(p["id"])
				p["lobby"] = id
				_broadcast(id)  # the joiner holds the lobby's data before it hears it is in, as on Steam
			_send(peer, {"t": "entered", "lobby": str(id), "response": response})
		"leave":
			_leave(peer)
		"set_data":
			if lobbies.has(lobby) and Variants.whole(Variants.dict(lobbies[lobby])["owner"]) == Variants.whole(p["id"]):
				Variants.dict(Variants.dict(lobbies[lobby])["data"])[str(m.get("key", ""))] = str(m.get("value", ""))
				_broadcast(lobby)
		"set_member_data":
			if lobbies.has(lobby):
				var md: Dictionary = Variants.dict(Variants.dict(lobbies[lobby])["member_data"])
				var key: String = str(p["id"])
				if not md.has(key):
					md[key] = {}
				Variants.dict(md[key])[str(m.get("key", ""))] = str(m.get("value", ""))
				_broadcast(lobby)
		"set_joinable":
			if lobbies.has(lobby) and Variants.whole(Variants.dict(lobbies[lobby])["owner"]) == Variants.whole(p["id"]):
				Variants.dict(lobbies[lobby])["joinable"] = Variants.flag(m.get("on", true))
		"set_limit":
			if lobbies.has(lobby) and Variants.whole(Variants.dict(lobbies[lobby])["owner"]) == Variants.whole(p["id"]):
				Variants.dict(lobbies[lobby])["limit"] = maxi(1, Variants.whole(m.get("limit", 5)))
		"search":
			_send(peer, {"t": "results", "lobbies": _search(Variants.dict(m.get("filters", {})))})


func _admit(id: int) -> int:
	if not lobbies.has(id):
		return LobbyBackendEnter.DOESNT_EXIST
	var l: Dictionary = lobbies[id]
	if not Variants.flag(l["joinable"]):
		return LobbyBackendEnter.NOT_ALLOWED
	if Variants.array(l["members"]).size() >= Variants.whole(l["limit"]):
		return LobbyBackendEnter.FULL
	return LobbyBackendEnter.SUCCESS


func _search(filters: Dictionary) -> Array:
	var out: Array = []
	for raw: Variant in lobbies.keys():
		var l: Dictionary = lobbies[raw]
		var d: Dictionary = l["data"]
		var hit: bool = true
		for key: Variant in filters.keys():
			if str(d.get(key, "")) != str(filters[key]):
				hit = false
		if hit and Variants.flag(l["joinable"]):
			out.append(str(raw))
	return out


func _leave(peer: int) -> void:
	if not peers.has(peer):
		return
	var p: Dictionary = peers[peer]
	var id: int = Variants.whole(p["lobby"])
	p["lobby"] = 0
	if not lobbies.has(id):
		return
	var l: Dictionary = lobbies[id]
	var members: Array = l["members"]
	members.erase(p["id"])
	Variants.dict(l["member_data"]).erase(str(p["id"]))
	_send(peer, {"t": "left", "lobby": str(id)})
	if members.is_empty():
		lobbies.erase(id)
		return
	if Variants.whole(l["owner"]) == Variants.whole(p["id"]):
		l["owner"] = members[0]  # as Steam does: the owner passes to a member
	_broadcast(id)


func _broadcast(id: int) -> void:
	var l: Dictionary = lobbies[id]
	var members: Array = []
	var md: Dictionary = l["member_data"]
	for raw: Variant in l["members"]:
		var member: int = Variants.whole(raw)
		members.append({"id": str(member), "name": _name_of(member), "data": md.get(str(member), {})})
	var state: Dictionary = {"t": "state", "lobby": str(id), "owner": str(l["owner"]), "limit": l["limit"], "joinable": l["joinable"],
		"data": l["data"], "members": members}
	for peer: Variant in peers.keys():
		if Variants.whole(Variants.dict(peers[peer])["lobby"]) == id:
			_send(Variants.whole(peer), state)


func _name_of(member: int) -> String:
	for raw: Variant in peers.values():
		var p: Dictionary = raw
		if Variants.whole(p["id"]) == member:
			return str(p["name"])
	return ""


func _send(peer: int, message: Dictionary) -> void:
	transport.send(peer, Lane.Id.CONTROL, LobbyRendezvousWire.encode(message))

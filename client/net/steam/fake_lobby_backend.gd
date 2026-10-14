class_name FakeLobbyBackend
extends LobbyBackend
## STM-02's dev-mode lobbies: FakeLobbyBackend talks to the dev server's lobby rendezvous (the game
## port plus net.dev_lobby_port_offset) over NET-02's transport, so --no-steam sessions, bots and
## tests behave like Steam lobbies. Its identity is STM-01's dev identity. There is no overlay.

var transport: Transport = null
var _peer: int = -1
var _up: bool = false
var _id: int = 0
var _name: String = ""
var _queue: Array[Dictionary] = []
var _host: String = ""
var _port: int = 0
var _connecting: bool = false
## Each lobby as the rendezvous last described it (the joined one, and one being joined).
var _states: Dictionary = {}
var _state: Dictionary:
	get:
		return Variants.dict(_states.get(lobby_id, {}))


func _init(over: Transport, steam_id: int, persona: String) -> void:
	transport = over
	_id = steam_id
	_name = persona


## Where the rendezvous is; the first request connects (so a client that never opens the lobby never
## reaches for it).
func aim(host: String, port: int) -> void:
	_host = host
	_port = port


## Connects to the rendezvous at host:port; requests made before it answers are queued.
func start(host: String, port: int) -> bool:
	_host = host
	_port = port
	_connecting = true
	_peer = transport.connect_to(host, port)
	return _peer >= 0


func poll() -> void:
	for ev: TransportEvent in transport.poll():
		match ev.kind:
			TransportEvent.Kind.CONNECTED:
				_up = true
				_connecting = false
				_send({"t": "hello", "id": str(_id), "name": _name})
				for m: Dictionary in _queue:
					_send(m)
				_queue.clear()
			TransportEvent.Kind.DROPPED:
				_up = false
				_connecting = false
				lobby_id = 0
				_states.clear()
				_fail_queued()
			TransportEvent.Kind.MESSAGE:
				if ev.lane == Lane.Id.CONTROL:
					_handle(LobbyRendezvousWire.decode(ev.data))
	transport.flush()


func _handle(m: Dictionary) -> void:
	var id: int = str(m.get("lobby", "0")).to_int()
	match str(m.get("t", "")):
		"created":
			created.emit(Variants.flag(m.get("ok", false)), id)
		"entered":
			var response: int = Variants.whole(m.get("response", LobbyBackendEnter.ERROR))
			if response == LobbyBackendEnter.SUCCESS:
				lobby_id = id
			entered.emit(id, response)
		"state":
			_states[id] = m
			if id == lobby_id:
				changed.emit(id)
		"left":
			_states.erase(id)
			if id == lobby_id:
				lobby_id = 0
		"results":
			var ids: PackedInt64Array = PackedInt64Array()
			for raw: Variant in Variants.array(m.get("lobbies", [])):
				ids.append(str(raw).to_int())
			search_done.emit(ids)


func _send(m: Dictionary) -> void:
	if _up:
		transport.send(_peer, Lane.Id.CONTROL, LobbyRendezvousWire.encode(m))
		return
	_queue.append(m)
	if not _connecting and not _host.is_empty():
		start(_host, _port)  # try the rendezvous again


## The rendezvous could not be reached: each waiting request fails as Steam would report it.
func _fail_queued() -> void:
	for m: Dictionary in _queue:
		match str(m.get("t", "")):
			"create":
				created.emit(false, 0)
			"join":
				entered.emit(str(m.get("lobby", "0")).to_int(), LobbyBackendEnter.ERROR)
			"search":
				search_done.emit(PackedInt64Array())
	_queue.clear()


func self_id() -> int:
	return _id


func create(limit: int) -> void:
	_send({"t": "create", "limit": limit})


func join(id: int) -> void:
	_send({"t": "join", "lobby": str(id)})


func leave() -> void:
	if lobby_id != 0:
		_send({"t": "leave"})
		_states.erase(lobby_id)
		lobby_id = 0


func set_data(key: String, value: String) -> void:
	var st: Dictionary = _states.get_or_add(lobby_id, {})
	Variants.dict(st.get_or_add("data", {}))[key] = value  # as Steam: the owner reads its own write at once
	_send({"t": "set_data", "key": key, "value": value})


func data(key: String) -> String:
	return str(Variants.dict(_state.get("data", {})).get(key, ""))


func set_member_data(key: String, value: String) -> void:
	_send({"t": "set_member_data", "key": key, "value": value})


func member_data(member: int, key: String) -> String:
	for raw: Variant in Variants.array(_state.get("members", [])):
		var m: Dictionary = raw
		if str(m.get("id", "")).to_int() == member:
			return str(Variants.dict(m.get("data", {})).get(key, ""))
	return ""


func members() -> PackedInt64Array:
	var out: PackedInt64Array = PackedInt64Array()
	for raw: Variant in Variants.array(_state.get("members", [])):
		out.append(str(Variants.dict(raw).get("id", "0")).to_int())
	return out


func owner() -> int:
	return str(_state.get("owner", "0")).to_int()


func set_joinable(on: bool) -> void:
	_send({"t": "set_joinable", "on": on})


func set_limit(limit: int) -> void:
	_send({"t": "set_limit", "limit": limit})


func search(filters: Dictionary) -> void:
	_send({"t": "search", "filters": filters})


func member_name(steam_id: int) -> String:
	if steam_id == _id:
		return _name
	for raw: Variant in Variants.array(_state.get("members", [])):
		var m: Dictionary = raw
		if str(m.get("id", "")).to_int() == steam_id:
			return str(m.get("name", ""))
	return ""


func close() -> void:
	transport.close()

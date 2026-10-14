extends RefCounted
## STM-03's test network: fake Steam accounts (fake_steam_api.gd) joined in memory, answering as
## Steam Networking Sockets does: listen sockets by (SteamID, virtual port), connections that wait
## for accept, status changes delivered at the next run_callbacks, and seeded loss, reordering and
## duplication of unreliable messages. Reliable messages always arrive, in order.

var apis: Dictionary = {}
var listeners: Dictionary = {}
var conns: Dictionary = {}
var loss: float = 0.0
var reorder: float = 0.0
var duplicate_share: float = 0.0
var insecure: bool = false
var flushes: int = 0
var global_config: Dictionary = {}
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _next_handle: int = 1000
var _next_socket: int = 65536
var _pending: Dictionary = {}


func _init(seed_value: int = 7) -> void:
	rng.seed = seed_value


func join(api: Object, steam_id: int) -> void:
	apis[steam_id] = api
	_pending[steam_id] = []
	api.set(&"sns_net", self)
	api.set(&"id", steam_id)


func listen(owner: int, vport: int) -> int:
	_next_socket += 1
	listeners["%d:%d" % [owner, vport]] = _next_socket
	return _next_socket


func connect_to(owner: int, remote: int, vport: int) -> int:
	_next_handle += 1
	var mine: int = _next_handle
	conns[mine] = {"owner": owner, "remote": remote, "vport": vport, "peer": 0, "state": 1, "listen": 0, "inbox": []}
	var key: String = "%d:%d" % [remote, vport]
	if not listeners.has(key):
		_status(mine, 5, 4001)
		return mine
	_next_handle += 1
	var theirs: int = _next_handle
	conns[theirs] = {"owner": remote, "remote": owner, "vport": vport, "peer": mine, "state": 1, "listen": listeners[key], "inbox": []}
	Variants.dict(conns[mine])["peer"] = theirs
	_status(theirs, 1, 0)
	return mine


func accept(handle: int) -> int:
	var c: Dictionary = conns[handle]
	c["state"] = 3
	var other: Dictionary = conns[c["peer"]]
	other["state"] = 3
	_status(handle, 3, 0)
	_status(Variants.whole(c["peer"]), 3, 0)
	return 1


func close(handle: int) -> void:
	if not conns.has(handle):
		return
	var c: Dictionary = conns[handle]
	var peer: int = Variants.whole(c["peer"])
	conns.erase(handle)
	if conns.has(peer) and Variants.whole(Variants.dict(conns[peer])["state"]) in [1, 2, 3]:
		Variants.dict(conns[peer])["state"] = 4
		_status(peer, 4, 1000)


## Severs a link as a dead network would: both ends see a problem (the timeout end reason).
func sever(handle: int) -> void:
	var c: Dictionary = conns[handle]
	for h: int in [handle, Variants.whole(c["peer"])]:
		if conns.has(h):
			Variants.dict(conns[h])["state"] = 5
			_status(h, 5, 4001)


func send(handle: int, data: PackedByteArray, flags: int) -> int:
	if not conns.has(handle) or Variants.whole(Variants.dict(conns[handle])["state"]) != 3:
		return 3  # k_EResultNoConnection
	var peer: Dictionary = conns[Variants.dict(conns[handle])["peer"]]
	var inbox: Array = peer["inbox"]
	var reliable: bool = (flags & 8) != 0
	if not reliable:
		if rng.randf() < loss:
			return 1
		if rng.randf() < duplicate_share:
			inbox.append(data)
		if rng.randf() < reorder and not inbox.is_empty():
			inbox.insert(inbox.size() - 1, data)
			return 1
	inbox.append(data)
	return 1


func receive(handle: int, max_messages: int) -> Array:
	if not conns.has(handle):
		return []
	var inbox: Array = Variants.dict(conns[handle])["inbox"]
	var out: Array = []
	while not inbox.is_empty() and out.size() < max_messages:
		out.append({"payload": inbox.pop_front()})
	return out


func info(handle: int) -> Dictionary:
	if not conns.has(handle):
		return {}
	var c: Dictionary = conns[handle]
	return {"identity": c["remote"], "listen_socket": c["listen"], "connection_state": c["state"], "end_reason": 0,
		"end_debug": "", "info_flags": (16 | (3 if insecure else 0))}


func _status(handle: int, state: int, end_reason: int) -> void:
	var c: Dictionary = conns.get(handle, {})
	var owner: int = Variants.whole(c.get("owner", 0))
	if not _pending.has(owner):
		return
	var info_now: Dictionary = {"identity": c.get("remote", 0), "listen_socket": c.get("listen", 0), "connection_state": state,
		"end_reason": end_reason, "end_debug": "fake", "info_flags": (16 | (3 if insecure else 0))}
	Variants.array(_pending[owner]).append([handle, info_now])


## Delivers one account's queued status changes (its run_callbacks).
func deliver(owner: int) -> void:
	var queue: Array = _pending[owner]
	var now: Array = queue.duplicate()
	queue.clear()
	var api: Object = apis[owner]
	for item: Variant in now:
		var it: Array = item
		api.emit_signal(&"sns_status_changed", Variants.whole(it[0]), Variants.dict(it[1]), 0)

class_name HostLink
extends RefCounted
## STM-04: the server side of a private host's control link (GDD §15.10). A loopback ENet listener,
## authenticated by a one-time token printed in the ready line; it carries the lobby's members (the
## admission list for STM-02's rule), the run options, status and shutdown. It also watches the
## parent (the host's client) once a second.

signal shutdown_requested
signal parent_gone
signal members_changed

var transport: EnetTransport = null
var token: String = ""
var control_port: int = 0
var parent_pid: int = 0
var owner: int = 0
var members: PackedInt64Array = PackedInt64Array()
var code_users: Dictionary = {}
var vouched: Dictionary = {}
var options: Dictionary = {}
## (snapshot for a status reply): () -> Dictionary
var status_of: Callable = func() -> Dictionary: return {}
var _authed: Dictionary = {}
var _last_parent_check_usec: int = 0
var _parent_seen_gone: bool = false


func start(port: int, parent: int, build: BuildInfo) -> Error:
	transport = EnetTransport.new()
	transport.build = build
	transport.connection_timeout_usec = 0  # the host may sit in menus; the parent watch covers it
	var error: Error = transport.listen("127.0.0.1", port)
	if error != OK:
		return error
	control_port = transport.bound_port()
	token = Crypto.new().generate_random_bytes(16).hex_encode()
	parent_pid = parent
	_last_parent_check_usec = TickTimer.now_usec()
	return OK


## STM-02's rule at the connection: members only, and of those the owner, code users and vouched
## friends (the seat count is ServerNet's).
func admits(steam_id: int) -> bool:
	return LobbyAdmission.judge(steam_id, owner, members, code_users, vouched, PackedInt64Array(), 1 << 30) == LobbyAdmission.Verdict.SEAT


func poll() -> void:
	if transport == null:
		return
	for ev: TransportEvent in transport.poll():
		match ev.kind:
			TransportEvent.Kind.DROPPED:
				_authed.erase(ev.peer)
			TransportEvent.Kind.MESSAGE:
				if ev.lane == Lane.Id.CONTROL:
					_handle(ev.peer, HostLinkWire.decode(ev.data))
	transport.flush()
	var now: int = TickTimer.now_usec()
	if parent_pid > 0 and not _parent_seen_gone and now - _last_parent_check_usec >= 1000000:
		_last_parent_check_usec = now
		if not Variants.flag(ClassDB.class_call_static(&"LbCoreInfo", &"process_alive", parent_pid)):
			_parent_seen_gone = true
			Log.info("host link: the host's client (pid %d) is gone" % parent_pid)
			parent_gone.emit()


func _handle(peer: int, m: Dictionary) -> void:
	var t: String = str(m.get("t", ""))
	if not _authed.has(peer):
		if t == "auth" and str(m.get("token", "")) == token and not token.is_empty():
			_authed[peer] = true
			_send(peer, {"t": "status"}.merged(Variants.dict(status_of.call())))
		else:
			Log.info("host link: refused a peer without the token")
			transport.disconnect_peer(peer)
		return
	match t:
		"members":
			owner = str(m.get("owner", "0")).to_int()
			members = HostLinkWire.strings_to_ids(m.get("ids", []))
			code_users = {}
			for id: int in HostLinkWire.strings_to_ids(m.get("code_users", [])):
				code_users[id] = true
			vouched = {}
			for id: int in HostLinkWire.strings_to_ids(m.get("vouched", [])):
				vouched[id] = true
			members_changed.emit()
		"options":
			options = Variants.dict(m.get("options", {}))
		"status":
			_send(peer, {"t": "status"}.merged(Variants.dict(status_of.call())))
		"shutdown":
			Log.info("host link: shutdown asked")
			shutdown_requested.emit()


func say_bye(reason: String) -> void:
	for peer: Variant in _authed.keys():
		_send(Variants.whole(peer), {"t": "bye", "reason": reason})
	if transport != null:
		transport.flush()


func _send(peer: int, m: Dictionary) -> void:
	transport.send(peer, Lane.Id.CONTROL, HostLinkWire.encode(m))


func close() -> void:
	if transport != null:
		transport.close()
		transport = null

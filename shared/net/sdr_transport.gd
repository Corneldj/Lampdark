class_name SdrTransport
extends Transport
## STM-03's transport (GDD §15.1): NET-02's Transport over Steam Networking Sockets, peer to peer
## through Valve's relays (ICE disabled: no peer learns another's address), encrypted and
## authenticated, with the remote SteamID verified by Steam. Through STM-01's adapter only.
##
## Lanes. The pinned GodotSteam exposes no per-message lane, so each peer has three connections on
## consecutive virtual ports, each its own send queue: base + 0 carries control and debug (reliable),
## base + 1 bulk (reliable), base + 2 frames, inputs and voice (unreliable), so a big bulk transfer
## never delays voice or frames. Every message starts with its lane byte; unreliable ones then carry a
## 16-bit sequence number per lane, and anything not newer than the last delivered is dropped
## ("unreliable sequenced" whatever the relay does). Reliable messages queue during a tick and leave
## at the tick's flush.
##
## A peer is up when its three connections are; any one closing drops the peer, once. A listener
## admits through `admission` (STM-02's rule, run by the server): (steam_id) -> bool.

const GROUPS: int = 3
## lane -> connection group
const GROUP_OF: Array[int] = [0, 2, 2, 2, 1, 0]
const HEADER_RELIABLE: int = 1
const HEADER_UNRELIABLE: int = 3
const RECEIVE_BATCH: int = 64

var api: SteamApi = null
## Server side: who may connect. Default: anyone signed in (M1 admits any kill-test build).
var admission: Callable = func(_steam_id: int) -> bool: return true
## Connections whose info flags say unauthenticated or unencrypted are refused (never expected).
var insecure_refused: int = 0
var _base_port: int = 0
var _listen_sockets: PackedInt64Array = PackedInt64Array()
var _next_peer: int = 1
## peer -> {steam_id, conns: [handle x3], up: [bool x3], incoming, live}
var _peers: Dictionary = {}
## connection handle -> [peer, group]
var _handles: Dictionary = {}
var _events: Array[TransportEvent] = []
## peer -> {lane: last sequence}, sent and received
var _send_seq: Dictionary = {}
var _recv_seq: Dictionary = {}


func _init(steam_api: SteamApi) -> void:
	super()
	api = steam_api
	api.sns_status_changed.connect(_on_status)
	# Relay only: ICE (direct NAT punch-through) off before any connection, so every connection rides
	# Valve's relays and no peer sees another's address.
	api.sns_set_global_int(SteamApi.SNS_CONFIG_ICE_ENABLE, SteamApi.SNS_ICE_DISABLE)
	if Tuning.current.has_key(&"net.connection_timeout_s"):
		api.sns_set_global_int(SteamApi.SNS_CONFIG_TIMEOUT_CONNECTED, roundi(Tuning.f(&"net.connection_timeout_s") * 1000.0))
	if Tuning.current.has_key(&"net.handshake_timeout_s"):
		api.sns_set_global_int(SteamApi.SNS_CONFIG_TIMEOUT_INITIAL, roundi(Tuning.f(&"net.handshake_timeout_s") * 1000.0))


## Dev and QA builds: Steam's fake lag (ms each way) and loss (percent each way), with reordering of
## 1% of packets when there is loss; 0 and 0 turn them off. Refused (false) in release builds.
static func set_fake_conditions(steam_api: SteamApi, build_info: BuildInfo, lag_ms: int, loss_pct: float) -> bool:
	if build_info.is_release():
		return false
	var ok: bool = steam_api.sns_set_global_int(SteamApi.SNS_CONFIG_FAKE_LAG_SEND, lag_ms / 2)
	ok = steam_api.sns_set_global_int(SteamApi.SNS_CONFIG_FAKE_LAG_RECV, lag_ms - lag_ms / 2) and ok
	ok = steam_api.sns_set_global_float(SteamApi.SNS_CONFIG_FAKE_LOSS_SEND, loss_pct / 2.0) and ok
	ok = steam_api.sns_set_global_float(SteamApi.SNS_CONFIG_FAKE_LOSS_RECV, loss_pct / 2.0) and ok
	ok = steam_api.sns_set_global_float(SteamApi.SNS_CONFIG_FAKE_REORDER_SEND, 1.0 if loss_pct > 0.0 else 0.0) and ok
	return ok


## `port` is the base virtual port (net.sdr_virtual_port); the bind address means nothing here.
func _listen(_bind_address: String, port: int) -> Error:
	_base_port = port
	for g: int in GROUPS:
		var socket: int = api.sns_listen(port + g)
		if socket == 0:
			_close_listeners()
			return ERR_CANT_CREATE
		_listen_sockets.append(socket)
	return OK


## `host` is the remote SteamID (decimal); `port` its base virtual port.
func _connect(host: String, port: int) -> int:
	var remote: int = host.to_int()
	if remote == 0 or not host.is_valid_int():
		return -1
	var peer: int = _new_peer(remote, false)
	var p: Dictionary = _peers[peer]
	var conns: Array = p["conns"]
	for g: int in GROUPS:
		var handle: int = api.sns_connect(remote, port + g)
		if handle == 0:
			_drop(peer, "refused")
			return -1
		conns[g] = handle
		_handles[handle] = [peer, g]
	return peer


func _new_peer(steam_id: int, incoming: bool) -> int:
	var peer: int = _next_peer
	_next_peer += 1
	_peers[peer] = {"steam_id": steam_id, "conns": [0, 0, 0], "up": [false, false, false], "incoming": incoming, "live": false}
	_send_seq[peer] = {}
	_recv_seq[peer] = {}
	return peer


## The SteamID Steam authenticated for this peer (the server checks Hello.identity against it).
func verified_identity(peer: int) -> String:
	return str(Variants.whole(Variants.dict(_peers.get(peer, {})).get("steam_id", 0))) if _peers.has(peer) else ""


func _on_status(handle: int, info: Dictionary, _old_state: int) -> void:
	var state: int = Variants.whole(info.get("connection_state", 0))
	var listen_socket: int = Variants.whole(info.get("listen_socket", 0))
	if not _handles.has(handle):
		if listen_socket == 0 or not _listen_sockets.has(listen_socket) or state != SteamApi.SnsState.CONNECTING:
			return
		_incoming(handle, info, listen_socket)
		return
	var where: Array = _handles[handle]
	var peer: int = where[0]
	var group: int = where[1]
	match state:
		SteamApi.SnsState.CONNECTED:
			var flags: int = Variants.whole(api.sns_info(handle).get("info_flags", info.get("info_flags", 0)))
			if (flags & (SteamApi.SNS_INFO_UNAUTHENTICATED | SteamApi.SNS_INFO_UNENCRYPTED)) != 0:
				insecure_refused += 1
				_drop(peer, "insecure")
				return
			var p: Dictionary = _peers[peer]
			var up: Array = p["up"]
			up[group] = true
			if not Variants.flag(p["live"]) and not up.has(false):
				p["live"] = true
				_events.append(TransportEvent.connected(peer))
		SteamApi.SnsState.CLOSED_BY_PEER:
			_drop(peer, "disconnected")
		SteamApi.SnsState.PROBLEM:
			_drop(peer, "timeout" if Variants.whole(info.get("end_reason", 0)) in [4001, 5003] else "problem: %s" % info.get("end_debug", ""))


func _incoming(handle: int, info: Dictionary, listen_socket: int) -> void:
	var remote: int = Variants.whole(info.get("identity", 0))
	var group: int = _listen_sockets.find(listen_socket)
	if remote == 0 or not Variants.flag(admission.call(remote)):
		api.sns_close(handle, SteamApi.SNS_END_APP_GENERIC, "not admitted", false)
		return
	# The three connections from one SteamID make one peer.
	var peer: int = -1
	for raw: Variant in _peers.keys():
		var p: Dictionary = _peers[raw]
		var conns: Array = p["conns"]
		if Variants.flag(p["incoming"]) and Variants.whole(p["steam_id"]) == remote and Variants.whole(conns[group]) == 0:
			peer = Variants.whole(raw)
			break
	if peer < 0:
		peer = _new_peer(remote, true)
	var target: Array = Variants.dict(_peers[peer])["conns"]
	target[group] = handle
	_handles[handle] = [peer, group]
	if api.sns_accept(handle) != 1:
		_drop(peer, "refused")


func _send_raw(peer: int, lane: int, data: PackedByteArray) -> Error:
	if not _peers.has(peer):
		return ERR_DOES_NOT_EXIST
	var conns: Array = Variants.dict(_peers[peer])["conns"]
	var handle: int = Variants.whole(conns[GROUP_OF[lane]])
	var reliable: bool = Lane.is_reliable(lane)
	var head: PackedByteArray = PackedByteArray([lane])
	if not reliable:
		var seqs: Dictionary = _send_seq[peer]
		var seq: int = (Variants.whole(seqs.get(lane, 0)) + 1) & 0xFFFF
		seqs[lane] = seq
		head.append(seq & 0xFF)
		head.append(seq >> 8)
	head.append_array(data)
	var result: int = api.sns_send(handle, head, SteamApi.SNS_SEND_RELIABLE if reliable else SteamApi.SNS_SEND_UNRELIABLE)
	return OK if result == 1 else ERR_CONNECTION_ERROR


func _poll_raw() -> Array[TransportEvent]:
	var out: Array[TransportEvent] = _events.duplicate()
	_events.clear()
	for raw: Variant in _peers.keys():
		var peer: int = Variants.whole(raw)
		var p: Dictionary = _peers[peer]
		if not Variants.flag(p["live"]):
			continue
		for handle: Variant in Variants.array(p["conns"]):
			# Drain: a batch that comes back full may have more behind it.
			while true:
				var batch: Array = api.sns_receive(Variants.whole(handle), RECEIVE_BATCH)
				for m: Variant in batch:
					var payload: PackedByteArray = Variants.dict(m).get("payload", PackedByteArray())
					var ev: TransportEvent = _unwrap(peer, payload)
					if ev != null:
						out.append(ev)
				if batch.size() < RECEIVE_BATCH:
					break
		_refresh_stats(peer)
	return out


## A message's lane and, for unreliable lanes, its sequence; null when malformed or not newer.
func _unwrap(peer: int, payload: PackedByteArray) -> TransportEvent:
	if payload.is_empty() or payload[0] >= Lane.COUNT:
		return null
	var lane: int = payload[0]
	if Lane.is_reliable(lane):
		return TransportEvent.message(peer, lane, payload.slice(HEADER_RELIABLE))
	if payload.size() < HEADER_UNRELIABLE:
		return null
	var seq: int = payload[1] | (payload[2] << 8)
	var last: Dictionary = _recv_seq[peer]
	if last.has(lane):
		var ahead: int = (seq - Variants.whole(last[lane])) & 0xFFFF
		if ahead == 0 or ahead >= 0x8000:
			return null  # a duplicate, or older than what was delivered
	last[lane] = seq
	return TransportEvent.message(peer, lane, payload.slice(HEADER_UNRELIABLE))


## Steam's real-time status into NET-02's stats: ping as the round trip, 1 - quality as loss.
func _refresh_stats(peer: int) -> void:
	var conns: Array = Variants.dict(_peers[peer])["conns"]
	# GodotSteam nests the figures: {response, connection_status: {ping, local_quality, ...}, lanes_status}.
	var s: Dictionary = Variants.dict(api.sns_status(Variants.whole(conns[0])).get("connection_status", {}))
	if s.is_empty():
		return
	var st: PeerStats = stats(peer)
	st.rtt_ms = float(Variants.number(s.get("ping", st.rtt_ms)))
	var quality: float = float(Variants.number(s.get("local_quality", -1.0)))
	if quality >= 0.0:
		st.loss = clampf(1.0 - quality, 0.0, 1.0)  # -1 while Steam has no estimate yet


func _flush() -> void:
	for raw: Variant in _peers.values():
		var p: Dictionary = raw
		if Variants.flag(p["live"]):
			for handle: Variant in Variants.array(p["conns"]):
				api.sns_flush(Variants.whole(handle))


func _disconnect(peer: int) -> void:
	_close_peer(peer, "closed")


func _drop(peer: int, reason: String) -> void:
	if not _peers.has(peer):
		return
	var was_live: bool = Variants.flag(Variants.dict(_peers[peer])["live"])
	_close_peer(peer, reason)
	if was_live:
		_events.append(TransportEvent.dropped(peer, reason))


func _close_peer(peer: int, reason: String) -> void:
	if not _peers.has(peer):
		return
	var p: Dictionary = _peers[peer]
	for handle: Variant in Variants.array(p["conns"]):
		var h: int = Variants.whole(handle)
		if h != 0:
			_handles.erase(h)
			api.sns_close(h, SteamApi.SNS_END_APP_GENERIC, reason, true)
	_peers.erase(peer)
	_send_seq.erase(peer)
	_recv_seq.erase(peer)


func _close() -> void:
	for raw: Variant in _peers.keys():
		_close_peer(Variants.whole(raw), "closed")
	_close_listeners()
	if api.sns_status_changed.is_connected(_on_status):
		api.sns_status_changed.disconnect(_on_status)


func _close_listeners() -> void:
	for socket: int in _listen_sockets:
		api.sns_close_listen(socket)
	_listen_sockets.clear()

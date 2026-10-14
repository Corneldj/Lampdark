class_name HostRelay
extends RefCounted
## STM-04's Path B (--host-relay, and every source run): the host's client holds STM-03's SDR listen
## socket under the host's SteamID and gives each admitted friend a dedicated loopback ENet connection
## to the local server. Before anything else it sends a relay tag (the host link's token and the
## friend's authenticated SteamID), so the server checks the friend's Hello against Steam's word.
## It forwards every lane both ways untouched and never reads or alters a game message; a drop on
## either side drops the other.

var sdr: SdrTransport = null
var game_port: int = 0
var token: String = ""
## sdr peer -> {enet: EnetTransport, peer: int, up: bool, queue: [[lane, data]], steam_id: int}
var _links: Dictionary = {}
var relayed: int = 0


func _init(sdr_transport: SdrTransport, server_game_port: int, host_token: String) -> void:
	sdr = sdr_transport
	game_port = server_game_port
	token = host_token


func listen(vport: int) -> Error:
	return sdr.listen("", vport)


func poll() -> void:
	for ev: TransportEvent in sdr.poll():
		match ev.kind:
			TransportEvent.Kind.CONNECTED:
				_open(ev.peer)
			TransportEvent.Kind.MESSAGE:
				_to_server(ev.peer, ev.lane, ev.data)
			TransportEvent.Kind.DROPPED:
				_close(ev.peer)
	for raw: Variant in _links.keys():
		var friend: int = Variants.whole(raw)
		if not _links.has(friend):
			continue
		var l: Dictionary = _links[friend]
		var enet: EnetTransport = l["enet"]
		for ev: TransportEvent in enet.poll():
			match ev.kind:
				TransportEvent.Kind.CONNECTED:
					l["up"] = true
					enet.send(Variants.whole(l["peer"]), Lane.Id.CONTROL, Protocol.relay_tag(token, Variants.whole(l["steam_id"])))
					for q: Variant in Variants.array(l["queue"]):
						var item: Array = q
						var queued: PackedByteArray = item[1]
						enet.send(Variants.whole(l["peer"]), Variants.whole(item[0]), queued)
					Variants.array(l["queue"]).clear()
				TransportEvent.Kind.MESSAGE:
					sdr.send(friend, ev.lane, ev.data)
					relayed += 1
				TransportEvent.Kind.DROPPED:
					sdr.disconnect_peer(friend)
					_links.erase(friend)
		enet.flush()
	sdr.flush()


func _open(friend: int) -> void:
	var enet: EnetTransport = EnetTransport.new()
	var peer: int = enet.connect_to("127.0.0.1", game_port)
	_links[friend] = {"enet": enet, "peer": peer, "up": false, "queue": [], "steam_id": sdr.verified_identity(friend).to_int()}


func _to_server(friend: int, lane: int, data: PackedByteArray) -> void:
	if not _links.has(friend):
		return
	var l: Dictionary = _links[friend]
	if Variants.flag(l["up"]):
		var enet: EnetTransport = l["enet"]
		enet.send(Variants.whole(l["peer"]), lane, data)
		relayed += 1
	else:
		Variants.array(l["queue"]).append([lane, data])


func _close(friend: int) -> void:
	if _links.has(friend):
		var l: Dictionary = _links[friend]
		var enet: EnetTransport = l["enet"]
		enet.disconnect_peer(Variants.whole(l["peer"]))
		enet.flush()
		enet.close()
		_links.erase(friend)


func close() -> void:
	for raw: Variant in _links.keys():
		_close(Variants.whole(raw))
	sdr.close()

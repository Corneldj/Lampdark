class_name InProcessTransport
extends Transport
## A transport inside one process, for the scenario kit (NET-02, Proposed). Endpoints meet
## through a Hub by name; messages arrive at the next poll, in order, never lost. The same
## game code runs over it unchanged.

class Hub:
	extends RefCounted
	## name -> listening InProcessTransport
	var listeners: Dictionary = {}


var hub: Hub
var _name: String = ""
## peer id -> [other InProcessTransport, the id this endpoint has on the other side]
var _links: Dictionary = {}
var _inbox: Array[TransportEvent] = []
var _next_peer: int = 1


func _init(shared_hub: Hub) -> void:
	super()
	hub = shared_hub


func _listen(bind_address: String, port: int) -> Error:
	_name = "%s:%d" % [bind_address, port]
	if hub.listeners.has(_name):
		return ERR_ALREADY_IN_USE
	hub.listeners[_name] = self
	return OK


func _connect(host: String, port: int) -> int:
	var key: String = "%s:%d" % [host, port]
	if not hub.listeners.has(key):
		return -1
	var server: InProcessTransport = hub.listeners[key]
	var my_id: int = _next_peer
	_next_peer += 1
	var their_id: int = server._next_peer
	server._next_peer += 1
	_links[my_id] = [server, their_id]
	server._links[their_id] = [self, my_id]
	_inbox.append(TransportEvent.connected(my_id))
	server._inbox.append(TransportEvent.connected(their_id))
	return my_id


func _send_raw(peer: int, lane: int, data: PackedByteArray) -> Error:
	if not _links.has(peer):
		return ERR_DOES_NOT_EXIST
	var link: Array = _links[peer]
	var other: InProcessTransport = link[0]
	other._inbox.append(TransportEvent.message(int(Variants.number(link[1])), lane, data.duplicate()))
	return OK


func _poll_raw() -> Array[TransportEvent]:
	var events: Array[TransportEvent] = _inbox
	_inbox = []
	return events


## Every in-process peer shares this process.
func _is_local(_peer: int) -> bool:
	return true


func _disconnect(peer: int) -> void:
	if not _links.has(peer):
		return
	var link: Array = _links[peer]
	_links.erase(peer)
	var other: InProcessTransport = link[0]
	var their_id: int = int(Variants.number(link[1]))
	if other._links.erase(their_id):
		other._inbox.append(TransportEvent.dropped(their_id, "disconnected"))


func _close() -> void:
	for peer: Variant in _links.keys():
		_disconnect(int(Variants.number(peer)))
	if not _name.is_empty():
		hub.listeners.erase(_name)

class_name TransportEvent
extends RefCounted
## One thing a transport reports from poll(): a peer connected, dropped, or sent a message.

enum Kind { CONNECTED, DROPPED, MESSAGE }

var kind: Kind
var peer: int
var lane: int = -1
var data: PackedByteArray = PackedByteArray()
## Why a peer dropped: "timeout", "disconnected", "closed" or "refused".
var reason: String = ""


static func connected(peer_id: int) -> TransportEvent:
	var event: TransportEvent = TransportEvent.new()
	event.kind = Kind.CONNECTED
	event.peer = peer_id
	return event


static func dropped(peer_id: int, why: String) -> TransportEvent:
	var event: TransportEvent = TransportEvent.new()
	event.kind = Kind.DROPPED
	event.peer = peer_id
	event.reason = why
	return event


static func message(peer_id: int, on_lane: int, bytes: PackedByteArray) -> TransportEvent:
	var event: TransportEvent = TransportEvent.new()
	event.kind = Kind.MESSAGE
	event.peer = peer_id
	event.lane = on_lane
	event.data = bytes
	return event

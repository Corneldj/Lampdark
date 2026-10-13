class_name Protocol
## Message framing and schemas (NET-02). Every message is a type byte, a 32-bit payload
## length, then the payload. Both protocol_version and build_id must match exactly at the
## handshake; no game data is sent before Welcome. Unknown types are dropped and counted.

## 2: FND-08's handshake carries the build flavour and the QA token, and Welcome the debug grant.
const PROTOCOL_VERSION: int = 2

enum Msg {
	HELLO = 1,
	WELCOME = 2,
	REJECT = 3,
	PING = 4,
	PONG = 5,
	FRAME = 6,  ## NET-04: one client's frame (core/net/client_view; client/net/frame_decoder.gd)
	INPUT = 7,  ## NET-03: the client's input packet, every tick, on the inputs lane
	VOICE = 8,  ## SND-07 defines the contents; until then a band byte and a dummy payload (FND-09's bots)
	INVENTORY = 9,  ## MNR-04: the own miner's hands and belt (InventoryWire), control lane, owner only
	FEEL = 10,  ## VIS-07: a feel answer or a wall bump (FeelMessages), control lane, owner only
	RING = 11,  ## MNR-05: the interact ring's options and a body's belt (RingMessages), to the actor only
	AMBIENT = 12,  ## SND-03: an ambient bed layer starts or stops (AmbientMessages), control lane, one client
	DEAFENED = 13,  ## SND-04: the own miner is deafened (DeafenedMessages), control lane, that client only
	DEBUG_COMMAND = 14,  ## FND-08, debug lane only: a console line, client to server
	DEBUG_REPLY = 15,  ## FND-08, debug lane only: a command's answer, to its issuer
	DEBUG_SUBSCRIBE = 16,  ## FND-08, debug lane only: the client's truth layers and overlay switch
	DEBUG_TRUTH = 17,  ## FND-08, debug lane only: a truth-view snapshot (5 Hz)
	DEBUG_TAG = 18,  ## FND-08, debug lane only, QA and dev servers: an illusion's id, by tick and record number
}

enum Reject {
	VERSION_MISMATCH = 1,
	FULL = 2,
	REMOVED = 3,
	RUN_CLOSED = 4,
	AUTH_FAILED = 5,
	BAD_MESSAGE = 6,
	FLAVOUR_MISMATCH = 7,  ## FND-08: a release build never meets a dev or QA one
}

enum Seat { PLAYER = 0, BOT = 1 }


## The build identity both ends compare: the native core's version and git SHA.
static func build_id() -> String:
	if ClassDB.class_exists(&"LbCoreInfo"):
		return str(ClassDB.class_call_static(&"LbCoreInfo", &"version"))
	return "unknown"


static func reject_name(reason: int) -> String:
	return str(Reject.find_key(reason)).to_lower()


## Wraps a payload with its type and length.
static func frame(type: Msg, payload: PackedByteArray) -> PackedByteArray:
	var buffer: StreamPeerBuffer = StreamPeerBuffer.new()
	buffer.put_u8(type)
	buffer.put_u32(payload.size())
	buffer.put_data(payload)
	return buffer.data_array


## Splits a framed message. Returns {type, payload}, or {} if malformed.
static func unframe(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 5:
		return {}
	var buffer: StreamPeerBuffer = StreamPeerBuffer.new()
	buffer.data_array = bytes
	var type: int = buffer.get_u8()
	var length: int = buffer.get_u32()
	if length != bytes.size() - 5:
		return {}
	return {"type": type, "payload": bytes.slice(5)}


class Hello:
	extends RefCounted
	var protocol_version: int = PROTOCOL_VERSION
	var build_id: String = ""
	var identity: String = ""
	var seat_request: int = Seat.PLAYER
	var session_token: String = ""
	## FND-08: BuildInfo.Flavour (a release client never joins a dev or QA server, nor the reverse)
	## and the QA token that asks for the debug channel ("" for none).
	var flavour: int = BuildInfo.Flavour.RELEASE
	var qa_token: String = ""

	func encode() -> PackedByteArray:
		var b: StreamPeerBuffer = StreamPeerBuffer.new()
		b.put_u16(protocol_version)
		b.put_utf8_string(build_id)
		b.put_utf8_string(identity)
		b.put_u8(seat_request)
		b.put_utf8_string(session_token)
		b.put_u8(flavour)
		b.put_utf8_string(qa_token)
		return Protocol.frame(Msg.HELLO, b.data_array)

	static func decode(payload: PackedByteArray) -> Hello:
		var b: StreamPeerBuffer = StreamPeerBuffer.new()
		b.data_array = payload
		var hello: Hello = Hello.new()
		hello.protocol_version = b.get_u16()
		hello.build_id = b.get_utf8_string()
		hello.identity = b.get_utf8_string()
		hello.seat_request = b.get_u8()
		hello.session_token = b.get_utf8_string()
		if b.get_available_bytes() > 0:
			hello.flavour = b.get_u8()
			hello.qa_token = b.get_utf8_string()
		return hello


class Welcome:
	extends RefCounted
	var slot: int = 0
	var session_token: String = ""
	var tick_hz: int = 20
	var server_tick: int = 0
	var server_time_us: int = 0
	var run_phase: int = 0
	var client_tuning_hash: String = ""
	## FND-05's client table as JSON, only when its hash differs from the client's shipped one.
	var client_tuning: String = ""
	## FND-08: this client may use the debug channel (a dev or QA server, and its QA token or a
	## local dev run).
	var debug: bool = false

	func encode() -> PackedByteArray:
		var b: StreamPeerBuffer = StreamPeerBuffer.new()
		b.put_u8(slot)
		b.put_utf8_string(session_token)
		b.put_u16(tick_hz)
		b.put_64(server_tick)
		b.put_64(server_time_us)
		b.put_u8(run_phase)
		b.put_utf8_string(client_tuning_hash)
		b.put_utf8_string(client_tuning)
		b.put_u8(1 if debug else 0)
		return Protocol.frame(Msg.WELCOME, b.data_array)

	static func decode(payload: PackedByteArray) -> Welcome:
		var b: StreamPeerBuffer = StreamPeerBuffer.new()
		b.data_array = payload
		var welcome: Welcome = Welcome.new()
		welcome.slot = b.get_u8()
		welcome.session_token = b.get_utf8_string()
		welcome.tick_hz = b.get_u16()
		welcome.server_tick = b.get_64()
		welcome.server_time_us = b.get_64()
		welcome.run_phase = b.get_u8()
		welcome.client_tuning_hash = b.get_utf8_string()
		welcome.client_tuning = b.get_utf8_string()
		welcome.debug = b.get_available_bytes() > 0 and b.get_u8() == 1
		return welcome


static func reject(reason: Reject) -> PackedByteArray:
	var b: StreamPeerBuffer = StreamPeerBuffer.new()
	b.put_u8(reason)
	return frame(Msg.REJECT, b.data_array)


static func ping(client_time_us: int) -> PackedByteArray:
	var b: StreamPeerBuffer = StreamPeerBuffer.new()
	b.put_64(client_time_us)
	return frame(Msg.PING, b.data_array)


static func pong(client_time_us: int, server_time_us: int) -> PackedByteArray:
	var b: StreamPeerBuffer = StreamPeerBuffer.new()
	b.put_64(client_time_us)
	b.put_64(server_time_us)
	return frame(Msg.PONG, b.data_array)


## The frame header until NET-04: the tick, the newest one-shot action applied for this client
## (NET-03's exactly-once acknowledgement) and the client's input buffer depth (NET-05 nudges
## its clock to hold the target).
## Reads the first 64-bit field of a payload (pings and pongs).
static func read_i64(payload: PackedByteArray, index: int = 0) -> int:
	var b: StreamPeerBuffer = StreamPeerBuffer.new()
	b.data_array = payload
	b.seek(index * 8)
	return b.get_64()


static func read_u8(payload: PackedByteArray) -> int:
	return payload[0] if not payload.is_empty() else -1

extends TransportFilter
## Everything the server sent one client, as that client received it (FND-09): raw bytes per
## lane with the scenario tick and virtual time of arrival, and every frame decoded through
## NET-04's real client decoder (its own instance, fed the same frames in the same order).

## The scenario's current tick, set by the kit before each poll.
var tick: int = 0
## Array of {tick, usec, lane, type, bytes}
var messages: Array[Dictionary] = []
## tick -> that tick's messages, so per-tick lookups stay constant-time over a long soak.
var _by_tick: Dictionary = {}
var decoder: FrameDecoder = FrameDecoder.new()
## scenario tick -> the ReceivedView after the frames that arrived in it
var views: Dictionary = {}
## Every audio event received, each once, in arrival order.
var received_events: Array[Dictionary] = []
var _numbers: Dictionary = {}
## Called with each decoded frame (NET-05's reconciler in the kit).
var on_decoded: Callable = Callable()
## Long soaks only (NET-07's 3-hour record soak): keep this many ticks of messages, views and
## events, and count bytes as they pass. 0 keeps everything.
var keep_ticks: int = 0
var _trimmed_to: int = 0
var _lane_bytes: Dictionary = {}


func filter_receive(events: Array[TransportEvent]) -> Array[TransportEvent]:
	if keep_ticks > 0:
		_trim()
	for event: TransportEvent in events:
		if event.kind != TransportEvent.Kind.MESSAGE:
			continue
		var message: Dictionary = Protocol.unframe(event.data)
		var type: int = int(Variants.number(message.get("type", -1))) if not message.is_empty() else -1
		var record: Dictionary = {"tick": tick, "usec": Transport.now_usec(), "lane": event.lane, "type": type,
			"bytes": event.data.duplicate()}
		messages.append(record)
		if keep_ticks > 0:
			_lane_bytes[event.lane] = int(Variants.number(_lane_bytes.get(event.lane, 0))) + event.data.size()
		if not _by_tick.has(tick):
			_by_tick[tick] = [] as Array[Dictionary]
		var at: Array[Dictionary] = _by_tick[tick]
		at.append(record)
		if type == Protocol.Msg.FRAME:
			var payload: PackedByteArray = message["payload"]
			var decoded: FrameDecoder.Decoded = decoder.decode(payload)
			if decoded.ok:
				views[tick] = decoded.view
				if on_decoded.is_valid():
					on_decoded.call(decoded)
				for e: Dictionary in decoded.events:
					if not _numbers.has(e["number"]):
						_numbers[e["number"]] = true
						var stamped: Dictionary = e.duplicate()
						stamped["arrived"] = tick
						received_events.append(stamped)
	return events


## Raw messages, optionally on one lane.
func raw(lane: int = -1) -> Array[PackedByteArray]:
	var out: Array[PackedByteArray] = []
	for m: Dictionary in messages:
		if lane < 0 or int(Variants.number(m["lane"])) == lane:
			var bytes: PackedByteArray = m["bytes"]
			out.append(bytes)
	return out


func messages_at(at_tick: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _by_tick.has(at_tick):
		var at: Array[Dictionary] = _by_tick[at_tick]
		out.assign(at)
	return out


## Bytes that arrived during one tick, all lanes.
func bytes_sent(at_tick: int) -> int:
	var total: int = 0
	for m: Dictionary in messages_at(at_tick):
		var bytes: PackedByteArray = m["bytes"]
		total += bytes.size()
	return total


func bytes_by_lane() -> Dictionary:
	var out: Dictionary = {}
	if keep_ticks > 0:
		for lane: Variant in _lane_bytes.keys():
			out[Lane.lane_name(int(Variants.number(lane)))] = _lane_bytes[lane]
		return out
	for m: Dictionary in messages:
		var bytes: PackedByteArray = m["bytes"]
		var lane: String = Lane.lane_name(int(Variants.number(m["lane"])))
		out[lane] = int(Variants.number(out.get(lane, 0))) + bytes.size()
	return out


## The tick of every frame received, in order.
func frame_ticks() -> PackedInt64Array:
	var out: PackedInt64Array = PackedInt64Array()
	for m: Dictionary in messages:
		if int(Variants.number(m["type"])) == Protocol.Msg.FRAME:
			var bytes: PackedByteArray = m["bytes"]
			var payload: PackedByteArray = Variants.dict(Protocol.unframe(bytes)).get("payload", PackedByteArray())
			out.append(int(Variants.number(FrameDecoder.header(payload)["tick"])))
	return out


## One SHA-256 over every message (tick, lane and bytes), for determinism checks.
func digest() -> String:
	var ctx: HashingContext = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for m: Dictionary in messages:
		var head: PackedByteArray = PackedByteArray()
		head.resize(12)
		head.encode_s64(0, int(Variants.number(m["tick"])))
		head.encode_s32(8, int(Variants.number(m["lane"])))
		ctx.update(head)
		var bytes: PackedByteArray = m["bytes"]
		ctx.update(bytes)
	return ctx.finish().hex_encode()


## NET-04's client decoder is in use.
func decoder_ready() -> bool:
	return true


## The view the client held at the end of a scenario tick (the latest frame decoded by then),
## or null before the first frame.
func records_at(at_tick: int) -> ReceivedView:
	var best: int = -1
	for key: Variant in views.keys():
		var t: int = int(Variants.number(key))
		if t <= at_tick and t > best:
			best = t
	return views[best] if best >= 0 else null


## The entities the client held at a tick: {level, size_or_kind, position, facing?}, by token.
func entities_visible(at_tick: int) -> Dictionary:
	var view: ReceivedView = records_at(at_tick)
	return view.entities if view != null else {}


## Audio events that started within [from_tick, to_tick], each once.
func audio_events(from_tick: int, to_tick: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in received_events:
		var start: int = int(Variants.number(e["start_tick"]))
		if start >= from_tick and start <= to_tick:
			out.append(e)
	return out


## The caption keys of those events (UI-03 lays them out).
func captions(from_tick: int, to_tick: int) -> Array[String]:
	var out: Array[String] = []
	for e: Dictionary in audio_events(from_tick, to_tick):
		out.append("caption.noise." + NoiseTypes.id_of(int(Variants.number(e["type"])) as NoiseTypes.Type))
	return out


## Feel replies (VIS-07): none are sent yet, so none are received.
func feel_results() -> Array:
	return []


## The per-tick index (a reconnect's fresh capture carries it over with `messages`).
func index_by_tick() -> Dictionary:
	return _by_tick


## A reconnect's fresh capture keeps everything the old one received.
func carry_over(old_messages: Array[Dictionary], old_index: Dictionary) -> void:
	messages = old_messages
	_by_tick = old_index


## Drops what arrived more than keep_ticks ago, a few seconds at a time.
func _trim() -> void:
	var cut: int = tick - keep_ticks
	if cut - _trimmed_to < 200:
		return
	var i: int = 0
	while i < messages.size() and int(Variants.number(messages[i]["tick"])) < cut:
		i += 1
	messages = messages.slice(i)
	for t: int in range(_trimmed_to, cut):
		_by_tick.erase(t)
		views.erase(t)
	received_events = received_events.filter(func(e: Dictionary) -> bool: return int(Variants.number(e["arrived"])) >= cut)
	_trimmed_to = cut

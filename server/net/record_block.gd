class_name RecordBlock
extends RefCounted
## NET-07: one keyframe interval of the run record (net.record_keyframe_s), sealed and compressed.
## The authoritative track and each client's stream are each a keyframe part and a per-tick part,
## kept as zstd bytes with their raw size. A thinned keyframe (the budget, GDD §15.3) is empty: a
## reader then decodes on from an earlier block's keyframe. Server-only, and never audio: a voice
## frame is kept as its band, speaker and listeners (GDD §15.6).
##
## The authoritative keyframe: {ids, kinds, xy, flags} (the entity mirror), sources (LbLightGrid's
## sources_packed) and doors {key: [open, centre]}. Its ticks, one dictionary each, keep only what
## happened: t, m [moved ids, xy], c [[id, kind, x, y, flags]], x (destroyed ids), fl [[id, flags]],
## s (every source, when any changed), d [[door, open]], n (sounds), v [[speaker, band, listener
## bits]], g (CRT-01's creature log), dr (NET-06's decisions), lie (CRT-10's lie log), fall, death.
## A stream's keyframe: {held (the newest view's frame tick, or -1), views {frame tick: view}}. Its
## ticks: f [[tick, bytes, received, arrival_ms, illusion numbers]], l [[tick, origin, light bytes]]
## (the true light of the client's 30x17 frame), r [[tick, rtt_ms]].


## One compressed part: a Variant as var_to_bytes, then zstd.
class Part:
	extends RefCounted
	var raw: int = 0
	var bytes: PackedByteArray = PackedByteArray()

	static func pack(value: Variant) -> Part:
		var p: Part = Part.new()
		var plain: PackedByteArray = var_to_bytes(value)
		p.raw = plain.size()
		p.bytes = plain.compress(FileAccess.COMPRESSION_ZSTD)
		return p

	static func from_array(a: Array) -> Part:
		var p: Part = Part.new()
		if a.size() == 2:
			p.raw = int(Variants.number(a[0]))
			var b: Variant = a[1]
			p.bytes = b if b is PackedByteArray else PackedByteArray()
		return p

	func unpack() -> Variant:
		if raw <= 0 or bytes.is_empty():
			return null
		return bytes_to_var(bytes.decompress(raw, FileAccess.COMPRESSION_ZSTD))

	func empty() -> bool:
		return bytes.is_empty()

	func size() -> int:
		return bytes.size()

	func to_array() -> Array:
		return [raw, bytes]


## The block's first tick and its length in ticks.
var start: int = 0
var ticks: int = 0
var auth_key: Part = Part.new()
var auth: Part = Part.new()
## slot -> {"key": Part, "frames": Part}
var streams: Dictionary = {}


## The last tick the block covers.
func last() -> int:
	return start + ticks - 1


func overlaps(from_tick: int, to_tick: int) -> bool:
	return start <= to_tick and last() >= from_tick


## Compressed bytes held.
func size() -> int:
	var n: int = auth_key.size() + auth.size()
	for raw: Variant in streams.values():
		var parts: Dictionary = raw
		var key: Part = parts["key"]
		var frames: Part = parts["frames"]
		n += key.size() + frames.size()
	return n


## A copy holding the authoritative track and one slot's stream only (a pinned window's share).
## The bytes are shared until either side lets go of them.
func only(slot: int) -> RecordBlock:
	var b: RecordBlock = RecordBlock.new()
	b.start = start
	b.ticks = ticks
	b.auth_key = auth_key
	b.auth = auth
	if streams.has(slot):
		var parts: Dictionary = streams[slot]
		b.streams[slot] = {"key": parts["key"], "frames": parts["frames"]}
	return b


## Drops the keyframes (the budget's thinning). Returns the bytes freed.
func thin() -> int:
	var freed: int = auth_key.size()
	auth_key = Part.new()
	for raw: Variant in streams.values():
		var parts: Dictionary = raw
		var key: Part = parts["key"]
		freed += key.size()
		parts["key"] = Part.new()
	return freed


func has_keyframes() -> bool:
	return not auth_key.empty()


func auth_keyframe() -> Dictionary:
	return Variants.dict(auth_key.unpack())


func auth_ticks() -> Array:
	return Variants.array(auth.unpack())


func stream_keyframe(slot: int) -> Dictionary:
	if not streams.has(slot):
		return {}
	var parts: Dictionary = streams[slot]
	var key: Part = parts["key"]
	return Variants.dict(key.unpack())


func stream_ticks(slot: int) -> Dictionary:
	if not streams.has(slot):
		return {}
	var parts: Dictionary = streams[slot]
	var frames: Part = parts["frames"]
	return Variants.dict(frames.unpack())


## Plain values only (NET-09 saves them with snapshots and knock-off saves).
func to_dict() -> Dictionary:
	var s: Dictionary = {}
	for raw: Variant in streams.keys():
		var parts: Dictionary = streams[raw]
		var key: Part = parts["key"]
		var frames: Part = parts["frames"]
		s[raw] = {"key": key.to_array(), "frames": frames.to_array()}
	return {"start": start, "ticks": ticks, "auth_key": auth_key.to_array(), "auth": auth.to_array(), "streams": s}


static func from_dict(d: Dictionary) -> RecordBlock:
	var b: RecordBlock = RecordBlock.new()
	b.start = int(Variants.number(d.get("start", 0)))
	b.ticks = int(Variants.number(d.get("ticks", 0)))
	b.auth_key = Part.from_array(Variants.array(d.get("auth_key", [])))
	b.auth = Part.from_array(Variants.array(d.get("auth", [])))
	var s: Dictionary = Variants.dict(d.get("streams", {}))
	for raw: Variant in s.keys():
		var parts: Dictionary = Variants.dict(s[raw])
		b.streams[int(Variants.number(raw))] = {"key": Part.from_array(Variants.array(parts.get("key", []))),
			"frames": Part.from_array(Variants.array(parts.get("frames", [])))}
	return b

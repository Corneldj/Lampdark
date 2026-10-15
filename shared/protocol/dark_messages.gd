class_name DarkMessages
extends RefCounted
## RSC-04's two streams to a fallen client, both made only of NET-04 frames another client (or this
## one) was sent, so they hold nothing a frame could not:
##   WATCH (Protocol.Msg.WATCH): a conscious teammate's frames as they were sent to them,
##     rescue.watch_delay_s late. `reset` starts a new stream with `views` (the decoded keyframe a
##     FrameDecoder starts from, ReceivedView.to_dict by frame tick); `ended` closes it (the watched
##     miner fell, or the watcher stopped).
##   REPLAY (Protocol.Msg.REPLAY): the victim's own frames before their fall, once, in parts.
## Plain values only (var_to_bytes without objects).


static func watch(reset: bool, views: Dictionary, frames: Array, ended: bool = false) -> PackedByteArray:
	return var_to_bytes({"reset": reset, "views": views, "frames": frames, "ended": ended})


static func replay(part: int, of: int, views: Dictionary, frames: Array) -> PackedByteArray:
	return var_to_bytes({"part": part, "of": of, "views": views, "frames": frames})


## {} when malformed. Frames come back as [[tick, bytes], ...] with ints and byte arrays checked.
static func decode(payload: PackedByteArray) -> Dictionary:
	var v: Variant = bytes_to_var(payload) if payload.size() > 0 else null
	if not v is Dictionary:
		return {}
	var d: Dictionary = v
	var frames: Array = []
	for raw: Variant in Variants.array(d.get("frames", [])):
		var f: Array = Variants.array(raw)
		if f.size() != 2 or not (f[0] is int) or not (f[1] is PackedByteArray):
			return {}
		frames.append(f)
	d["frames"] = frames
	d["views"] = Variants.dict(d.get("views", {}))
	return d

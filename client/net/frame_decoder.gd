class_name FrameDecoder
extends RefCounted
## NET-04's client decoder: each frame applies its records to the baseline it names (a frame
## the client decoded earlier), giving the view the client now holds. Mirrors the native
## encoder's layout (core/net/client_view.cpp) byte for byte; a malformed frame, or one whose
## baseline the client no longer has, decodes to nothing and is not acknowledged.

const VERSION: int = 4
const FLAG_FULL: int = 1
const FLAG_BLINDED: int = 2
## VIS-09: the moth's dust settles on every lit tile this client sees.
const FLAG_DUST: int = 4


class Decoded:
	extends RefCounted
	var ok: bool = false
	var tick: int = 0
	var baseline_tick: int = -1
	var full: bool = false
	var action_ack: int = 0xFFFF
	## The seq of the input the server applied this tick (NET-05 reconciles against it).
	var input_ack: int = 0xFFFF
	var input_depth: int = 0
	var view: ReceivedView = null
	## {number, type, start_tick, apparent (Vector2), remaining_np, duration_s, voice (or absent)}
	var events: Array[Dictionary] = []
	## What this frame itself carried (NET-08's audit judges these): the tiles and geometry it
	## upserted, the tokens it upserted, and whether it carried the glow.
	var tiles_sent: Array[Vector2i] = []
	var geometry_sent: Array[Vector2i] = []
	var tokens_sent: Array[int] = []
	var glow_sent: bool = false


## Bounds-checked little-endian reading: an underrun flags the reader instead of erroring.
class Reader:
	extends RefCounted
	var data: PackedByteArray
	var at: int = 0
	var ok: bool = true

	func _init(bytes: PackedByteArray) -> void:
		data = bytes

	func u8() -> int:
		if at + 1 > data.size():
			ok = false
			return 0
		at += 1
		return data[at - 1]

	func u16() -> int:
		var lo: int = u8()
		return lo | (u8() << 8)

	func u32() -> int:
		var lo: int = u16()
		return lo | (u16() << 16)

	func i8() -> int:
		var v: int = u8()
		return v - 256 if v >= 128 else v

	func i16() -> int:
		var v: int = u16()
		return v - 65536 if v >= 32768 else v

	func i32() -> int:
		var v: int = u32()
		return v - 0x100000000 if v >= 0x80000000 else v


var held_cells: int = 2
## How many decoded frames to keep as possible baselines.
var keep_frames: int = 64
## frame tick -> ReceivedView
var history: Dictionary = {}


func _init() -> void:
	if Tuning.current.has_key(&"vision.held_geometry_cells"):
		held_cells = Tuning.i(&"vision.held_geometry_cells")


## The header fields of a frame without decoding the rest: {tick, action_ack, input_ack, input_depth}.
static func header(payload: PackedByteArray) -> Dictionary:
	var r: Reader = Reader.new(payload)
	if r.u8() != VERSION:
		return {}
	var tick: int = r.u32()
	r.u16()
	var action_ack: int = r.u16()
	var input_ack: int = r.u16()
	var depth: int = r.u8()
	return {"tick": tick, "action_ack": action_ack, "input_ack": input_ack, "input_depth": depth} if r.ok else {}


func reset() -> void:
	history.clear()


func decode(payload: PackedByteArray) -> Decoded:
	var d: Decoded = Decoded.new()
	var r: Reader = Reader.new(payload)
	if r.u8() != VERSION:
		return d
	d.tick = r.u32()
	var age: int = r.u16()
	d.action_ack = r.u16()
	d.input_ack = r.u16()
	d.input_depth = r.u8()
	var flags: int = r.u8()
	d.full = (flags & FLAG_FULL) != 0
	var view: ReceivedView
	if age == 0:
		view = ReceivedView.new()
	else:
		d.baseline_tick = d.tick - age
		if not history.has(d.baseline_tick):
			return d
		var base: ReceivedView = history[d.baseline_tick]
		view = base.duplicate_view()
	var x256: int = r.i32()
	var y256: int = r.i32()
	view.own = {"position": Vector2(x256 / 256.0, y256 / 256.0), "facing": r.u16(), "gait": r.u8(), "speed_q": r.u8(), "flags": r.u16(),
		"stamina_q": r.u8(), "lamp_radius": r.u8() / 16.0, "flame": r.u8()}
	view.blinded = (flags & FLAG_BLINDED) != 0
	view.dust = (flags & FLAG_DUST) != 0
	view.apply_held_rule(held_cells)
	var own: Vector2i = Vector2i(floori(x256 / 256.0), floori(y256 / 256.0))
	for _i: int in r.u16():
		var t: Vector2i = own + Vector2i(r.i8(), r.i8())
		view.tiles[t] = PackedByteArray([r.u8(), r.u8(), r.u8()])
		d.tiles_sent.append(t)
	for _i: int in r.u16():
		view.tiles.erase(own + Vector2i(r.i8(), r.i8()))
	for _i: int in r.u16():
		var t: Vector2i = own + Vector2i(r.i8(), r.i8())
		view.geometry[t] = PackedByteArray([r.u8(), r.u8()])
		d.geometry_sent.append(t)
	for _i: int in r.u16():
		var token: int = r.u16()
		var level: int = r.u8()
		var e: Dictionary = {"level": level, "size_or_kind": r.u8()}
		var dx: int = r.i16()
		var dy: int = r.i16()
		e["position"] = Vector2(own.x + dx / 64.0, own.y + dy / 64.0)
		if level == 2:
			e["facing"] = r.u16()
			e["cues"] = r.u16()
			e["in_hand"] = r.u16()
			e["flame"] = r.u8()
		view.entities[token] = e
		d.tokens_sent.append(token)
	for _i: int in r.u16():
		view.entities.erase(r.u16())
	if r.u8() == 1:
		d.glow_sent = true
		view.glow_mask = r.u32()
		view.glow_colour = PackedByteArray()
		view.glow_colour.resize(32)
		for b: int in 32:
			if (view.glow_mask >> b) & 1:
				view.glow_colour[b] = r.u8()
	for _i: int in r.u8():
		var ev: Dictionary = {"number": r.u16(), "type": r.u8(), "start_tick": r.u32()}
		var ax: int = r.i16()
		var ay: int = r.i16()
		ev["apparent"] = Vector2(own.x + ax / 16.0, own.y + ay / 16.0)
		ev["remaining_np"] = r.u8() / 4.0
		ev["level_np"] = r.u8() / 4.0
		ev["duration_s"] = r.u8() / 10.0
		var event_flags: int = r.u8()
		ev["flags"] = event_flags & 0x7F
		if (event_flags & 0x80) != 0:
			ev["voice"] = r.u8()
		ev["gain_db"] = r.i8()
		var points: Array[Vector2] = []
		var at: Vector2 = ev["apparent"]
		for _k: int in r.u8():
			var px: int = r.i16()
			var py: int = r.i16()
			points.append(at + Vector2(px / 16.0, py / 16.0))
		ev["points"] = points
		d.events.append(ev)
	d.ok = r.ok and r.at == payload.size()
	if not d.ok:
		d.events.clear()
		return d
	d.view = view
	history[d.tick] = view
	for raw: Variant in history.keys():
		if int(Variants.number(raw)) < d.tick - keep_frames:
			history.erase(raw)
	return d

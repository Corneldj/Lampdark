class_name SaveContainer
extends RefCounted
## NET-09's save container (GDD §15.10): the magic LMPB, the format version, a plain header (the
## run's UUID, the snapshot's sequence number and its parent's hash, the build, generator,
## template-set and data-bundle versions it resumes on, its kind), a section table, then each
## section zstd-compressed and sealed (LbSeal). Seeds, stream states and everything else of the run
## live only inside sealed sections. The server builds and opens containers; a client only ever
## stores the bytes it was sent, assembling a file from its parts without opening any.

const MAGIC: PackedByteArray = [0x4C, 0x4D, 0x50, 0x42]  # "LMPB"
const FORMAT: int = 1


## The container: `header` (plain values) and `sections` (name -> plain bytes, sealed here).
static func build(header: Dictionary, sections: Dictionary) -> PackedByteArray:
	var sealed: Dictionary = {}
	var names: Array = sections.keys()
	names.sort()
	for raw: Variant in names:
		var plain: PackedByteArray = sections[raw]
		sealed[str(raw)] = seal_section(plain)
	return assemble(header, sealed, PackedStringArray(names))


## One section as it travels and is stored: compressed, then sealed.
static func seal_section(plain: PackedByteArray) -> PackedByteArray:
	var packed: PackedByteArray = PackedByteArray()
	packed.resize(4)
	packed.encode_u32(0, plain.size())
	packed.append_array(plain.compress(FileAccess.COMPRESSION_ZSTD) if not plain.is_empty() else PackedByteArray())
	return LbSeal.seal(packed)


## The file from a plain header and already sealed sections, in `order` (a client assembles its
## copy this way, opening nothing).
static func assemble(header: Dictionary, sealed: Dictionary, order: PackedStringArray) -> PackedByteArray:
	var out: StreamPeerBuffer = StreamPeerBuffer.new()
	out.put_data(MAGIC)
	out.put_u16(FORMAT)
	var h: PackedByteArray = var_to_bytes(header)
	out.put_u32(h.size())
	out.put_data(h)
	out.put_u16(order.size())
	for n: String in order:
		var blob: PackedByteArray = sealed[n]
		var name_bytes: PackedByteArray = n.to_utf8_buffer()
		out.put_u16(name_bytes.size())
		out.put_data(name_bytes)
		out.put_u32(blob.size())
	for n: String in order:
		var blob: PackedByteArray = sealed[n]
		out.put_data(blob)
	return out.data_array


## Only the plain header, or {} if the bytes are no container (no section is opened).
static func read_header(bytes: PackedByteArray) -> Dictionary:
	var parts: Dictionary = _split(bytes)
	return Variants.dict(parts.get("header", {}))


## {ok, error ("" | "format" | "seal"), header, sections: name -> plain bytes}. A section that fails
## its seal (tampered, or sealed by another build's keys) refuses the whole save.
static func open(bytes: PackedByteArray) -> Dictionary:
	var parts: Dictionary = _split(bytes)
	if parts.is_empty():
		return {"ok": false, "error": "format", "header": {}, "sections": {}}
	var out: Dictionary = {}
	var sealed: Dictionary = parts["sealed"]
	for raw: Variant in sealed.keys():
		var blob: PackedByteArray = sealed[raw]
		var packed: PackedByteArray = LbSeal.open(blob)
		if packed.size() < 4:
			return {"ok": false, "error": "seal", "header": parts["header"], "sections": {}}
		var size: int = packed.decode_u32(0)
		out[raw] = packed.slice(4).decompress(size, FileAccess.COMPRESSION_ZSTD) if size > 0 else PackedByteArray()
	return {"ok": true, "error": "", "header": parts["header"], "sections": out}


## Sizes on disk by section (sealed), and in all.
static func sizes(bytes: PackedByteArray) -> Dictionary:
	var parts: Dictionary = _split(bytes)
	var out: Dictionary = {"total": bytes.size()}
	for raw: Variant in Variants.dict(parts.get("sealed", {})).keys():
		var blob: PackedByteArray = parts["sealed"][raw]
		out[raw] = blob.size()
	return out


## The SHA-256 of the container (the next snapshot's parent hash).
static func hash_of(bytes: PackedByteArray) -> String:
	var h: HashingContext = HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(bytes)
	return h.finish().hex_encode()


static func _split(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 12 or bytes.slice(0, 4) != MAGIC:
		return {}
	var b: StreamPeerBuffer = StreamPeerBuffer.new()
	b.data_array = bytes
	b.seek(4)
	if b.get_u16() != FORMAT:
		return {}
	var hsize: int = b.get_u32()
	if b.get_position() + hsize > bytes.size():
		return {}
	var header: Variant = bytes_to_var(bytes.slice(b.get_position(), b.get_position() + hsize))
	b.seek(b.get_position() + hsize)
	if not header is Dictionary:
		return {}
	var n: int = b.get_u16()
	var table: Array = []
	for _i: int in n:
		var nlen: int = b.get_u16()
		if b.get_position() + nlen > bytes.size():
			return {}
		var section: String = bytes.slice(b.get_position(), b.get_position() + nlen).get_string_from_utf8()
		b.seek(b.get_position() + nlen)
		table.append([section, b.get_u32()])
	var sealed: Dictionary = {}
	var at: int = b.get_position()
	for row: Array in table:
		var size: int = row[1]
		if at + size > bytes.size():
			return {}
		sealed[row[0]] = bytes.slice(at, at + size)
		at += size
	if at != bytes.size():
		return {}
	return {"header": header, "sealed": sealed}

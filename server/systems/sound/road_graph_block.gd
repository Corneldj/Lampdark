class_name RoadGraphBlock
## A cell's Road Graph block (SND-01, format v0) as readable JSON for cell files, and its
## binary form for the native graph:
## {"zones": [{"id", "kind"}], "portals": [{"id", "kind", "a", "b", "barrier", "tiles"}]}.
## Zone kinds: road, chamber, poi, base_camp. Portal kinds: opening, air_door, gate.
## Tiles are local indices (y * 20 + x). An empty block {} encodes to no bytes.

const VERSION: int = 0
const ZONE_KINDS: Array[String] = ["road", "chamber", "poi", "base_camp"]
const PORTAL_KINDS: Array[String] = ["opening", "air_door", "gate"]


static func encode(block: Dictionary) -> PackedByteArray:
	if block.is_empty():
		return PackedByteArray()
	var b: StreamPeerBuffer = StreamPeerBuffer.new()
	b.big_endian = false
	b.put_u8(VERSION)
	var zones: Array = Variants.array(block.get("zones", []))
	b.put_u16(zones.size())
	for raw: Variant in zones:
		var z: Dictionary = Variants.dict(raw)
		b.put_u16(int(Variants.number(z.get("id", 0))))
		b.put_u8(maxi(ZONE_KINDS.find(str(z.get("kind", "road"))), 0))
	var portals: Array = Variants.array(block.get("portals", []))
	b.put_u16(portals.size())
	for raw: Variant in portals:
		var p: Dictionary = Variants.dict(raw)
		b.put_u16(int(Variants.number(p.get("id", 0))))
		b.put_u8(maxi(PORTAL_KINDS.find(str(p.get("kind", "opening"))), 0))
		b.put_u16(int(Variants.number(p.get("a", 0))))
		b.put_u16(int(Variants.number(p.get("b", 0))))
		b.put_u32(int(Variants.number(p.get("barrier", 0))))
		var tiles: Array = Variants.array(p.get("tiles", []))
		b.put_u16(tiles.size())
		for t: Variant in tiles:
			b.put_u16(int(Variants.number(t)))
	return b.data_array


static func decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.is_empty():
		return {}
	var b: StreamPeerBuffer = StreamPeerBuffer.new()
	b.data_array = bytes
	if b.get_u8() != VERSION:
		push_error("RoadGraphBlock: unknown block version")
		return {}
	var zones: Array = []
	for _i: int in b.get_u16():
		var id: int = b.get_u16()
		var kind: int = b.get_u8()
		zones.append({"id": id, "kind": ZONE_KINDS[kind] if kind < ZONE_KINDS.size() else "road"})
	var portals: Array = []
	for _i: int in b.get_u16():
		var id: int = b.get_u16()
		var kind: int = b.get_u8()
		var a: int = b.get_u16()
		var z: int = b.get_u16()
		var barrier: int = b.get_u32()
		var tiles: Array = []
		for _t: int in b.get_u16():
			tiles.append(b.get_u16())
		portals.append({"id": id, "kind": PORTAL_KINDS[kind] if kind < PORTAL_KINDS.size() else "opening",
			"a": a, "b": z, "barrier": barrier, "tiles": tiles})
	return {"zones": zones, "portals": portals}

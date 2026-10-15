class_name ReceivedView
extends RefCounted
## What a client holds after one frame (NET-04): seen tiles' light, held geometry, entities by
## per-client token, the edge glow and its own miner. Absolute tile coordinates, decoded from
## positions sent relative to the own miner. Nothing here names a server entity.

## Vector2i -> PackedByteArray [light 0-255, colour class, decal bits]
var tiles: Dictionary = {}
## Vector2i -> PackedByteArray [material, state]
var geometry: Dictionary = {}
## token -> {level (1 token, 2 identity, 3 hidden margin token: VIS-04, drawn only once the
## predicted own light reaches it), size or kind, position (Vector2); identity only: facing,
## cues (MinerCues bits), in_hand (MNR-04: lamp-hand kind low byte, bit 7 hooked; free-hand kind high byte)}
var entities: Dictionary = {}
var glow_mask: int = 0
## 32 dominant colour classes, by bucket
var glow_colour: PackedByteArray = PackedByteArray()
## {position (Vector2), facing, gait (255 still), speed_q, flags, stamina_q (0.05 s steps; only
## for NET-05 to predict when running stops, never drawn)}
var own: Dictionary = {"position": Vector2.ZERO, "facing": 0, "gait": 255, "speed_q": 100, "flags": 0, "stamina_q": 120,
	"lamp_radius": 0.0}
var blinded: bool = false
## VIS-09: dust settles on every lit tile this client sees (the moth is awake or stirring near).
var dust: bool = false


func _init() -> void:
	glow_colour.resize(32)


func duplicate_view() -> ReceivedView:
	var v: ReceivedView = ReceivedView.new()
	v.tiles = tiles.duplicate()
	v.geometry = geometry.duplicate()
	v.entities = entities.duplicate(true)
	v.glow_mask = glow_mask
	v.glow_colour = glow_colour.duplicate()
	v.own = own.duplicate()
	v.blinded = blinded
	v.dust = dust
	return v


## Plain values (NET-07's run record keeps decoded views as keyframes).
func to_dict() -> Dictionary:
	return {"tiles": tiles.duplicate(), "geometry": geometry.duplicate(), "entities": entities.duplicate(true), "glow_mask": glow_mask,
		"glow_colour": glow_colour.duplicate(), "own": own.duplicate(), "blinded": blinded, "dust": dust}


static func from_dict(d: Dictionary) -> ReceivedView:
	var v: ReceivedView = ReceivedView.new()
	v.tiles = Variants.dict(d.get("tiles", {})).duplicate()
	v.geometry = Variants.dict(d.get("geometry", {})).duplicate()
	v.entities = Variants.dict(d.get("entities", {})).duplicate(true)
	v.glow_mask = int(Variants.number(d.get("glow_mask", 0)))
	var colour: Variant = d.get("glow_colour", PackedByteArray())
	if colour is PackedByteArray:
		var bytes: PackedByteArray = colour
		v.glow_colour = bytes.duplicate()
	v.own = Variants.dict(d.get("own", v.own)).duplicate()
	v.blinded = Variants.flag(d.get("blinded", false))
	v.dust = Variants.flag(d.get("dust", false))
	return v


## Equal content (NET-07 compares a rebuilt view with the client's own).
func same_as(other: ReceivedView) -> bool:
	return other != null and to_dict() == other.to_dict()


func own_tile() -> Vector2i:
	var p: Vector2 = own["position"]
	return Vector2i(floori(p.x), floori(p.y))


## The held-geometry rule both sides apply: keep cells within `held_cells` of the own cell.
func apply_held_rule(held_cells: int) -> void:
	var own_cell: Vector2i = Vector2i(floori(float(own_tile().x) / WorldIds.CELL_TILES), floori(float(own_tile().y) / WorldIds.CELL_TILES))
	for raw: Variant in geometry.keys():
		var t: Vector2i = raw
		var c: Vector2i = Vector2i(floori(float(t.x) / WorldIds.CELL_TILES), floori(float(t.y) / WorldIds.CELL_TILES))
		if absi(c.x - own_cell.x) > held_cells or absi(c.y - own_cell.y) > held_cells:
			geometry.erase(t)

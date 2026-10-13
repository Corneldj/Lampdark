class_name Medbay
extends RefCounted
## LFT-01: two first-aid tables (one body each, Proposed) and the cupboard with
## basecamp.medbay_cupboard_kits healing kits. Revival and laying bodies are RSC-02's and
## MNR-13's; taking a kit is MNR-04's pick-up rule.

var tables: Array[Vector2i] = []
## table tile -> the body on it (0: empty)
var bodies: Dictionary = {}
var cupboard: Vector2i = Vector2i.ZERO
var kits: int = 0


func install(seed_value: int, side: int) -> void:
	for a: Dictionary in Basecamp.fixture(seed_value, "medbay_table", side):
		var t: Vector2i = a["position"]
		tables.append(t)
		bodies[t] = 0
	cupboard = Basecamp.fixture(seed_value, "medbay_cupboard", side)[0]["position"]
	kits = Tuning.i(&"basecamp.medbay_cupboard_kits")


## Takes a kit from the cupboard (MNR-04 calls it); false when none is left.
func take_kit() -> bool:
	if kits <= 0:
		return false
	kits -= 1
	return true


## A body lifted off its table (MNR-13): the table is free again.
func take_off(body: int) -> void:
	for t: Vector2i in tables:
		if int(Variants.number(bodies[t])) == body:
			bodies[t] = 0


## Lays a body on a free table (RSC-02, MNR-13); false when that table holds one.
func lay(table: Vector2i, body: int) -> bool:
	if not bodies.has(table) or int(Variants.number(bodies[table])) != 0:
		return false
	bodies[table] = body
	return true

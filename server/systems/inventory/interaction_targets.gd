class_name InteractionTargets
extends RefCounted
## MNR-04's interaction target (Proposed): among the interactables in touch range that the miner
## sees with identity (VIS-03's identified set as of the last frame), or the thing just felt
## (VIS-07), the one closest to the facing ray, then the nearest, then the lowest id. Items come
## from ItemWorld; other owners add providers (LFT-02's levers). UI-01's glyph reads the same pick.
## Server-only.

## (run, actor: int, at: Vector2, reach: float) -> Array of {kind: StringName, id: int, point: Vector2}
var providers: Array[Callable] = []
## actor -> the item entity last felt (VIS-07 calls note_felt).
var felt: Dictionary = {}


func note_felt(actor: int, entity: int) -> void:
	felt[actor] = entity


## Every candidate for `actor` (on `slot`), unsorted.
func candidates(run: RunState, actor: int, slot: int, world: ItemWorld) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var me: SimEntity = run.registry.get_entity(actor)
	if me == null:
		return out
	var reach: float = Tuning.f(&"vision.touch_range_tiles")
	var seen: Dictionary = {}
	if run.vision != null:
		var frame: Dictionary = run.vision.frame_for(slot)
		var identified: PackedInt64Array = frame.get("identified", PackedInt64Array())
		for id: int in identified:
			seen[id] = true
	var felt_entity: int = int(Variants.number(felt.get(actor, 0)))
	var ids: Array = world.items.keys()
	ids.sort()
	for raw: Variant in ids:
		var id: int = int(Variants.number(raw))
		if not seen.has(id) and id != felt_entity:
			continue
		# MNR-14: a load is never picked up; LoadCarry and TubRails offer it as their own target.
		var lying: Item = world.items[raw]
		if ItemKinds.is_load(lying.kind):
			continue
		var e: SimEntity = run.registry.get_entity(id)
		if e != null and me.position.distance_to(e.position) <= reach:
			out.append({"kind": &"item", "id": id, "point": e.position})
	for p: Callable in providers:
		for raw: Variant in Variants.array(p.call(run, actor, me.position, reach)):
			out.append(Variants.dict(raw))
	return out


## The target for `actor`, or {} if none.
func pick(run: RunState, actor: int, slot: int, world: ItemWorld) -> Dictionary:
	var all: Array[Dictionary] = candidates(run, actor, slot, world)
	if all.is_empty():
		return {}
	var me: Vector2 = run.registry.get_entity(actor).position
	var facing: int = run.movement.facing_of(slot) if run.movement != null and run.movement.miner(slot) != null else 0
	var u: PackedFloat64Array = LbDetMath.unit(float(facing) / 65536.0)
	var ray: Vector2 = Vector2(u[0], u[1])
	var best: Dictionary = {}
	var best_key: Array = []
	for c: Dictionary in all:
		var p: Vector2 = c["point"]
		var d: Vector2 = p - me
		var length: float = d.length()
		var along: float = 1.0 if length < 1e-6 else ray.dot(d / length)
		var key: Array = [-along, length, str(c["kind"]), int(Variants.number(c["id"]))]
		if best.is_empty() or _less(key, best_key):
			best = c
			best_key = key
	return best


static func _less(a: Array, b: Array) -> bool:
	for i: int in a.size():
		if a[i] != b[i]:
			return a[i] < b[i]
	return false

class_name StateDicts
extends RefCounted
## NET-09: plain values for snapshots. Named fields of an object to and from a dictionary, and
## items (MNR-04) with every state. Server-only.


static func pick(obj: Object, names: Array[String]) -> Dictionary:
	var out: Dictionary = {}
	for n: String in names:
		var v: Variant = obj.get(n)
		if v is Dictionary:
			out[n] = Variants.dict(v).duplicate(true)
		elif v is Array:
			out[n] = Variants.array(v).duplicate(true)
		else:
			out[n] = v
	return out


static func put(obj: Object, d: Dictionary) -> void:
	for raw: Variant in d.keys():
		var n: String = str(raw)
		var v: Variant = d[raw]
		var current: Variant = obj.get(n)
		# Typed arrays keep their type: fill rather than replace.
		if current is Array and v is Array:
			var arr: Array = current
			arr.clear()
			arr.append_array(Variants.array(v))
		else:
			obj.set(n, v)


static func item_to(it: Item) -> Variant:
	if it == null:
		return null
	return {"uid": it.uid, "kind": it.kind, "count": it.count, "state": it.state.duplicate(true), "placement": it.placement}


static func item_from(d: Variant) -> Item:
	if d == null or not d is Dictionary:
		return null
	var v: Dictionary = d
	var it: Item = Item.new()
	it.uid = int(Variants.number(v["uid"]))
	it.kind = int(Variants.number(v["kind"])) as ItemKinds.Kind
	it.count = int(Variants.number(v["count"]))
	it.state = Variants.dict(v["state"]).duplicate(true)
	it.placement = str(v.get("placement", ""))
	return it

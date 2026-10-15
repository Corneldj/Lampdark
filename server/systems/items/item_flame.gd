class_name ItemFlame
extends SimSystem
## MNR-09: what candles and flares share. A burning item carries `state.lit` and `state.burn_ticks`
## (its remaining time). Each tick, wherever MNR-04 holds it (a hand, the floor), it burns a tick,
## registers its VIS-02 source (`light_kind`, held: FLAME | CARRIED with its holder as owner;
## lying: FLAME | UNHELD, owner 0; plus `extra_flags`), and signals LampSystem.naked_flame for
## HAZ-04 on lighting and on every tile it enters, with `flame_cause` ("lit_candle",
## "burning_flare"; MNR-07's relights keep "candle" and "passed_flame"). Burnt out, it is gone.
## Server-only.

## uid -> {source, owner, flags}
var sources: Dictionary = {}
## uid -> the tile it last burned on
var last_tile: Dictionary = {}
## Every lighting, burn-out and snuff: {tick, uid, what, cause}.
var history: Array[Dictionary] = []
var _run: RunState = null


func item_kind() -> ItemKinds.Kind:
	return ItemKinds.Kind.NONE


func light_kind() -> String:
	return ""


func colour() -> int:
	return LbLightGrid.COLOUR_AMBER


func extra_flags() -> int:
	return 0


func radius() -> float:
	return 0.0


func full_burn_ticks() -> int:
	return 0


## The naked_flame cause of this kind's burning items.
func flame_cause() -> String:
	return ""


static func burning(it: Item) -> bool:
	return it != null and Variants.flag(it.state.get("lit", false))


## A newly lit item of this kind (one from a stack): its remaining time kept, else a full burn.
func lit_item(run: RunState, from: Item) -> Item:
	var left: int = int(Variants.number(from.state.get("burn_ticks", full_burn_ticks())))
	var it: Item = from if from.count == 1 else run.inventory.world.make(item_kind(), 1, from.state)
	if from.count > 1:
		from.count -= 1
	it.state["lit"] = true
	it.state["burn_ticks"] = left
	return it


func lit_at(run: RunState, it: Item, tile: Vector2i, cause: String) -> void:
	history.append({"tick": run.tick, "uid": it.uid, "what": &"lit", "cause": cause})
	last_tile[it.uid] = tile
	if run.lamps != null:
		run.lamps.naked_flame.emit(tile, flame_cause())


## Burns, moves the light and drops burnt-out items. `on_place` (optional) may act on each burning
## place first and return false to skip it (a candle put on the belt goes out).
func burn(run: RunState) -> void:
	_run = run
	var seen: Dictionary = {}
	for place: Dictionary in ItemPlaces.of_kind(run, item_kind()):
		var it: Item = place["item"]
		if not burning(it) or not keep_burning(run, place):
			continue
		# A burning item made elsewhere with no time on it (a found lit candle) has its full burn.
		if not it.state.has("burn_ticks"):
			it.state["burn_ticks"] = full_burn_ticks()
		var left: int = int(Variants.number(it.state["burn_ticks"]))
		if left <= 0:
			history.append({"tick": run.tick, "uid": it.uid, "what": &"burnt_out", "cause": ""})
			ItemPlaces.remove(run, place, &"burnt_out")
			continue
		seen[it.uid] = true
		_light(run, it, place)
		it.state["burn_ticks"] = left - 1
	for raw: Variant in sources.keys():
		if not seen.has(raw):
			_unlight(run, int(Variants.number(raw)))


## Whether a burning item keeps burning where it is (a subclass may put it out).
func keep_burning(_r: RunState, _place: Dictionary) -> bool:
	return true


func _light(run: RunState, it: Item, place: Dictionary) -> void:
	var pos: Vector2 = place["position"]
	var tile: Vector2i = Vector2i(floori(pos.x), floori(pos.y))
	if not last_tile.has(it.uid) or last_tile[it.uid] != tile:
		last_tile[it.uid] = tile
		if run.lamps != null:
			run.lamps.naked_flame.emit(tile, flame_cause())
	if run.light == null:
		return
	var holder: int = int(Variants.number(place["holder"]))
	var flags: int = LbLightGrid.FLAG_FLAME | extra_flags() | (LbLightGrid.FLAG_CARRIED if holder != 0 else LbLightGrid.FLAG_UNHELD)
	var s: Dictionary = sources.get(it.uid, {})
	if not s.is_empty() and int(Variants.number(s["owner"])) != holder:
		_unlight(run, it.uid, false)
		s = {}
	if s.is_empty():
		var id: int = run.light.grid.add_point(light_kind(), colour(), holder, flags, radius(), 1.0, pos, 0)
		sources[it.uid] = {"source": id, "owner": holder, "flags": flags}
		return
	var id: int = int(Variants.number(s["source"]))
	if int(Variants.number(s["flags"])) != flags:
		run.light.grid.set_flags(id, flags)
		s["flags"] = flags
	run.light.grid.update_point(id, pos, radius(), 1.0)


## Removes a burning item's light; `forget_tile` false when it is only re-registered (a new holder).
func _unlight(run: RunState, uid: int, forget_tile: bool = true) -> void:
	var s: Dictionary = sources.get(uid, {})
	if not s.is_empty() and run.light != null:
		run.light.grid.remove_source(int(Variants.number(s["source"])))
	sources.erase(uid)
	if forget_tile:
		last_tile.erase(uid)


## The VIS-02 source of a burning item, 0 if none.
func source_of(it: Item) -> int:
	return int(Variants.number(Variants.dict(sources.get(it.uid, {})).get("source", 0)))


## The burning item whose source is `source`, or null.
func item_of_source(run: RunState, source: int) -> Item:
	for place: Dictionary in ItemPlaces.of_kind(run, item_kind()):
		var it: Item = place["item"]
		if source_of(it) == source:
			return it
	return null


## Whether a burning item of this kind is within `reach` of `at`.
func burning_near(run: RunState, at: Vector2, reach: float) -> bool:
	for place: Dictionary in ItemPlaces.of_kind(run, item_kind()):
		var p: Vector2 = place["position"]
		var it: Item = place["item"]
		if burning(it) and p.distance_to(at) <= reach:
			return true
	return false


func write_state(writer: SimStateWriter) -> void:
	var places: Array[Dictionary] = ItemPlaces.of_kind(_run, item_kind()) if _run != null else ([] as Array[Dictionary])
	writer.put_i64(places.size())
	for place: Dictionary in places:
		var it: Item = place["item"]
		writer.put_i64(it.uid)
		writer.put_bool(burning(it))
		writer.put_i64(int(Variants.number(it.state.get("burn_ticks", -1))))

extends "res://tests/scenario/kit/scenario_test.gd"
## GEN-09's contents spawned (GEN-10) from the shipped set's point-of-interest templates (GEN-16).
## With their cells loaded, a seed's planned substation and a lamp cabin hold each contents line's
## items in that line's slot, each a placed item keyed by its placement and lying on its tile. The
## substation's spare fuse lies there, its phone stands on its fixture, and LFT-05's fuse board, trip
## lever and main switch come from its template. The lamp cabin holds its gauze lamps (unlit), its oil
## flasks and its paraffin can, and its phone.

const Specs = preload("res://tests/unit/gen/template_specs.gd")
const SEED: int = 16201
## The things a contents line lays as something other than an item (GEN-10's contents pass).
const NOT_ITEMS: Array[String] = ["remains", "phone", "coats", "lore", "brass_checks"]


func before_all() -> void:
	assert_true(Tuning.load_server())


## pid -> the entity of every placed item lying in the world.
static func _placed_items(s: Scenario) -> Dictionary:
	var out: Dictionary = {}
	for raw: Variant in s.run.inventory.world.items.keys():
		var it: Item = s.run.inventory.world.items[raw]
		if not it.placement.is_empty():
			out[it.placement] = Variants.whole(raw)
	return out


## Loads a point of interest's cells; checks each contents line's item lies spawned in its line's
## slot and its phone on its fixture. Returns {thing: count} of the items found.
func _check(s: Scenario, poi: Dictionary) -> Dictionary:
	var layouts: LbLayouts = s.generation.layouts
	var cells: Array[Vector2i] = []
	cells.assign(Variants.array(poi["cells"]))
	s.generation.start(cells)
	var placed: Array[Dictionary] = []
	for cell: Vector2i in cells:
		assert_true(s.run.mine.native.is_loaded(cell), "%s: cell %s loaded" % [poi["kind"], cell])
		for raw: Variant in Variants.array(s.run.placed.by_cell.get(cell, [])):
			var p: Dictionary = raw
			if str(p["source"]) == "poi":
				placed.append(p)
	var items: Dictionary = _placed_items(s)
	var slots: Array = Variants.array(poi["slots"])
	var used: Dictionary = {}
	var found: Dictionary = {}
	var region: Vector2i = poi["region"]
	for raw: Variant in layouts.poi_contents(region, Variants.whole(poi["index"])):
		var line: Dictionary = raw
		var at: int = Variants.whole(line["line"])
		var thing: String = str(line["thing"])
		if thing == "phone":
			var phone: bool = false
			for p: Dictionary in placed:
				if str(p["kind"]) == "phone":
					var entity: int = Variants.whole(s.run.placed.phones.get(str(p["id"]), 0))
					phone = entity != 0 and s.run.registry.get_entity(entity).tile() == p["tile"]
			assert_true(phone, "%s: its phone stands on its fixture" % poi["kind"])
			continue
		if at < 0 or NOT_ITEMS.has(thing):
			continue
		var slot: Rect2i = slots[at]
		var match_pid: String = ""
		for p: Dictionary in placed:
			var tile: Vector2i = p["tile"]
			if str(p["thing"]) == thing and slot.has_point(tile) and not used.has(str(p["id"])):
				match_pid = str(p["id"])
				break
		assert_false(match_pid.is_empty(), "%s: a %s placed in slot %d" % [poi["kind"], thing, at])
		if match_pid.is_empty():
			continue
		used[match_pid] = true
		var entity: int = Variants.whole(items.get(match_pid, 0))
		assert_ne(entity, 0, "%s: its %s spawned" % [poi["kind"], thing])
		if entity == 0:
			continue
		assert_true(slot.has_point(s.run.registry.get_entity(entity).tile()), "%s: its %s lies in slot %d" % [poi["kind"], thing, at])
		found[thing] = Variants.whole(found.get(thing, 0)) + 1
	return found


static func _lamp_cabin(layouts: LbLayouts) -> Dictionary:
	for y: int in range(-4, 5):
		for x: int in range(-4, 5):
			for raw: Variant in Variants.array(layouts.poi_region(Vector2i(x, y))["pois"]):
				var poi: Dictionary = raw
				if str(poi["kind"]) == "lamp_cabin" and not str(poi["template"]).is_empty():
					return poi
	return {}


func test_a_planned_substation_and_a_lamp_cabin_spawn_into_their_slots() -> void:
	var s: Scenario = make({"seed": SEED, "generated": {"pack": Specs.shipped_pack(), "plan": true}})
	var layouts: LbLayouts = s.generation.layouts
	var substation: Dictionary = {}
	for raw: Variant in Variants.array(layouts.plan_dict()["sites"]):
		var site: Dictionary = Variants.dict(raw)
		if str(site["kind"]) == "substation":
			var door: Vector2i = site["door"]
			substation = layouts.poi_at(door)
	assert_false(substation.is_empty(), "a substation planned")
	assert_false(str(substation.get("template", "")).is_empty(), "with its template")
	var at_substation: Dictionary = _check(s, substation)
	assert_eq(Variants.whole(at_substation.get("fuse", 0)), 1, "the spare fuse")
	s.step(1)
	assert_eq(s.run.power.anchors_from, "template", "LFT-05's fixtures read from the template")
	var slots: Array = Variants.array(substation["slots"])
	var fixtures: Array[String] = ["fuse_board", "trip_lever", "main_switch"]
	for i: int in fixtures.size():
		var centre: Vector2 = s.run.power.anchors[fixtures[i]]
		var slot: Rect2i = slots[i + 1]
		assert_eq(Vector2i(centre.floor()), slot.position, "its %s on its slot" % fixtures[i])
	var cabin: Dictionary = _lamp_cabin(layouts)
	assert_false(cabin.is_empty(), "a lamp cabin near base camp")
	var at_cabin: Dictionary = _check(s, cabin)
	assert_gt(Variants.whole(at_cabin.get("gauze_lamp", 0)), 0, "its gauze lamps")
	assert_gt(Variants.whole(at_cabin.get("oil_flask", 0)), 0, "its oil flasks")
	assert_eq(Variants.whole(at_cabin.get("paraffin_can", 0)), 1, "its paraffin can")
	for raw: Variant in s.run.inventory.world.items.keys():
		var it: Item = s.run.inventory.world.items[raw]
		if it.kind == ItemKinds.Kind.GAUZE_LAMP and not it.placement.is_empty():
			assert_false(Variants.flag(it.state.get("lit", false)), "a found lamp lies unlit")

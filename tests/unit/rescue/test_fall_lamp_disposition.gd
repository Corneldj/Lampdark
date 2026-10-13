extends "res://tests/scenario/kit/scenario_test.gd"
## RSC-01: for each cause, the lamp ends as §11.2's table says, with a gauze lamp open, a gauze
## lamp shuttered and an electric lamp; only the lamp drops: the belt, slotted lamps included,
## stays on the body unchanged.

const W = preload("res://tests/unit/mnr/belt_world.gd")
const L = preload("res://tests/unit/mnr/lamp_world.gd")

const MOTH: int = 999


func before_all() -> void:
	assert_true(Tuning.load_server())


## [lamp variant, cause] -> [where (&"moth", &"beside", &"grab_point"), gauze state after or -1, electric still on]
func _expected(variant: String, cause: int) -> Array:
	var open_after: int = GauzeLamp.State.SET_DOWN_OPEN if variant == "open" else GauzeLamp.State.SET_DOWN_SHUTTERED
	match cause:
		FallCause.Cause.MOTH_SMOTHER:
			return [&"beside", -1, true] if variant == "electric" else [&"moth", GauzeLamp.State.CARRIED_OFF, false]
		FallCause.Cause.DRAG:
			return [&"grab_point", GauzeLamp.State.OUT, true]
		FallCause.Cause.HATCH:
			return [&"beside", GauzeLamp.State.OUT, true]
	return [&"beside", open_after, true]


func test_table() -> void:
	var causes: Array[int] = [FallCause.Cause.MOTH_SMOTHER, FallCause.Cause.DRAG, FallCause.Cause.PIN, FallCause.Cause.BLAST,
		FallCause.Cause.BLACKDAMP, FallCause.Cause.ROOF_FALL, FallCause.Cause.HATCH, FallCause.Cause.FRIENDLY_HIT]
	var run_seed: int = 100
	for variant: String in ["open", "shuttered", "electric"]:
		for cause: int in causes:
			run_seed += 1
			var s: Scenario = make({"seed": run_seed, "fixture": W.room()})
			var a: Vector2i = s.fixture.spot("a")
			var ann: MinerHandle = s.add_miner("ann", a)
			s.step(1)
			var inv: InventorySystem = s.run.inventory
			var lamp: Item = null
			var gauze: GauzeLamp = null
			if variant == "electric":
				lamp = inv.world.make(ItemKinds.Kind.ELECTRIC_LAMP, 1, {"on": true})
				assert_true(inv.give(s.run, ann.entity_id, lamp))
			else:
				gauze = L.lit_in_hand(s, ann)
				lamp = gauze.item
				if variant == "shuttered":
					s.run.lamps.douse(s.run, gauze, 0)
			# The belt: a spanner, three candles, and a spare lamp shuttered in a slot.
			assert_true(inv.give(s.run, ann.entity_id, inv.world.make(ItemKinds.Kind.SPANNER)))
			assert_true(inv.give(s.run, ann.entity_id, inv.world.make(ItemKinds.Kind.CANDLE, 3)))
			var spare: Item = inv.world.make(ItemKinds.Kind.GAUZE_LAMP, 1, {"lit": true, "shutter": true})
			W.belt(s, ann.entity_id).slots[2] = spare
			s.step(1)
			var before: Array = _belt(W.belt(s, ann.entity_id))
			var grab_point: Vector2i = a + Vector2i(3, 1)
			var ctx: Dictionary = {"moth_takes_lamp": MOTH} if cause == FallCause.Cause.MOTH_SMOTHER else {}
			if cause == FallCause.Cause.DRAG:
				ctx = {"grab_point": grab_point}
			assert_true(s.run.falls.fall_unconscious(s.run, ann.entity_id, cause, ctx))
			s.step(2)
			var label: String = "%s lamp, %s" % [variant, FallCause.name_of(cause)]
			assert_eq(s.run.miner_state.life(ann.entity_id), MinerTransitions.Life.UNCONSCIOUS, label)
			var want: Array = _expected(variant, cause)
			var b: HandsAndBelt = W.belt(s, ann.entity_id)
			assert_null(b.lamp_hand, label + ": only the lamp drops")
			assert_eq(_belt(b), before, label + ": the belt stays on the body, unchanged")
			var where: StringName = want[0]
			if where == &"moth":
				assert_eq(gauze.state(), GauzeLamp.State.CARRIED_OFF, label + ": gone with the Moth, snuffed")
				assert_eq(gauze.holder, MOTH)
				continue
			var tile: Vector2i = grab_point if where == &"grab_point" else a
			var found: Vector2i = Vector2i(-99, -99)
			for raw: Variant in inv.world.items.keys():
				if inv.world.items[raw] == lamp:
					found = s.run.registry.get_entity(int(Variants.number(raw))).tile()
			assert_eq(found, tile, label + ": the lamp lies %s" % where)
			if gauze != null:
				assert_eq(gauze.state(), int(Variants.number(want[1])), label + ": %s" % L.state_name(int(Variants.number(want[1]))))
			else:
				assert_eq(Variants.flag(lamp.state.get("on", false)), Variants.flag(want[2]), label + ": an electric lamp stays lit")


func _belt(b: HandsAndBelt) -> Array:
	var out: Array = []
	for it: Item in b.slots:
		out.append([it.uid, it.kind, it.count] if it != null else null)
	return out

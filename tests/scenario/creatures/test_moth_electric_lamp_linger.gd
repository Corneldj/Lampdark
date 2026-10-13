extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-04: an electric-lamp carrier falls and the lamp drops beside them, still lit; the Moth
## lingers 8 s over it, then ignores that light for 60 s. MNR-08's lamp is stood in here by a
## carried, cannot-take VIS-02 source of kind electric_lamp.

const A = preload("res://tests/scenario/creatures/moth_awake_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_electric() -> void:
	var s: Scenario = make({"seed": 81, "fixture": A.hall(40, 20)})
	var m: Moth = A.awake(s, Vector2i(5, 10), false)
	var ann: MinerHandle = s.add_miner("ann", Vector2i(22, 10))
	s.step(1)
	var inv: InventorySystem = s.run.inventory
	var item: Item = inv.world.make(ItemKinds.Kind.ELECTRIC_LAMP, 1, {"on": true})
	assert_true(inv.give(s.run, ann.entity_id, item))
	var light: int = s.run.light.grid.add_point("electric_lamp", LbLightGrid.COLOUR_WHITE, ann.entity_id,
		LbLightGrid.FLAG_CARRIED | LbLightGrid.FLAG_CANNOT_TAKE | LbLightGrid.FLAG_NO_FLAME_STATES, 6.0, 1.0, Vector2(22.5, 10.5), 0)
	assert_gte(A.until_state(s, m, &"linger", 600), 0)
	assert_eq(A.life(s, ann.entity_id), MinerTransitions.Life.UNCONSCIOUS, "the carrier falls")
	assert_null(inv.hands_of(ann.entity_id).lamp_hand)
	assert_true(Variants.flag(item.state["on"]), "the electric lamp burns on")
	assert_true(s.run.light.grid.has_source(light))
	var lingered: int = A.until_state(s, m, &"search", 400)
	assert_between(lingered, 158, 161, "8 s")
	var ignored_from: int = s.run.tick
	var hunted_again: Array[int] = []
	s.run.creatures.log.logged.connect(func(e: Dictionary) -> void:
		if e["type"] == &"moth_target" and int(Variants.number(e["source"])) == light:
			hunted_again.append(s.run.tick))
	s.step(1250)
	assert_eq(hunted_again.size(), 1, "it hunts that light again only once the 60 s are up")
	assert_gte(hunted_again[0] - ignored_from, 1199, "never inside the 60 s")

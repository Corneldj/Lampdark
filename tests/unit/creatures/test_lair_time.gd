extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-15: the lair's layout and its row. Until GEN-10 places it, the lair is the floor within
## stythe.lair_radius_tiles by path of the Stythe's lair tile, the row in row-major order; a given
## layout replaces it. A slot whose body is gone is free again. Lair time is per miner, in seconds.

const H = preload("res://tests/scenario/creatures/stythe_hunt_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_the_stand_in_layout_and_the_row() -> void:
	var s: Scenario = make({"seed": 1541, "fixture": H.road(), "overrides": H.W.ON})
	var st: StytheCreature = H.W.stythe(s, Vector2i(60, 2), Vector2i(95, 2))
	var lair: StytheLair = st.home
	var r: int = Tuning.i(&"stythe.lair_radius_tiles")
	assert_eq(lair.tiles().size(), 2 * r + 1, "the road within %d tiles either side" % r)
	assert_true(lair.is_lair(Vector2i(95 - r, 2)) and lair.is_lair(Vector2i(95 + r, 2)))
	assert_false(lair.is_lair(Vector2i(95 - r - 1, 2)), "no farther")
	assert_false(lair.is_lair(Vector2i(95, 1)), "rock is not lair")
	assert_eq(lair.row()[0], Vector2i(95 - r, 2), "the row runs row-major")
	assert_eq(lair.next_slot(), 0)
	st.lair = Vector2i(30, 2)
	assert_true(lair.is_lair(Vector2i(30, 2)), "moved with its lair tile")
	var given: Array[Vector2i] = [Vector2i(10, 2), Vector2i(11, 2), Vector2i(12, 2)]
	lair.set_layout(given, [Vector2i(12, 2), Vector2i(10, 2)] as Array[Vector2i])
	assert_eq(lair.tiles(), given, "a placed layout replaces it")
	assert_eq(lair.row(), [Vector2i(12, 2), Vector2i(10, 2)] as Array[Vector2i])
	lair.slots[0] = 777
	assert_eq(lair.next_slot(), 1, "a laid slot is taken")
	lair.slots[0] = 0
	assert_eq(lair.next_slot(), 0, "free again once its body is gone")
	assert_eq(lair.lair_seconds(12345), 0.0)

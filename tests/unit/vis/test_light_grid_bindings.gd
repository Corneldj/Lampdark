extends GutTest
## VIS-02 through GDScript: sources, signals, queries, falloff for client prediction.

var mine: Mine
var light: LightSystem
var added: Array[int] = []
var removed: Array[int] = []
var changed: Array[String] = []


func before_all() -> void:
	assert_true(Tuning.load_server())


func before_each() -> void:
	mine = Mine.new()
	assert_eq(mine.load_fixed_map("test"), 2)
	light = LightSystem.new(mine)
	added.clear()
	removed.clear()
	changed.clear()
	light.grid.source_added.connect(func(id: int, _kind: String, _pos: Vector2) -> void: added.append(id))
	light.grid.source_removed.connect(func(id: int) -> void: removed.append(id))
	light.grid.light_changed.connect(func(_id: int, _kind: String, cause: String) -> void: changed.append(cause))


func _lamp(pos: Vector2, radius: float, owner: int = 0) -> int:
	return light.grid.add_point("gauze_lamp", LbLightGrid.COLOUR_AMBER, owner, LbLightGrid.FLAG_FLAME | LbLightGrid.FLAG_CARRIED,
		radius, 1.0, pos, 0)


func test_a_lamp_lights_the_corridor_and_not_through_the_door() -> void:
	_lamp(Vector2(7.5, 1.5), 4.0)
	light.grid.update()
	assert_eq(light.grid.value(Vector2i(7, 1)), 1000, "the lamp's own tile")
	assert_eq(light.grid.value(Vector2i(8, 1)), 708, "1 tile off: 1 - 0.7 / 2.4")
	assert_gt(light.grid.value(Vector2i(10, 1)), 0, "the door's face is lit")
	assert_eq(light.grid.value(Vector2i(11, 1)), 0, "nothing passes the shut air door")
	assert_almost_eq(light.light_at(Vector2i(7, 1)), light.grid.value(Vector2i(7, 1)) / 1000.0, 0.0001)


func test_opening_the_door_lets_light_through_on_the_next_update() -> void:
	_lamp(Vector2(9.5, 1.5), 4.0)
	light.grid.update()
	assert_eq(light.grid.value(Vector2i(11, 1)), 0)
	mine.native.set_barrier(Vector2i(0, 0), 1, true)
	light.grid.update()
	assert_gt(light.grid.value(Vector2i(11, 1)), 0)


func test_signals_and_queries() -> void:
	var a: int = _lamp(Vector2(3.5, 5.5), 2.5, 11)
	var b: int = _lamp(Vector2(7.5, 5.5), 2.5, 12)
	light.grid.update()
	assert_eq(added, [a, b] as Array[int])
	assert_eq(light.grid.value(Vector2i(5, 5)), 420, "two wick-down lamps 2 tiles off")
	assert_eq(light.grid.value_from(Vector2i(5, 5), PackedInt64Array([11])), 210)
	assert_eq(light.grid.colour_class(Vector2i(3, 5)), LbLightGrid.COLOUR_AMBER)
	var brightest: Dictionary = light.grid.brightest_source(Vector2i(3, 5))
	assert_eq(int(Variants.number(brightest["id"])), a)
	light.grid.set_radius_modifier(a, 0.7, "guttering")
	light.grid.update_point(b, Vector2(7.5, 5.5), 0.0, 1.0)
	assert_eq(changed, ["guttering", "radius"] as Array[String])
	var flames: PackedInt64Array = light.grid.flame_sources(Rect2(0, 0, 20, 20))
	assert_eq(flames, PackedInt64Array([a, b]), "a shuttered lamp is still a flame")
	light.grid.remove_source(a)
	assert_eq(removed, [a] as Array[int])
	light.grid.update()
	var bright: Array = light.grid.tiles_at_or_above(300, Rect2i(0, 0, 20, 20))
	assert_eq(bright.size(), 0, "the shuttered lamp and the removed one give nothing")


func test_muzzle_flash_for_exactly_two_ticks() -> void:
	var run: RunState = RunState.create(1, ServerConfig.Mode.FRIENDS, false)
	light.register_into(run)
	var flash: int = light.grid.add_point("muzzle_flash", LbLightGrid.COLOUR_PALE_AMBER, 0, 0, 6.0, 1.0, Vector2(5.5, 5.5), 2)
	run.run_tick()
	assert_eq(light.grid.value(Vector2i(5, 5)), 1000, "tick 1")
	run.run_tick()
	assert_true(light.grid.has_source(flash), "tick 2")
	run.run_tick()
	assert_false(light.grid.has_source(flash), "gone at tick 3")
	assert_eq(light.grid.value(Vector2i(5, 5)), 0)


func test_client_falloff_matches_the_grid() -> void:
	_lamp(Vector2(4.5, 5.5), 4.0)
	light.grid.update()
	for x: int in range(4, 9):
		var d: float = absf(x + 0.5 - 4.5)
		var predicted: int = LbLightMath.falloff_milli(d, 4.0, 1.0, Tuning.f(&"light.core_fraction"),
			Tuning.f(&"light.core_value"), Tuning.f(&"light.edge_value"))
		assert_eq(light.grid.value(Vector2i(x, 5)), predicted, "tile %d" % x)


func test_light_keys_reach_the_client_table() -> void:
	var client: TuningSet = TuningSet.new()
	assert_eq(client.load_client_table(TuningSet.CLIENT_TABLE), [] as Array[String])
	for key: String in ["light.core_fraction", "light.core_value", "light.edge_value", "light.cap", "light.value_scale"]:
		assert_true(client.has_key(StringName(key)), key)

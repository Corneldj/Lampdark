extends GutTest
## MNR-09 (§4.8): Use held on a stone slot aims and its release throws: one THROW action with the
## cursor's distance from the own miner in tiles (mouse) or the right stick's deflection, centred 2,
## full 8 (pad); nothing while the free hand holds something or both hands are full, nor on another
## slot. The router draws nothing and sends no landing point.

const F = preload("res://tests/unit/mnr/input_frames.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _stones_router(family: String) -> InputRouter:
	var r: InputRouter = F.router(family)
	r.know_inventory({"lamp": [0, 0], "free": [0, 0], "slots": [[ItemKinds.Kind.STONE, 3], [0, 0], [0, 0], [0, 0]], "two_handed": false})
	return r


func _throws(actions: Array) -> Array:
	return actions.filter(func(a: Variant) -> bool: return int(Variants.number(Variants.array(a)[0])) == ActionRecord.Kind.THROW)


func test_mouse_distance_from_the_cursor() -> void:
	var tile_px: float = Tuning.f(&"camera.tile_px_at_1080p")
	var own: Vector2 = Vector2(960, 540)
	for tiles: float in [5.0, 1.0, 11.0]:
		var r: InputRouter = _stones_router("kbm")
		var extra: Dictionary = {"cursor": own + Vector2(tiles * tile_px, 0.0), "own_screen": own}
		var sent: Array = F.press(r, {"use": true}, 1.0, 0.4, extra)
		assert_eq(_throws(sent).size(), 1, "one throw on the release")
		var arg: int = int(Variants.number(Variants.array(_throws(sent)[0])[1]))
		assert_eq(arg, roundi(clampf(tiles, 2.0, 8.0) * 100.0), "%.0f tiles of cursor" % tiles)


func test_stick_deflection() -> void:
	for pair: Array in [[Vector2.ZERO, 200], [Vector2(1.0, 0.0), 800]]:
		var r: InputRouter = _stones_router("pad")
		var want: int = pair[1]
		var sent: Array = F.press(r, {"use": true}, 1.0, 0.4, {"face_stick": pair[0]})
		assert_eq(int(Variants.number(Variants.array(_throws(sent)[0])[1])), want)


func test_nothing_otherwise() -> void:
	var r: InputRouter = _stones_router("kbm")
	r.know_inventory({"lamp": [0, 0], "free": [ItemKinds.Kind.FLARE, 1], "slots": [[ItemKinds.Kind.STONE, 3], [0, 0], [0, 0], [0, 0]],
		"two_handed": false})
	assert_eq(_throws(F.press(r, {"use": true}, 1.0, 0.4)).size(), 0, "a flare in the free hand")
	r.know_inventory({"lamp": [0, 0], "free": [0, 0], "slots": [[ItemKinds.Kind.STONE, 3], [0, 0], [0, 0], [0, 0]], "two_handed": true})
	assert_eq(_throws(F.press(r, {"use": true}, 2.0, 0.4)).size(), 0, "both hands full")
	r.know_inventory({"lamp": [0, 0], "free": [0, 0], "slots": [[ItemKinds.Kind.CANDLE, 3], [0, 0], [0, 0], [0, 0]], "two_handed": false})
	assert_eq(_throws(F.press(r, {"use": true}, 3.0, 0.4)).size(), 0, "another slot's Use")

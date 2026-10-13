extends GutTest
## VIS-06: a token's frames depend on its speed alone: two tokens of a size class moving at the same
## speed in different directions show the same frames; a still large token (a heap, the sleeping
## Moth) never animates; the shape is the same in every direction (no facing).


func test_same_speed_same_frames() -> void:
	var r: TokenRenderer = TokenRenderer.new()
	var a: Vector2 = Vector2(5, 5)
	var b: Vector2 = Vector2(40, 12)
	var east: Vector2 = Vector2(0.27, 0.0)
	var north_west: Vector2 = Vector2(-0.19, -0.19).normalized() * 0.27
	for _i: int in 40:
		a += east
		b += north_west
		var frames: Dictionary = r.update({1: a, 2: b})
		assert_eq(int(Variants.number(frames[1])), int(Variants.number(frames[2])), "a miner token and a Stythe token at the same speed")


func test_still_never_animates() -> void:
	var r: TokenRenderer = TokenRenderer.new()
	for _i: int in 30:
		var frames: Dictionary = r.update({7: Vector2(3, 3), 8: Vector2(9, 9)})
		assert_eq([frames[7], frames[8]], [0, 0], "a heap and the sleeping Moth: still")


func test_shape_has_no_facing() -> void:
	for size: int in [SeenKind.Size.MINER, SeenKind.Size.LARGE, SeenKind.Size.LARGE_MOTIONLESS, SeenKind.Size.SMALL]:
		for frame: int in TokenRenderer.FRAMES:
			var poly: PackedVector2Array = TokenRenderer.shape(size, frame)
			var r0: float = poly[0].length()
			for p: Vector2 in poly:
				assert_almost_eq(p.length(), r0, 1e-4, "radially symmetric")
	assert_eq(TokenRenderer.shape(SeenKind.Size.LARGE, 2), TokenRenderer.shape(SeenKind.Size.LARGE_MOTIONLESS, 2),
		"a large mover and a large still thing share one shape")

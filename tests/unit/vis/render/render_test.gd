extends GutTest
## VIS-05: the base of the render tests: a WorldView in the tree, one synthetic frame, the root
## viewport captured with a real renderer (tools/build/run_render_tests.sh). Pending without one.

const K = preload("res://tests/unit/vis/render/render_kit.gd")

var wv: WorldView = null


func before_all() -> void:
	assert_true(Tuning.load_server())


func before_each() -> void:
	wv = WorldView.new()
	add_child_autofree(wv)


## True (and the test pending) when there is no renderer: the plain headless suite.
func skip_without_renderer() -> bool:
	if K.has_renderer():
		return false
	pending("needs a renderer: tools/build/run_render_tests.sh")
	return true


## Renders one frame of `view` and returns the screen.
func render(view: ReceivedView, drawn: DrawnSet, facing: int = 0, own_light: float = 0.0) -> Image:
	wv.show_frame(drawn, view, K.ORIGIN, K.MINER, facing, own_light)
	return await capture()


func capture() -> Image:
	var gut_layers: Array[CanvasLayer] = []
	for n: Node in get_tree().root.find_children("GutLayer", "CanvasLayer", true, false):
		var l: CanvasLayer = n
		if l.visible:
			l.visible = false
			gut_layers.append(l)
	for _i: int in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	for l: CanvasLayer in gut_layers:
		l.visible = true
	return img


## Every sampled pixel (every `stride` px) for which `want(pixel, colour)` is false.
func violations(img: Image, stride: int, want: Callable) -> Array[String]:
	var out: Array[String] = []
	for y: int in range(0, img.get_height(), stride):
		for x: int in range(0, img.get_width(), stride):
			var c: Color = img.get_pixel(x, y)
			if not Variants.flag(want.call(Vector2i(x, y), c)):
				out.append("(%d, %d) = %s" % [x, y, c])
				if out.size() >= 5:
					return out
	return out


## The world point (tiles) at a pixel's centre.
static func world_at(p: Vector2i) -> Vector2:
	return K.ORIGIN + (Vector2(p) + Vector2(0.5, 0.5)) / Tuning.f(&"camera.tile_px_at_1080p")

extends GutTest
## STM-01's first Proton launch showed a black screen: the mine view drew over the Pithead before any
## server frame. A started client (dev mode, no server) shows the Pithead's Play button on screen.
## Needs a real renderer (tools/build/run_render_tests.sh); pending in the plain headless suite.

const K = preload("res://tests/unit/vis/render/render_kit.gd")


func test_the_pithead_is_drawn_before_any_frame() -> void:
	if not K.has_renderer():
		pending("needs a renderer: tools/build/run_render_tests.sh")
		return
	var script: GDScript = load("res://client/client_main.gd")
	var cm: Node = script.new()
	add_child_autofree(cm)
	var cfg: ClientConfig = ClientConfig.new()
	cfg.no_steam = true
	cm.call("start", cfg)
	var play: Button = cm.find_child("Play", true, false)
	assert_not_null(play)
	for n: Node in get_tree().root.find_children("GutLayer", "CanvasLayer", true, false):
		(n as CanvasLayer).visible = false
	for _i: int in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var box: Rect2i = Rect2i(play.get_global_rect())
	var lit: int = 0
	for y: int in range(box.position.y, box.end.y, 2):
		for x: int in range(box.position.x, box.end.x, 2):
			if not K.is_black(img.get_pixel(x, y)):
				lit += 1
	gut.p("Play button at %s: %d lit samples of %d" % [box, lit, box.get_area() / 4])
	assert_gt(lit, box.get_area() / 8, "the Play button is drawn, not covered in black")
	for n: Node in get_tree().root.find_children("GutLayer", "CanvasLayer", true, false):
		(n as CanvasLayer).visible = true


func test_the_steam_failure_screen_is_drawn_with_its_quit_button() -> void:
	if not K.has_renderer():
		pending("needs a renderer: tools/build/run_render_tests.sh")
		return
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 20
	add_child_autofree(layer)
	var screen: SteamFailureScreen = SteamFailureScreen.new(SteamApi.Init.NO_STEAM_CLIENT)
	layer.add_child(screen)
	for n: Node in get_tree().root.find_children("GutLayer", "CanvasLayer", true, false):
		(n as CanvasLayer).visible = false
	for _i: int in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	for n: Node in get_tree().root.find_children("GutLayer", "CanvasLayer", true, false):
		(n as CanvasLayer).visible = true
	var box: Rect2i = Rect2i(screen.quit_button.get_global_rect())
	assert_true(Rect2i(Vector2i.ZERO, img.get_size()).encloses(box), "the Quit button is on screen: %s" % box)
	var bright: int = 0
	for y: int in range(box.position.y, box.end.y, 2):
		for x: int in range(box.position.x, box.end.x, 2):
			if img.get_pixel(x, y).get_luminance() > 0.12:
				bright += 1
	gut.p("Quit button at %s: %d bright samples" % [box, bright])
	assert_gt(bright, 10, "its label and frame are drawn")

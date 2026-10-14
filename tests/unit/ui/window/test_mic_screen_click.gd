extends GutTest
## SND-10: a mouse click on the permission screen chooses directly. Pointer input needs a real
## window, so this runs with the render tests (tools/build/run_render_tests.sh) and is pending in
## the plain headless suite.

const K = preload("res://tests/unit/vis/render/render_kit.gd")

var _dir: String = ""


func before_each() -> void:
	_dir = "user://test_mic_click_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(_dir)


func after_each() -> void:
	for f: String in DirAccess.get_files_at(_dir):
		DirAccess.remove_absolute(_dir.path_join(f))
	DirAccess.remove_absolute(_dir)


func _click(at: Vector2) -> void:
	var move: InputEventMouseMotion = InputEventMouseMotion.new()
	move.position = at
	move.global_position = at
	get_viewport().push_input(move)
	await wait_physics_frames(1)
	for pressed: bool in [true, false]:
		var e: InputEventMouseButton = InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		e.pressed = pressed
		e.position = at
		e.global_position = at
		get_viewport().push_input(e)
		await wait_physics_frames(1)


func test_a_click_on_either_button_chooses_it() -> void:
	if not K.has_renderer():
		pending("needs a window: tools/build/run_render_tests.sh")
		return
	for want: int in [MicMode.Mode.USE, MicMode.Mode.MUTE]:
		var v: String = _dir.path_join("version.json")
		var f: FileAccess = FileAccess.open(v, FileAccess.WRITE)
		f.store_string(JSON.stringify({"version": 1}))
		f.close()
		var m: MicMode = MicMode.new(_dir.path_join("log_%d.jsonl" % want), _dir.path_join("queue_%d.jsonl" % want), v)
		var layer: CanvasLayer = CanvasLayer.new()
		layer.layer = 100
		add_child_autofree(layer)
		var s: MicPermissionScreen = MicPermissionScreen.new(m)
		layer.add_child(s)
		await wait_physics_frames(3)
		var button: Button = s.use_button if want == MicMode.Mode.USE else s.mute_button
		await _click(button.get_global_rect().get_center())
		assert_eq(m.mode, want, "a click on %s chooses it" % button.text)
		assert_eq(m.entries().size(), 1, "and logs it")
		layer.queue_free()
		await wait_physics_frames(1)

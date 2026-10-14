extends GutTest
## STM-01's first Proton launch found the mine view drawing black over the pithead before any server
## frame: the view, overlay included, stays hidden until ClientMain shows its first frame.


func before_all() -> void:
	assert_true(Tuning.load_client())


func test_set_shown_hides_the_view_and_its_overlay() -> void:
	var wv: WorldView = WorldView.new()
	add_child_autofree(wv)
	wv.set_shown(false)
	assert_false(wv.visible)
	assert_false(wv.overlay_layer().visible, "the overlay (own miner, edge glow, breath-cloud) too")
	wv.set_shown(true)
	assert_true(wv.visible and wv.overlay_layer().visible)


func test_the_client_hides_it_until_the_first_frame() -> void:
	var src: String = FileAccess.get_file_as_string("res://client/client_main.gd")
	var made: int = src.find("world_view = WorldView.new()")
	var hidden: int = src.find("world_view.set_shown(false)")
	assert_gt(hidden, made, "hidden as soon as it is made")
	var shown: int = src.find("world_view.set_shown(true)")
	assert_gt(shown, 0)
	assert_lt(shown, src.find("world_view.show_frame("), "shown with the first frame")

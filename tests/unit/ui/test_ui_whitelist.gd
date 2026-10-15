extends GutTest
## UI-01: the in-play layers hold only registered screen elements (ScreenElementRegistry); an
## unregistered visible node fails the check, a hidden one or a registered one does not.

const W = preload("res://tests/unit/ui/inplay_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_client())


func _layer() -> InPlayLayer:
	var l: InPlayLayer = InPlayLayer.new()
	add_child_autofree(l)
	return l


func test_every_element_shown_is_registered() -> void:
	var l: InPlayLayer = _layer()
	for child: Node in l.get_children():
		var item: CanvasItem = child as CanvasItem
		item.visible = true
		assert_true(ScreenElementRegistry.TYPES.has(ScreenElementRegistry.type_of(child)), "%s is registered" % child.get_class())
	assert_eq(l.check_frame(), [] as Array[String])


func test_an_unregistered_visible_node_fails() -> void:
	var l: InPlayLayer = _layer()
	var stray: Label = Label.new()
	stray.text = "Ann"
	l.add_child(stray)
	assert_eq(l.check_frame().size(), 1, "a stray label is caught")
	stray.visible = false
	assert_eq(l.check_frame(), [] as Array[String], "hidden: nothing drawn")
	stray.visible = true
	var holder: Node = Node.new()
	l.add_child(holder)
	var deep: Node2D = Node2D.new()
	holder.add_child(deep)
	assert_eq(l.check_frame().size(), 2, "found under a plain node too")
	ScreenElementRegistry.mark(stray, &"caption")
	ScreenElementRegistry.mark(deep, &"arc")
	assert_eq(l.check_frame(), [] as Array[String], "registered: allowed")


func test_world_views_overlay_is_registered() -> void:
	var wv: WorldView = WorldView.new()
	add_child_autofree(wv)
	var l: InPlayLayer = _layer()
	assert_eq(l.check_frame([wv.overlay_layer()]), [] as Array[String], "the edge glow, own miner and breath-cloud")
	var stray: Sprite2D = Sprite2D.new()
	wv.overlay_layer().add_child(stray)
	assert_eq(l.check_frame([wv.overlay_layer()]).size(), 1, "a marker added to the overlay is caught")
	stray.queue_free()


func test_a_frame_with_every_element_up_is_clean() -> void:
	var l: InPlayLayer = _layer()
	var r: InputRouter = InputRouter.new()
	r.know_ring({"open": true, "options": ["hand_over", "douse", "take:1"]})
	var v: ReceivedView = W.view(Vector2(5, 5))
	W.identity(v, 1, SeenKind.Kind.ITEM, Vector2(5.5, 5.0))
	var feel: FeelClient = FeelClient.new()
	feel.last_feel = {"caption_key": "feel.item.spanner", "bearing_q": 4, "verb_key": "verb.pick_up"}
	feel.feels = 1
	l.streamer_mode = true
	r.aside_held = true
	r.record.holds = InputRecord.HOLD_CHECK_LAMP
	l.update(W.frame(v, r, {"feel": feel, "inventory": {"lamp": [ItemKinds.Kind.GAUZE_LAMP, 0], "check": {"oil48": 30, "notches": 1}}}))
	assert_true(l.feel.visible and l.feel.arc.visible and l.check_lamp.visible and l.aside.visible and l.ring.visible)
	assert_eq(l.check_frame(), [] as Array[String])


func test_client_checks_every_frame_outside_release() -> void:
	var src: String = FileAccess.get_file_as_string("res://client/client_main.gd")
	assert_true(src.contains("in_play.check_frame([world_view.overlay_layer(), captions])"), "UI-03: the caption layer is checked too")
	assert_true(src.contains("if config.build.is_release():\n\t\treturn\n\tfor v: String in in_play.check_frame("),
		"release builds skip the walk; debug and test builds report each new violation")

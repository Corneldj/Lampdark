extends GutTest
## MNR-15: every row of §4.8's two tables has a default on keyboard and mouse and on gamepad (bar
## push-to-talk, unbound on pads by design); keys are physical positions; the shared pad buttons
## carry their tap and hold; every action the router reads exists.

const F = preload("res://tests/unit/mnr/input_frames.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_every_row_has_a_default_on_both_families() -> void:
	var store: BindingsStore = BindingsStore.new()
	for raw: Variant in BindingsStore.ROWS.keys():
		var row: String = str(raw)
		for family: String in BindingsStore.FAMILIES:
			var bound: bool = false
			for action: Variant in Variants.array(BindingsStore.ROWS[raw]):
				bound = bound or store.is_bound(str(action), family)
			var by_design: bool = Variants.array(BindingsStore.UNBOUND_BY_DESIGN.get(row, [])).has(family)
			assert_eq(bound, not by_design, "%s on %s" % [row, family])


func test_every_action_is_in_a_row_and_bound_somewhere() -> void:
	var in_rows: Dictionary = {}
	for raw: Variant in BindingsStore.ROWS.values():
		for action: Variant in Variants.array(raw):
			in_rows[str(action)] = true
	var store: BindingsStore = BindingsStore.new()
	for raw: Variant in BindingsStore.defaults().keys():
		assert_true(in_rows.has(str(raw)), "%s belongs to a row" % raw)
	for raw: Variant in InputRouter.HELD.keys():
		assert_true(store.bindings.has(raw), "held %s" % raw)
	for pair: Array in InputRouter.WHEELS:
		assert_true(store.bindings.has(pair[0]), "wheel %s" % pair[0])
	for action: String in InputContexts.CLOSE_UP_ACTIONS:
		assert_true(store.is_bound(action, "kbm") and store.is_bound(action, "pad"), "close-up %s" % action)


func test_keys_are_physical_positions() -> void:
	var store: BindingsStore = BindingsStore.new()
	var azerty_z: InputEventKey = InputEventKey.new()
	azerty_z.physical_keycode = KEY_W
	azerty_z.keycode = KEY_Z
	azerty_z.pressed = true
	assert_eq(store.action_for(azerty_z, "kbm"), ["move_up"] as Array[String], "the key in W's place moves up on any layout")


func test_shared_pad_buttons() -> void:
	var store: BindingsStore = BindingsStore.new()
	var lb: Dictionary = F.pad_button(store, JOY_BUTTON_LEFT_SHOULDER)
	assert_eq(lb.keys().size(), 2)
	assert_true(lb.has("callout") and lb.has("tap_rock"), "LB: the callout wheel held, the rock tapped")
	var view: Dictionary = F.pad_button(store, JOY_BUTTON_BACK)
	assert_true(view.has("check_lamp") and view.has("pocket_book"), "View: Check Lamp held, the Pocket Book tapped")
	var y: Dictionary = F.pad_button(store, JOY_BUTTON_Y)
	assert_true(y.has("signal_wheel") and y.has("chalk_wheel"), "Y: lamp signals with chalk on it too")
	assert_false(store.is_bound("push_to_talk", "pad"), "push-to-talk unbound on pads")
	assert_eq(store.specs("aside", "pad").size(), 2, "the Aside on L4 and R4")
	assert_eq(int(Variants.number(Variants.dict(store.specs("relight", "kbm")[0])["code"])), KEY_R)
	assert_eq(int(Variants.number(Variants.dict(store.specs("fire", "kbm")[0])["button"])), MOUSE_BUTTON_LEFT)

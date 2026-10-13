extends GutTest
## MNR-15 (§4.8 rule 9, GDD §14.5): every action can be rebound on both families, the router follows
## the new binding, and bindings and hold-or-toggle choices survive a restart (user://input.cfg).

const CFG: String = "user://test_remap_persistence.cfg"


func before_all() -> void:
	assert_true(Tuning.load_server())


func after_all() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG))


func _key(code: Key) -> InputEventKey:
	var e: InputEventKey = InputEventKey.new()
	e.physical_keycode = code
	e.pressed = true
	return e


func test_rebind_follows_at_once() -> void:
	var store: BindingsStore = BindingsStore.new()
	store.rebind("interact", "kbm", [BindingsStore.key(KEY_K)])
	assert_true(store.action_for(_key(KEY_K), "kbm").has("interact"))
	assert_false(store.action_for(_key(KEY_E), "kbm").has("interact"), "E no longer interacts")
	assert_true(store.action_for(_key(KEY_E), "kbm").has("close_up_open"), "other actions keep theirs")
	var pad: InputEventJoypadButton = InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_X
	pad.pressed = true
	store.rebind("shutter", "pad", [BindingsStore.joy(JOY_BUTTON_X)])
	assert_true(store.action_for(pad, "pad").has("shutter"))


func test_every_action_rebinds_and_survives_a_restart() -> void:
	var store: BindingsStore = BindingsStore.new()
	var keys: Array = BindingsStore.defaults().keys()
	keys.sort()
	var code: int = KEY_F1
	var button: int = JOY_BUTTON_MISC1
	for raw: Variant in keys:
		store.rebind(str(raw), "kbm", [BindingsStore.key(code)])
		store.rebind(str(raw), "pad", [BindingsStore.joy(button)])
		code += 1
	store.set_toggle("crouch", true)
	store.set_toggle("check_lamp", true)
	assert_eq(store.save(CFG), OK)
	var again: BindingsStore = BindingsStore.new()
	assert_eq(again.load_from(CFG), OK)
	code = KEY_F1
	for raw: Variant in keys:
		assert_true(again.action_for(_key(code as Key), "kbm").has(str(raw)), "%s survives" % raw)
		assert_eq(again.specs(str(raw), "pad"), [BindingsStore.joy(button)], "%s on the pad survives" % raw)
		code += 1
	assert_true(again.is_toggle("crouch"))
	assert_true(again.is_toggle("check_lamp"))
	assert_false(again.is_toggle("run"))


func test_missing_file_keeps_the_defaults() -> void:
	var store: BindingsStore = BindingsStore.new()
	assert_ne(store.load_from("user://no_such_input.cfg"), OK)
	assert_eq(store.bindings, BindingsStore.defaults())

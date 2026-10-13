extends GutTest
## MNR-15 (§6.7, GDD §14.5): with the callout timing option on, the confirm press's hold length and
## the gap since the previous press reach SND-11 accurately to one frame (hold to whisper, tap to
## talk, double-tap to shout; SND-11 sets the band); the direction still picks the slice, releasing
## centred still cancels, and the option and its ranges survive a restart.

const F = preload("res://tests/unit/mnr/input_frames.gd")
const CFG: String = "user://test_callout_timing_input.cfg"


func before_all() -> void:
	assert_true(Tuning.load_server())


func after_all() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG))


func _timing_router(family: String = "kbm") -> InputRouter:
	var store: BindingsStore = BindingsStore.new()
	store.callout_timing = true
	return F.router(family, store)


func _decoded(sent: Array) -> Dictionary:
	assert_eq(F.kinds(sent), [ActionRecord.Kind.CALLOUT] as Array[int])
	return Intents.decode_wheel_arg(int(Variants.number(Variants.array(sent[-1])[1])))


func test_hold_length_to_one_frame() -> void:
	for hold: float in [0.08, 0.3, 0.5, 0.73, 1.0]:
		var r: InputRouter = _timing_router()
		var got: Dictionary = _decoded(F.press(r, {"callout": true}, 5.0, hold, {"wheel_vec": Vector2(0.7, 0)}))
		assert_almost_eq(Variants.number(got["hold_ms"]), hold * 1000.0, F.FRAME_S * 1000.0, "held %.2f s" % hold)
		assert_eq(int(Variants.number(got["gap_ms"])), -1, "a first press: no gap")


func test_double_tap_gap_to_one_frame() -> void:
	var r: InputRouter = _timing_router()
	var window: float = r.store.shout_window_s
	var first: Dictionary = _decoded(F.press(r, {"callout": true}, 1.0, 0.08, {"wheel_vec": Vector2(0, 0.6)}))
	assert_eq(int(Variants.number(first["gap_ms"])), -1)
	# The second press starts 0.17 s after the first ended.
	var second: Dictionary = _decoded(F.press(r, {"callout": true}, 1.25, 0.07, {"wheel_vec": Vector2(0, 0.6)}))
	assert_almost_eq(Variants.number(second["gap_ms"]), 170.0, F.FRAME_S * 1000.0, "the double-tap gap")
	# Past the player's shout window: no gap rides.
	var third: Dictionary = _decoded(F.press(r, {"callout": true}, 1.32 + window + 0.05, 0.07, {"wheel_vec": Vector2(0, 0.6)}))
	assert_eq(int(Variants.number(third["gap_ms"])), -1)


func test_direction_still_picks_and_centred_cancels() -> void:
	var r: InputRouter = _timing_router()
	var sent: Array = F.press(r, {"callout": true}, 1.0, 0.5, {"wheel_vec": Vector2(0, -0.5)})
	assert_eq(int(Variants.number(Variants.array(sent[0])[2])), Intents.facing_u16(270.0))
	assert_eq(F.press(r, {"callout": true}, 3.0, 0.5, {"wheel_vec": Vector2.ZERO}), [], "centred: nothing")


func test_pad_timing_keeps_the_rock_tap() -> void:
	var r: InputRouter = _timing_router("pad")
	var lb: Dictionary = F.pad_button(r.store, JOY_BUTTON_LEFT_SHOULDER)
	var talk: Dictionary = _decoded(F.press(r, lb, 1.0, 0.1, {"wheel_vec": Vector2(0.8, 0)}))
	assert_almost_eq(Variants.number(talk["hold_ms"]), 100.0, F.FRAME_S * 1000.0, "a quick aimed press: the talk tap, timed")
	assert_eq(F.kinds(F.press(r, lb, 3.0, 0.1)), [ActionRecord.Kind.TAP_ROCK] as Array[int], "a quick centred press: the rock")
	assert_eq(F.press(r, lb, 5.0, 0.5), [], "a long centred press: cancelled")


func test_option_survives_a_restart() -> void:
	var store: BindingsStore = BindingsStore.new()
	assert_false(store.callout_timing, "the band ring by default")
	assert_almost_eq(store.whisper_hold_s, Tuning.f(&"voice.callout_whisper_hold_s"), 1e-6)
	assert_almost_eq(store.shout_window_s, Tuning.f(&"voice.callout_shout_window_s"), 1e-6)
	store.callout_timing = true
	store.whisper_hold_s = 0.7
	store.shout_window_s = 0.45
	assert_eq(store.save(CFG), OK)
	var again: BindingsStore = BindingsStore.new()
	assert_eq(again.load_from(CFG), OK)
	assert_true(again.callout_timing)
	assert_almost_eq(again.whisper_hold_s, 0.7, 1e-6)
	assert_almost_eq(again.shout_window_s, 0.45, 1e-6)
	# Out of range on disk: clamped to the tuning ranges (0.3-1.0 s, 0.2-0.6 s).
	store.whisper_hold_s = 2.0
	store.shout_window_s = 0.05
	assert_eq(store.save(CFG), OK)
	assert_eq(again.load_from(CFG), OK)
	assert_almost_eq(again.whisper_hold_s, 1.0, 1e-6)
	assert_almost_eq(again.shout_window_s, 0.2, 1e-6)

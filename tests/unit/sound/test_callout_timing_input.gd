extends GutTest
## SND-11 (GDD §14.5): with the timing option a hold of voice.callout_whisper_hold_s whispers, a tap
## talks once the shout window has passed with no second tap, and a double tap inside the window
## shouts once (never a talk first). Both settings move across their ranges and the input follows.


func before_all() -> void:
	assert_true(Tuning.load_client())


func _pick(hold_s: float, gap_s: float) -> Array:
	return [ActionRecord.Kind.CALLOUT, Intents.wheel_arg_timing(roundi(hold_s * 1000.0), roundi(gap_s * 1000.0) if gap_s >= 0.0 else -1), 0]


func _bands(sent: Array[Array]) -> Array[int]:
	var out: Array[int] = []
	for a: Array in sent:
		if int(Variants.number(a[0])) == ActionRecord.Kind.CALLOUT:
			out.append(CalloutLines.band_of(Intents.decode_wheel_arg(int(Variants.number(a[1])))))
	return out


func test_hold_tap_and_double_tap_at_the_defaults() -> void:
	var store: BindingsStore = BindingsStore.new()
	var w: CalloutWheel = CalloutWheel.new(store)
	assert_eq(_bands(w.filter([_pick(0.5, -1.0)] as Array[Array], 0.0)), [CalloutLines.WHISPER] as Array[int], "a 0.5 s hold whispers")
	assert_eq(_bands(w.filter([_pick(0.1, -1.0)] as Array[Array], 1.0)), [] as Array[int], "a tap waits for the window")
	assert_eq(_bands(w.filter([] as Array[Array], 1.2)), [] as Array[int])
	assert_eq(_bands(w.filter([] as Array[Array], 1.31)), [CalloutLines.TALK] as Array[int], "no second tap: it talks")
	assert_eq(_bands(w.filter([_pick(0.1, -1.0)] as Array[Array], 2.0)), [] as Array[int])
	assert_eq(_bands(w.filter([_pick(0.1, 0.2)] as Array[Array], 2.2)), [CalloutLines.SHOUT] as Array[int], "a double tap shouts")
	assert_eq(_bands(w.filter([] as Array[Array], 3.0)), [] as Array[int], "and never talked first")
	var other: Array[Array] = [[ActionRecord.Kind.TAP_ROCK, 0, 0]]
	assert_eq(w.filter(other, 4.0), other, "everything else passes as it was")


func test_the_settings_move_across_their_ranges() -> void:
	for hold: float in [0.3, 1.0]:
		var store: BindingsStore = BindingsStore.new()
		store.whisper_hold_s = hold
		var w: CalloutWheel = CalloutWheel.new(store)
		assert_eq(_bands(w.filter([_pick(hold, -1.0)] as Array[Array], 0.0)), [CalloutLines.WHISPER] as Array[int], "hold %.1f s whispers" % hold)
		assert_eq(_bands(w.filter([_pick(hold - 0.11, -1.0)] as Array[Array], 1.0)), [] as Array[int], "shorter: a tap")
	for window: float in [0.2, 0.6]:
		var store: BindingsStore = BindingsStore.new()
		store.shout_window_s = window
		var w: CalloutWheel = CalloutWheel.new(store)
		w.filter([_pick(0.1, -1.0)] as Array[Array], 0.0)
		assert_eq(_bands(w.filter([] as Array[Array], window - 0.01)), [] as Array[int], "still waiting inside %.1f s" % window)
		assert_eq(_bands(w.filter([] as Array[Array], window + 0.01)), [CalloutLines.TALK] as Array[int], "then talks")

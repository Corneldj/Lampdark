extends GutTest
## RSC-06 (Gameplay §11.9, §13.2, GDD §14.3): the lampman at Lamp Check. He reads each number digit
## by digit, waits in silence at each empty hook and gives one remark keyed to the cause, every line
## subtitled; the band is silent while he reads and plays before and after. The screen hangs each
## check as he reaches it, then shows the card; a friend's Ready goes once.

const HOOKS: Array = [{"lamp": 108, "hangs": true}, {"lamp": 114, "hangs": false}, {"lamp": 131, "hangs": true},
	{"lamp": 162, "hangs": true}, {"lamp": 207, "hangs": true}]
const CARD: String = "Morrow Main, first shift. Up 4 of 5. Left Below: Ada Rowe, Lamp 114. Deepest: the Third Level. Below 1 h 42 min."


func before_all() -> void:
	assert_true(Tuning.load_client())


func _len(line_id: String, _form: String) -> float:
	return 0.4 if line_id.begins_with("digit_") else 2.0


func _opening(hooks: Array, remark: String, wipe: bool = false, public_s: float = 0.0) -> Dictionary:
	return {"kind": LampCheckWire.OPEN, "run_uuid": "lamp-check-test", "hooks": hooks, "remark": remark, "card": CARD,
		"wipe": wipe, "own": "escaped", "public_s": public_s}


func test_he_reads_digit_by_digit_waits_at_empty_hooks_then_remarks() -> void:
	var q: LampmanSequence = LampmanSequence.build(HOOKS, "drag", _len)
	assert_eq([q.digits_read(0), q.digits_read(1), q.digits_read(2), q.digits_read(3), q.digits_read(4)], ["108", "", "131", "162", "207"])
	var forms: Array[String] = []
	var silences: Array[int] = []
	var remarks: Array[String] = []
	for s: LampmanSequence.Step in q.steps:
		if s.kind == "digit" and s.hook == 0:
			forms.append(s.form)
		elif s.kind == "silence":
			silences.append(s.hook)
			assert_almost_eq(s.length_s, Tuning.f(&"rescue.lamp_check_silence_s"), 1e-6, "his silence at the empty hook")
			assert_eq(s.key, "", "nothing said")
		elif s.kind == "remark":
			remarks.append(s.key)
			assert_gt(s.start_s, q.steps[q.steps.size() - 2].end_s() - 1e-6, "after the last hook")
	assert_eq(forms, ["continuing", "continuing", "final"] as Array[String], "'One... oh... eight'")
	assert_eq(silences, [1] as Array[int], "silence at hook 114 only")
	assert_eq(remarks, ["lampman.remark.drag"] as Array[String], "one remark, keyed to the cause")
	# Steps never overlap: one voice, one line at a time.
	for i: int in q.steps.size() - 1:
		assert_lte(q.steps[i].end_s(), q.steps[i + 1].start_s + 1e-6)
	assert_false(q.reading(q.reading_from_s - 0.01), "the band plays before he starts")
	assert_true(q.reading(q.reading_from_s + 0.01))
	assert_true(q.reading(q.reading_to_s - 0.01))
	assert_false(q.reading(q.reading_to_s + 0.01), "and after his last word")


func test_a_wipe_is_silence_at_every_hook() -> void:
	var hooks: Array = [{"lamp": 301, "hangs": false}, {"lamp": 302, "hangs": false}]
	var q: LampmanSequence = LampmanSequence.build(hooks, "roof_fall", _len)
	var kinds: Array[String] = []
	for s: LampmanSequence.Step in q.steps:
		kinds.append(s.kind)
	assert_eq(kinds, ["silence", "silence", "remark"] as Array[String], "no check hangs, no number read")
	var nobody: LampmanSequence = LampmanSequence.build([{"lamp": 101, "hangs": true}], "", _len)
	for s: LampmanSequence.Step in nobody.steps:
		assert_ne(s.kind, "remark", "nobody fell: no remark")


func test_the_screen_speaks_subtitles_hangs_and_quiets_the_band() -> void:
	var v: LampCheckView = LampCheckView.new()
	add_child_autofree(v)
	var subs: Array[String] = []
	v.subtitle = func(key: String, _d: float, _now: float) -> void: subs.append(key)
	v.open(_opening(HOOKS, "drag"), 10.0)
	var q: LampmanSequence = v.sequence
	assert_true(v.band_audible(), "the band plays as it opens")
	var heard_band_while_reading: bool = false
	var t: float = 0.0
	while t < q.reading_to_s + 0.5:
		v.step(10.0 + t)
		if q.reading(t + 1e-3) and t > q.reading_from_s + 0.05 and v.band_audible():
			heard_band_while_reading = true
		t += 0.05
	assert_false(heard_band_while_reading, "silent while he reads")
	assert_true(v.band_audible(), "and back after")
	assert_eq(v.hung, [true, false, true, true, true] as Array[bool], "the checks of those who came up")
	var expected: Array[String] = []
	for lamp: String in ["108", "131", "162", "207"]:
		for d: int in lamp.length():
			expected.append("lampman.digit_" + lamp[d])
	expected.append("lampman.remark.drag")
	assert_eq(subs, expected, "every line subtitled, in order")
	for key: String in subs:
		assert_false(UiText.text(key).is_empty(), "%s has caption text" % key)
	assert_eq(v.spoken.size(), expected.size(), "every line spoken")
	assert_true(v.card_text() == CARD and v.find_child("Ready", true, false) != null)
	var ready: Button = v.find_child("Ready", true, false)
	assert_true(ready.visible, "friends: Ready once the card shows")
	var pressed: Array[int] = [0]
	v.ready_pressed.connect(func() -> void: pressed[0] += 1)
	ready.pressed.emit()
	v.press_ready()
	assert_eq(pressed[0], 1, "Ready goes once")


func test_public_has_no_ready_but_a_countdown() -> void:
	var v: LampCheckView = LampCheckView.new()
	add_child_autofree(v)
	v.open(_opening(HOOKS, "", false, 120.0), 0.0)
	v.step(v.sequence.reading_to_s + 1.0)
	var ready: Button = v.find_child("Ready", true, false)
	assert_false(ready.visible, "in public the pithead empties on its own")
	assert_false(v.is_friends())

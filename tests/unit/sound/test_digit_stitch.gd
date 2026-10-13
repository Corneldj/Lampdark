extends GutTest
## SND-13 (Gameplay §13.2): a lamp number is spoken digit by digit, each continuing but the last,
## which takes the final fall, in the given voice. One file per (voice, line, form): the wheel, the
## illusions and the roll call load the same bytes.


func test_114() -> void:
	assert_eq(VoiceManifest.stitch_digits("114"), [{"line_id": "digit_1", "form": "continuing"},
		{"line_id": "digit_1", "form": "continuing"}, {"line_id": "digit_4", "form": "final"}] as Array[Dictionary])
	assert_eq(VoiceManifest.stitch_digits("7"), [{"line_id": "digit_7", "form": "final"}] as Array[Dictionary])
	assert_eq(VoiceManifest.stitch_digits("1a4"), [] as Array[Dictionary], "digits only")


func test_in_the_given_voice() -> void:
	var a: Array[PackedByteArray] = VoiceBank.digits("voice_3", "114")
	assert_eq(a.size(), 3)
	assert_eq(a[0], FileAccess.get_file_as_bytes("res://client/audio/voices/voice_3/digit_1.continuing.lbv"))
	assert_eq(a[0], a[1])
	assert_eq(a[2], FileAccess.get_file_as_bytes("res://client/audio/voices/voice_3/digit_4.final.lbv"))
	assert_ne(VoiceBank.line("voice_3", "digit_1", "continuing"), VoiceBank.line("voice_3", "digit_1", "final"), "the fall differs")
	assert_ne(VoiceBank.digits("voice_6", "114")[0], a[0], "another voice, another file")
	for f: PackedByteArray in a:
		assert_false(VoiceBank.parse(f).is_empty(), "a playable .lbv")


func test_one_file_for_wheel_illusion_and_roll_call() -> void:
	var wheel: PackedByteArray = VoiceBank.callout("voice_2", "here", "talk")
	var false_here: PackedByteArray = VoiceBank.illusion("voice_2", "here", "talk")
	assert_false(wheel.is_empty())
	assert_eq(false_here, wheel, "a false 'Here!' is the very file the wheel plays")
	var roll: Array[PackedByteArray] = VoiceBank.roll_call("voice_2", "114")
	assert_eq(roll.size(), 5, "'Lamp', one, one, four, 'all right'")
	assert_eq(roll[0], VoiceBank.line("voice_2", "roll_lamp", "talk"))
	assert_eq(roll.slice(1, 4), VoiceBank.digits("voice_2", "114"), "the roll call's digits are the illusion's digits")
	assert_eq(roll[4], VoiceBank.line("voice_2", "roll_all_right", "talk"))

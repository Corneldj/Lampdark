extends GutTest
## SND-11's client side: a record plays the line's recorded frames with the dropped ones concealed
## (the same length either way), and hands UI-03 its words' kept shares, band, voice and direction
## (none for a phone line or a dry channel).


func before_all() -> void:
	assert_true(Tuning.load_client())


func _record(mask_kept: Array[int], flags: int = 0) -> CalloutRecord:
	var r: CalloutRecord = CalloutRecord.new()
	r.voice = VoiceManifest.wire_voice("voice_3")
	r.line = VoiceManifest.wire_line("moth")
	r.band = CalloutLines.SHOUT
	r.apparent = Vector2(14, 10)
	r.flags = flags
	var n: int = VoiceManifest.frames_of("voice_3", "moth", "shout")
	r.mask.resize(n)
	for i: int in n:
		r.mask[i] = 1
	for i: int in mask_kept:
		r.mask[i] = 0
	return r


func test_masked_frames_are_concealed_not_skipped() -> void:
	var file: PackedByteArray = VoiceBank.callout("voice_3", "moth", "shout")
	var whole: PackedFloat32Array = CalloutPlayer.decode(file, _record([]).mask)
	var lossy: PackedFloat32Array = CalloutPlayer.decode(file, _record([2, 3, 4, 5, 6]).mask)
	assert_gt(whole.size(), 0)
	assert_eq(lossy.size(), whole.size(), "the bark keeps its length")
	assert_ne(lossy, whole, "the lost frames sound different")


func test_captions_from_the_record() -> void:
	var player: CalloutPlayer = CalloutPlayer.new()
	var got: Array = []
	player.on_caption = func(r: CalloutRecord, key: String, shares: PackedFloat32Array, direction: Variant, duration_s: float) -> void:
		got.append([key, shares, direction, duration_s, r.band])
	var n: int = VoiceManifest.frames_of("voice_3", "moth", "shout")
	var first_half: Array[int] = []
	for i: int in n / 2:
		first_half.append(i)
	player.play(_record(first_half), Vector2(10, 10))
	player.play(_record([], CalloutRecord.FLAG_TELEPHONE), Vector2(10, 10))
	assert_eq(got.size(), 2)
	var a: Array = got[0]
	assert_eq(str(a[0]), "callout.moth")
	var shares: PackedFloat32Array = a[1]
	assert_eq(shares.size(), UiText.text("callout.moth").split(" ", false).size(), "one share a word")
	assert_lt(shares[0], 0.5, "the first word was lost")
	assert_eq(shares[shares.size() - 1], 1.0, "the last word arrived")
	var dir: Variant = a[2]
	var at: Vector2 = dir if dir is Vector2 else Vector2.INF
	assert_eq(at, Vector2(4, 0), "from where it seemed to come")
	var b: Array = got[1]
	var none: Variant = b[2]
	var is_none: bool = none == null
	assert_true(is_none, "a phone line has no direction")
	var sys: CaptionSystem = CaptionSystem.new()
	sys.on_callout(str(a[0]), shares, CalloutLines.SHOUT, "voice_3", dir, float(Variants.number(a[3])), 0.0)
	assert_string_starts_with(str(sys.visible_lines()[0]["text"]), UiText.text("caption.word_gap"), "the caption shows the gap")

extends GutTest
## UI-03: every SND-02 event type and SND-03 local sound has a caption kind and a text key with text;
## the creature tells are diffuse; the design's named captions read as named; and no caption string
## carries a distance, a number or a unit.

const NAMED: Dictionary = {"caption.noise.cough": "[cough]", "caption.noise.drag_scrape": "[something dragged]",
	"caption.noise.moth_laying": "[wet ticking]", "caption.local.firedamp_hiss": "[gas hissing]",
	"caption.local.hatch_ticking": "[ticking, close]", "caption.local.moth_stir": "[a dry rustle, rising]",
	"caption.local.moth_awake": "[a dry rustle]", "caption.noise.rock_tap.diffuse": "[taps in the rock]",
	"caption.silence.drips.stop": "[the drip stops]", "caption.ringing": "[ringing]", "caption.voice": "[voice]",
	"caption.voice.broken": "[voice, broken]", "caption.stythe.breath": "[a slow breath, all around]"}


func before_all() -> void:
	assert_true(Tuning.load_client())


func test_every_type_has_a_kind_and_text() -> void:
	var types: Array[int] = []
	for raw: Variant in NoiseTypes.Type.values() + LocalSounds.Type.values():
		var t: int = raw
		types.append(t)
	for t: int in types:
		if t == 0:
			continue
		assert_true(CaptionTable.has(t), "type %d (%s) has a caption kind" % [t, CaptionTable.id_of(t)])
		assert_false(UiText.text(CaptionTable.key_of(t)).is_empty(), "type %d (%s) has caption text" % [t, CaptionTable.id_of(t)])
	for t: int in [LocalSounds.Type.MOTH_STIR, LocalSounds.Type.MOTH_SETTLE, LocalSounds.Type.MOTH_AWAKE, LocalSounds.Type.MOTH_THRUM]:
		assert_eq(CaptionTable.kind_of(t), CaptionTable.Kind.DIFFUSE, "the Moth's tells come from nowhere")
	assert_eq(CaptionTable.kind_of(NoiseTypes.Type.ROCK_TAP), CaptionTable.Kind.POSITIONAL)
	assert_eq(CaptionTable.kind_of(NoiseTypes.Type.ROCK_TAP, AudioRecord.DIFFUSE), CaptionTable.Kind.DIFFUSE, "a diffuse record is a diffuse tell")
	assert_eq(UiText.text(CaptionTable.key_of(NoiseTypes.Type.ROCK_TAP, AudioRecord.DIFFUSE)), "[taps in the rock]")
	assert_eq(CaptionTable.kind_of(NoiseTypes.Type.VOICE), CaptionTable.Kind.VOICE)
	assert_eq(CaptionTable.kind_of(NoiseTypes.Type.CALLOUT), CaptionTable.Kind.CALLOUT)


func test_the_named_captions_read_as_the_design_names_them() -> void:
	for key: String in NAMED.keys():
		assert_eq(UiText.text(key), str(NAMED[key]), key)


func test_no_caption_says_how_far_or_whose() -> void:
	var doc: Dictionary = Variants.dict(JSON.parse_string(FileAccess.get_file_as_string(CaptionTable.PATH)))
	var strings: Dictionary = Variants.dict(doc["strings"])
	var forbidden: RegEx = RegEx.create_from_string("[0-9]|\\b(tiles?|metres?|meters?|yards?|feet|foot|distance|away|far|near|nearby|name|lamp \\d)\\b")
	for raw: Variant in strings.keys():
		var text: String = str(strings[raw]).to_lower()
		assert_null(forbidden.search(text), "%s: '%s' carries no distance, number or name" % [raw, text])

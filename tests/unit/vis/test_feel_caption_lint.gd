extends GutTest
## VIS-07: every feel and bump caption is bracketed, silent text that never names a person or a
## lamp number: no digits, no capitals (names), and a string for every caption key the server uses.

const CAPTIONS: String = "res://data/text/captions_feel.json"


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_lint() -> void:
	var strings: Dictionary = Variants.dict(Variants.dict(JSON.parse_string(FileAccess.get_file_as_string(CAPTIONS)))["strings"])
	var digits: RegEx = RegEx.create_from_string("[0-9]")
	var capitals: RegEx = RegEx.create_from_string("[A-Z]")
	for raw: Variant in strings.keys():
		var text: String = str(strings[raw])
		assert_true(text.begins_with("[") and text.ends_with("]"), "%s is a bracketed caption" % raw)
		assert_null(digits.search(text), "%s: no numbers" % raw)
		assert_null(capitals.search(text), "%s: no names" % raw)
	for name: String in ItemKinds.Kind.keys():
		if name != "NONE":
			assert_true(strings.has("feel.item." + name.to_lower()), "a caption for %s" % name)
	for key: String in ["feel.body_breathing", "feel.body_cold", "feel.someone_standing", "feel.iron_jaws", "feel.rotten_boards",
			"feel.heap_of_coats", "feel.coats_moving", "feel.telephone", "feel.timber", "feel.cold_soot", "feel.nothing",
			"caption.bump.rock", "caption.bump.brick", "caption.bump.timber", "caption.bump.steel"]:
		assert_true(strings.has(key), key)

extends GutTest
## DIR-04: in-game text never says "ring": it names the Level. All five Level names exist, and no
## player-facing string under data/text/ contains the whole word "ring" (notes excluded).

const TEXT: String = "res://data/text"


func test_level_names() -> void:
	for ring: int in 5:
		assert_ne(Depth.level_name(ring), "", "level.%d exists" % ring)
	assert_eq(Depth.level_name(4), "the Deep")
	assert_eq(Depth.level_name_key(9), "level.4")


func test_no_ring_in_player_text() -> void:
	var word: RegEx = RegEx.create_from_string("(?i)\\bring\\b")
	var checked: int = 0
	for f: String in DirAccess.get_files_at(TEXT):
		if not f.ends_with(".json"):
			continue
		for s: String in _strings(JSON.parse_string(FileAccess.get_file_as_string(TEXT.path_join(f)))):
			assert_null(word.search(s), "%s: %s" % [f, s])
			checked += 1
	assert_gt(checked, 10)


func _strings(v: Variant) -> Array[String]:
	var out: Array[String] = []
	if v is String:
		out.append(str(v))
	elif v is Dictionary:
		var d: Dictionary = v
		for k: Variant in d.keys():
			if str(k) != "note":
				out.append_array(_strings(d[k]))
	elif v is Array:
		for item: Variant in Variants.array(v):
			out.append_array(_strings(item))
	return out

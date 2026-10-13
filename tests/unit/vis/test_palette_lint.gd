extends GutTest
## VIS-06 (GDD §14.1): badges, UI and close-ups never use amber, umber, egg-glow or firedamp blue;
## magenta appears only in FND-08's QA overlay; the six badges differ in value as well as hue, and
## each has its own pattern.

const NEAR: float = 0.18


func test_badges_avoid_world_colours() -> void:
	for i: int in Palette.BADGE_COLOURS.size():
		for reserved: Color in Palette.RESERVED_FOR_WORLD:
			assert_gt(Palette.distance(Palette.BADGE_COLOURS[i], reserved), NEAR, "badge %s keeps clear of %s" % [Palette.BADGE_PATTERNS[i], reserved])


func test_six_patterns_six_colours() -> void:
	assert_eq(Palette.BADGE_COLOURS.size(), 6)
	assert_eq(Palette.BADGE_PATTERNS, ["plain", "cross", "bar", "dot", "chevron", "ring"] as Array[String])


func test_no_magenta_outside_the_qa_overlay() -> void:
	var hits: Array[String] = []
	for dir: String in ["res://client", "res://shared"]:
		_scan(dir, hits)
	assert_eq(hits, [] as Array[String], "magenta only in FND-08's overlay")


func _scan(dir: String, hits: Array[String]) -> void:
	var d: DirAccess = DirAccess.open(dir)
	if d == null:
		return
	for f: String in d.get_files():
		var path: String = dir.path_join(f)
		if not (f.ends_with(".gd") or f.ends_with(".tscn") or f.ends_with(".tres") or f.ends_with(".gdshader")):
			continue
		if path.contains("qa_overlay") or path.ends_with("palette.gd"):
			continue
		var text: String = FileAccess.get_file_as_string(path)
		for pattern: String in ["Color(1, 0, 1", "Color(1.0, 0.0, 1.0", "QA_MAGENTA", "Color.MAGENTA"]:
			if text.contains(pattern):
				hits.append("%s: %s" % [path, pattern])
	for sub: String in d.get_directories():
		_scan(dir.path_join(sub), hits)

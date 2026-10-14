extends GutTest
## UI-01 (Gameplay §9.1, §14.3; GDD §14.1): nothing in play shows a name, lamp number, marker,
## outline, health or stamina bar, meter, progress bar, clock or timer, objective, kill feed, minimap
## or compass. A lint over the in-play strings, the elements' node types and drawing code, and their
## colours (never the world's amber, umber, egg-glow or firedamp blue).

const TEXT_FILES: Array[String] = ["res://data/text/ui_inplay.json", "res://data/text/verbs.json"]
const INPLAY_DIR: String = "res://client/ui/inplay"
const FORBIDDEN_WORDS: Array[String] = ["name", "marker", "outline", "health", "stamina", "meter", "progress", "clock", "timer",
	"objective", "kill", "minimap", "map", "compass", "score", "percent", "%", "hp", "ammo", "distance", "metre", "seconds"]
## Node types that are bars, timers or free text boxes.
const FORBIDDEN_NODES: Array[String] = ["ProgressBar", "TextureProgressBar", "Range", "Label", "RichTextLabel", "LineEdit",
	"TextEdit", "Timer", "SubViewport", "Camera2D"]
const NEAR: float = 0.18


func before_all() -> void:
	assert_true(Tuning.load_client())


func _strings() -> Dictionary:
	var out: Dictionary = {}
	for path: String in TEXT_FILES:
		out.merge(Variants.dict(Variants.dict(JSON.parse_string(FileAccess.get_file_as_string(path)))["strings"]))
	return out


func test_in_play_strings_carry_no_forbidden_content() -> void:
	var strings: Dictionary = _strings()
	var digits: RegEx = RegEx.create_from_string("[0-9]")
	for raw: Variant in strings.keys():
		var key: String = str(raw)
		var text: String = str(strings[raw]).to_lower()
		for word: String in FORBIDDEN_WORDS:
			assert_false(RegEx.create_from_string("\\b%s\\b" % word).search(text) != null if word != "%" else text.contains("%"),
				"%s: never '%s'" % [key, word])
		if not key.begins_with("wheel.chalk."):
			assert_null(digits.search(text), "%s: no numbers (the chalk wheel's digits are chalk)" % key)


func test_every_key_an_element_can_show_has_text() -> void:
	var keys: Array[String] = ["ui.aside", "ui.lamp_lit", "ui.lamp_out"]
	for kind: String in ["callout", "job_page", "signal", "chalk"]:
		keys.append_array(WheelWidget.slices_for(kind) if kind != "job_page" else WheelWidget.slices_for("callout", true))
	for kind: int in SeenKind.Kind.values():
		for cues: int in [0, MinerCues.LYING_BREATHING, MinerCues.LYING_STILL]:
			var verb: String = InteractionVerbs.for_seen(kind, cues)
			if not verb.is_empty():
				keys.append(verb)
	for option: String in ["hand_over", "douse", "share_oil", "pass_flame", "lift", "take", "cure", "revive"]:
		keys.append("ring.%s" % option)
	for key: String in keys:
		assert_ne(UiText.text(key), "", "%s has text" % key)
	assert_eq(UiText.text("no.such.key"), "", "an unknown key draws nothing, never the key itself")


func test_the_layer_holds_no_bars_timers_or_text_boxes() -> void:
	var l: InPlayLayer = InPlayLayer.new()
	add_child_autofree(l)
	var all: Array[Node] = l.find_children("*", "", true, false)
	assert_gt(all.size(), 0)
	for n: Node in all:
		for cls: String in FORBIDDEN_NODES:
			assert_false(n.is_class(cls), "%s is no %s" % [n.name, cls])
		assert_true(n is Node2D, "%s: every element is drawn by its own script" % n.name)


func test_the_drawing_code_takes_text_only_through_keys() -> void:
	# Each draw_string draws a string looked up from a key (UiText) or the binding's glyph label.
	var files: PackedStringArray = DirAccess.get_files_at(INPLAY_DIR)
	var draws: int = 0
	for f: String in files:
		if not f.ends_with(".gd"):
			continue
		var src: String = FileAccess.get_file_as_string(INPLAY_DIR.path_join(f))
		for cls: String in FORBIDDEN_NODES:
			assert_false(src.contains("%s.new(" % cls), "%s makes no %s" % [f, cls])
		for line: String in src.split("\n"):
			if line.contains("draw_string("):
				draws += 1
				var arg: String = _third_arg(line.substr(line.find("draw_string(") + 12))
				assert_true(arg in ["text", "caption", "verb", "key_label"] or arg.begins_with("UiText.text("), "%s: %s" % [f, line.strip_edges()])
			for m: RegExMatch in RegEx.create_from_string("var (text|caption|verb): String = (.*)").search_all(line):
				var rhs: String = m.get_string(2)
				assert_true(rhs.begins_with("UiText.text(") or rhs.begins_with("InteractionVerbs.for_seen("), "%s: %s" % [f, line.strip_edges()])
	assert_gt(draws, 5)


## The third top-level argument of a call's argument list (the string drawn).
static func _third_arg(args: String) -> String:
	var depth: int = 0
	var index: int = 0
	var start: int = 0
	for i: int in args.length():
		var c: String = args[i]
		if c == "(":
			depth += 1
		elif c == ")":
			depth -= 1
		elif c == "," and depth == 0:
			if index == 2:
				return args.substr(start, i - start).strip_edges()
			index += 1
			start = i + 1
	return args.substr(start).strip_edges()


func test_colours_keep_clear_of_the_worlds() -> void:
	for c: Color in [ScreenElementRegistry.INK, ScreenElementRegistry.DIM, ScreenElementRegistry.PANEL, ScreenElementRegistry.FLAME,
			BreathCloud.TINT]:
		for reserved: Color in Palette.RESERVED_FOR_WORLD:
			assert_gt(Palette.distance(c, reserved), NEAR, "%s keeps clear of %s" % [c, reserved])
	# Elements draw only in the registry's colours (no literal colour in their code).
	for f: String in DirAccess.get_files_at(INPLAY_DIR):
		if f.ends_with(".gd") and f != "screen_element_registry.gd":
			assert_false(FileAccess.get_file_as_string(INPLAY_DIR.path_join(f)).contains("Color(0"), "%s: no colour of its own" % f)


func test_text_meets_the_deck_minimum() -> void:
	var px: int = ScreenElementRegistry.min_font_px()
	assert_gte(px * ScreenElementRegistry.deck_scale(), Tuning.f(&"camera.ui_min_text_px_at_800p") - 1e-6,
		"at 1280x800 the smallest text is at least 16 px")
	for f: String in DirAccess.get_files_at(INPLAY_DIR):
		if not f.ends_with(".gd"):
			continue
		for line: String in FileAccess.get_file_as_string(INPLAY_DIR.path_join(f)).split("\n"):
			if line.contains("var size: int ="):
				assert_true(line.contains("ScreenElementRegistry.min_font_px()") and not line.contains(" - "),
					"%s sizes text from the minimum up: %s" % [f, line.strip_edges()])

extends GutTest
## CRT-01: one sense each. A static scan of server/creatures: no creature code references a
## client, an illusion, a seen set, the rewind history, or another creature's sense; each kind's
## directory names only its own sense.

const ROOT: String = "res://server/creatures"
const NEVER: Array[String] = ["ClientConnection", "client/", "Replication", "Illusion", "illusion", "run.vision", "Rewind", "run.rewind"]
const SENSES: Dictionary = {"moth": "LightSense", "tapper": "HearingSense", "stythe": "DarkSense"}


func _files(dir: String) -> Array[String]:
	var out: Array[String] = []
	for f: String in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d: String in DirAccess.get_directories_at(dir):
		out.append_array(_files(dir.path_join(d)))
	return out


func _code(path: String) -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	for line: String in FileAccess.get_file_as_string(path).split("\n"):
		if not line.strip_edges().begins_with("#"):
			lines.append(line)
	return lines


func test_no_creature_code_reads_a_client_an_illusion_or_a_rewind() -> void:
	var scanned: int = 0
	for path: String in _files(ROOT):
		# The spawner's start-tile guard reads the seen sets; it is not a sense.
		var skip_vision: bool = path.ends_with("framework/creature_system.gd")
		for line: String in _code(path):
			for word: String in NEVER:
				if skip_vision and word == "run.vision":
					continue
				assert_false(line.contains(word), "%s: %s" % [path, line.strip_edges()])
		scanned += 1
	assert_gt(scanned, 5)


func test_each_kind_reads_only_its_own_sense() -> void:
	for kind: String in SENSES.keys():
		var dir: String = ROOT.path_join(kind)
		if not DirAccess.dir_exists_absolute(dir):
			continue
		for path: String in _files(dir):
			for line: String in _code(path):
				for other: String in SENSES.keys():
					if other != kind:
						assert_false(line.contains(str(SENSES[other])), "%s reads the %s's sense" % [path, other])
	pass_test("the creature directories that exist were scanned")

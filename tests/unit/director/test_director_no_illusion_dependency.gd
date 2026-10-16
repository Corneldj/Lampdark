extends GutTest
## DIR-01: the Director reads only the true world (Gameplay §9.2: nothing in the simulation depends
## on an illusion). No code line under server/director/ names the illusion stage, an illusion, the
## lie log or its writers (CRT-10). Comment lines are skipped, so the rule can be explained there.

const ROOT: String = "res://server/director"
const FORBIDDEN: String = "(?i)illusion|lie_?log|\\blies\\b|ILLUSIONS"


func test_no_director_code_names_an_illusion_or_the_lie_log() -> void:
	var rx: RegEx = RegEx.create_from_string(FORBIDDEN)
	var checked: int = 0
	for path: String in _scripts(ROOT):
		var lines: PackedStringArray = FileAccess.get_file_as_string(path).split("\n")
		for i: int in lines.size():
			var line: String = lines[i].strip_edges()
			if line.begins_with("#"):
				continue
			var code: String = line.split("#")[0] if line.contains(" #") else line
			assert_null(rx.search(code), "%s:%d names an illusion: %s" % [path, i + 1, line])
		checked += 1
	assert_gt(checked, 3, "the Director's scripts were read")


## Every .gd under `dir`, recursively.
func _scripts(dir: String) -> Array[String]:
	var out: Array[String] = []
	for f: String in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d: String in DirAccess.get_directories_at(dir):
		out.append_array(_scripts(dir.path_join(d)))
	return out

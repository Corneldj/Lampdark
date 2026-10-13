extends SceneTree
## Checks that every Appendix A row of the Gameplay document and every GDD C.12 row is mapped
## in data/tuning/_coverage.json, to existing keys or to {"none": reason} (FND-05). Also
## validates every domain file. Exits 1 on any failure.
## Usage: godot --headless --path <game> -s tools/build/check_tuning_coverage.gd
##        [-- --gameplay <path> --gdd <path>] [-- --keys-only]
## The design documents default to ../../Docs/Design/ beside the game folder. They live outside
## the game repository, so CI (FND-04) passes --keys-only: every domain file and every key the
## coverage file names are still validated; matching rows against the design is left to local runs.

const COVERAGE: String = "res://data/tuning/_coverage.json"


func _init() -> void:
	var design_dir: String = ProjectSettings.globalize_path("res://").path_join("../../Docs/Design")
	var gameplay: String = design_dir.path_join("LAMPBLACK - Gameplay.md")
	var gdd: String = design_dir.path_join("LAMPBLACK - Game Design Document.md")
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var keys_only: bool = args.has("--keys-only")
	for index: int in args.size() - 1:
		if args[index] == "--gameplay":
			gameplay = args[index + 1]
		elif args[index] == "--gdd":
			gdd = args[index + 1]

	var problems: Array[String] = []
	var tuning: TuningSet = TuningSet.new()
	problems.append_array(tuning.load_directory(TuningSet.DATA_DIR))

	var rows: Array[String] = []
	if not keys_only:
		rows.append_array(design_row_ids(gameplay, "## Appendix A", "## Appendix B", "A."))
		rows.append_array(design_row_ids(gdd, "### C.12", "### C.13", "C.12"))
		if rows.is_empty():
			problems.append("no design rows found; check the document paths")

	var parsed: Variant = TuningSet.read_json(COVERAGE, problems)
	var coverage: Dictionary = Variants.dict(Variants.dict(parsed).get("rows", {}))
	if keys_only:
		print("check_tuning_coverage: --keys-only, design rows not matched")
	for row: String in rows:
		if not coverage.has(row):
			problems.append("unmapped design row: %s" % row)
	for row: Variant in coverage.keys():
		var mapping: Variant = coverage[row]
		if not keys_only and not str(row) in rows:
			problems.append("coverage names a row the design does not have: %s" % row)
		if mapping is Array:
			if Variants.array(mapping).is_empty():
				problems.append("%s: maps to no keys" % row)
			for key: Variant in Variants.array(mapping):
				if not tuning.has_key(StringName(str(key))):
					problems.append("%s: key %s does not exist" % [row, key])
		elif mapping is Dictionary:
			if str(Variants.dict(mapping).get("none", "")).is_empty():
				problems.append("%s: an unmapped row needs a 'none' reason" % row)
		else:
			problems.append("%s: mapping must be a key list or {\"none\": reason}" % row)

	if problems.is_empty():
		if keys_only:
			print("check_tuning_coverage: %d coverage rows name valid keys, %d keys valid" % [coverage.size(), tuning.entries.size()])
		else:
			print("check_tuning_coverage: %d design rows mapped, %d keys valid" % [rows.size(), tuning.entries.size()])
		quit(0)
	else:
		for problem: String in problems:
			printerr(problem)
		printerr("check_tuning_coverage: %d problems" % problems.size())
		quit(1)


## Row ids from the tables between start and end: "<section>/<parameter>", or
## "<section>/<sub-table>/<parameter>" where a short label line precedes the table
## (Appendix A.4's "Shared rules", "The Moth", ...).
static func design_row_ids(path: String, start: String, end: String, section_prefix: String) -> Array[String]:
	var ids: Array[String] = []
	if not FileAccess.file_exists(path):
		push_error("design document not found: %s" % path)
		return ids
	var on: bool = false
	var section: String = ""
	var sub: String = ""
	var section_pattern: RegEx = RegEx.create_from_string("^### ([A-C]\\.\\d+) ")
	for line: String in FileAccess.get_file_as_string(path).split("\n"):
		if line.begins_with(start):
			on = true
		elif on and line.begins_with(end):
			break
		if not on:
			continue
		var heading: RegExMatch = section_pattern.search(line)
		if heading != null:
			section = heading.get_string(1)
			sub = ""
			continue
		if section.is_empty() or not section.begins_with(section_prefix):
			continue
		var stripped: String = line.strip_edges()
		if not stripped.is_empty() and not line.begins_with("|") and not line.begins_with("#"):
			if line.length() < 60:
				sub = stripped.trim_prefix("**").trim_suffix("**").strip_edges()
			continue
		if line.begins_with("|") and not line.begins_with("|---") and not line.begins_with("| Parameter"):
			var parameter: String = line.strip_edges().trim_prefix("|").get_slice("|", 0).strip_edges()
			ids.append("%s/%s/%s" % [section, sub, parameter] if not sub.is_empty() else "%s/%s" % [section, parameter])
	return ids

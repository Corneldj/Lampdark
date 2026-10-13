extends SceneTree
## Writes a frozen full copy of the base tuning as a profile, e.g. QA-02's design_baseline,
## to data/tuning/profiles/<name>/ (FND-05).
## Usage: godot --headless --path <game> -s tools/build/freeze_tuning_profile.gd -- <name>


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 1 or not args[0].is_valid_filename():
		printerr("usage: freeze_tuning_profile.gd -- <profile name>")
		quit(2)
		return
	var tuning: TuningSet = TuningSet.new()
	var errors: Array[String] = tuning.load_directory(TuningSet.DATA_DIR)
	if not errors.is_empty():
		for error: String in errors:
			printerr(error)
		quit(1)
		return
	var dir: String = TuningSet.PROFILES_DIR.path_join(args[0])
	DirAccess.make_dir_recursive_absolute(dir)
	var by_domain: Dictionary = {}
	for key: Variant in tuning.entries.keys():
		var domain: String = str(key).get_slice(".", 0)
		if not by_domain.has(domain):
			by_domain[domain] = {}
		Variants.dict(by_domain[domain])[key] = tuning.entries[key]
	for domain: Variant in by_domain.keys():
		var file: FileAccess = FileAccess.open(dir.path_join("%s.json" % domain), FileAccess.WRITE)
		file.store_string(JSON.stringify({"domain": domain, "keys": by_domain[domain]}, "\t", false) + "\n")
		file.close()
	print("freeze_tuning_profile: wrote %d keys to %s" % [tuning.entries.size(), dir])
	quit(0)

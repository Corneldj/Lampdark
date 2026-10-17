class_name ResumeList
extends RefCounted
## MOD-05 (Gameplay §13.11; GDD §14.3): the runs this PC can resume from the Pithead: each run's newest
## save (its knock-off save or its last snapshot, by sequence number) that has not ended, the newest
## save first, as UI-04's resume list shows them: the list, the run time and the deepest ring reached.
## Read from the plain header alone: no section is opened. A public run is never saved, so never here.


## [{uuid, path, seq, kind, mode, list, run_time_s, deepest, saved_at}], the newest save first.
static func entries(root: String = "user://saves") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not DirAccess.dir_exists_absolute(root):
		return out
	for dir: String in DirAccess.get_directories_at(root):
		var run_dir: String = root.path_join(dir)
		if FileAccess.file_exists(run_dir.path_join(SaveStore.ENDED_FILE)):
			continue
		var best: Dictionary = {}
		for file: String in [SaveStore.KNOCKOFF_FILE, SaveStore.SNAPSHOT_FILE]:
			var path: String = run_dir.path_join(file)
			if not FileAccess.file_exists(path):
				continue
			var header: Dictionary = SaveContainer.read_header(FileAccess.get_file_as_bytes(path))
			if header.is_empty() or int(Variants.number(header.get("mode", -1))) == ServerConfig.Mode.PUBLIC:
				continue
			var seq: int = int(Variants.number(header.get("seq", 0)))
			if best.is_empty() or seq > int(Variants.number(best["seq"])):
				best = {"uuid": str(header.get("run_uuid", dir)), "path": path, "seq": seq, "kind": str(header.get("kind", "")),
					"mode": int(Variants.number(header.get("mode", 0))), "list": str(header.get("list", "")),
					"run_time_s": float(Variants.number(header.get("run_time_s", 0.0))), "deepest": int(Variants.number(header.get("deepest", 0))),
					"saved_at": FileAccess.get_modified_time(path)}
		if not best.is_empty():
			out.append(best)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(Variants.number(a["saved_at"])) > int(Variants.number(b["saved_at"])))
	return out

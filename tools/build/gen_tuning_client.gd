extends SceneTree
## Writes data/tuning/_client.json, the client-visible table that client packs ship instead
## of the domain files (FND-05). With --check, writes nothing and exits 1 if it is stale.
## Usage: godot --headless --path <game> -s tools/build/gen_tuning_client.gd [-- --check]


func _init() -> void:
	var tuning: TuningSet = TuningSet.new()
	var errors: Array[String] = tuning.load_directory(TuningSet.DATA_DIR)
	if not errors.is_empty():
		for error: String in errors:
			printerr(error)
		quit(1)
		return
	var table: Dictionary = tuning.client_table()
	var text: String = JSON.stringify(table, "\t", false) + "\n"
	var keys: Dictionary = table["keys"]
	if "--check" in OS.get_cmdline_user_args():
		if FileAccess.get_file_as_string(TuningSet.CLIENT_TABLE) != text:
			printerr("gen_tuning_client: %s is stale; run tools/build/gen_tuning_client.gd" % TuningSet.CLIENT_TABLE)
			quit(1)
			return
		print("gen_tuning_client: up to date (%d client keys)" % keys.size())
		quit(0)
		return
	var file: FileAccess = FileAccess.open(TuningSet.CLIENT_TABLE, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	print("gen_tuning_client: wrote %d client keys to %s" % [keys.size(), TuningSet.CLIENT_TABLE])
	quit(0)

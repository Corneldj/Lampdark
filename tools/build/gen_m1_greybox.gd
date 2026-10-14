extends SceneTree
## Writes data/maps/m1_greybox/ (GEN-03's grey box) from tools/build/m1_greybox_author.gd: the four
## cells through CellFile's canonical writer, the manifest and the placements.
## Usage: godot --headless --path <game> -s tools/build/gen_m1_greybox.gd
## The author is loaded once the autoloads exist (it reads GEN-02's arch length from tuning).

const DIR: String = "res://data/maps/m1_greybox"

var _done: bool = false


func _process(_delta: float) -> bool:
	if _done:
		return false
	_done = true
	root.get_node(^"/root/Tuning").call(&"load_server")
	var author: GDScript = load("res://tools/build/m1_greybox_author.gd")
	var built: Dictionary = author.call(&"build")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var cells: Dictionary = built["cells"]
	var status: int = 0
	for raw: Variant in cells.keys():
		var cell: Vector2i = raw
		var dict: Dictionary = cells[raw]
		var data: LbCellData = CellFile.from_dict(dict, "m1_greybox %s" % cell)
		if data == null:
			printerr("gen_m1_greybox: cell %s does not load" % cell)
			status = 1
			continue
		var path: String = CellFile.path_for("m1_greybox", cell)
		if CellFile.save(data, path) != OK:
			printerr("gen_m1_greybox: could not write %s" % path)
			status = 1
		else:
			print("wrote %s" % path)
	for name: String in ["manifest", "placements"]:
		var f: FileAccess = FileAccess.open("%s/%s.json" % [DIR, name], FileAccess.WRITE)
		f.store_string(JSON.stringify(built[name], "\t", false) + "\n")
		f.close()
		print("wrote %s/%s.json" % [DIR, name])
	quit(status)
	return true

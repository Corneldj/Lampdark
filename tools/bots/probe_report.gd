extends SceneTree
## NET-12's report command: tools/bots/probe_report.sh --rtt 120 --loss 0.02 [--minutes 1]
##   [--seed S] [--out DIR] [--plant-margin-delay-ms 100]
## Runs tools/bots/probe_run.gd and writes DIR/report.md, samples.csv and summary.json (default
## build/probes/rtt<rtt>_loss<pct>/). Exits 0 when criterion 4 passes, 1 when it fails, 2 on bad
## arguments. Autoloads join after _initialize, so the run starts on the first frame.

var _args: Dictionary = {}
var _out_dir: String = ""
var _done: bool = false


func _initialize() -> void:
	var a: PackedStringArray = OS.get_cmdline_user_args()
	_args = {"rtt_ms": 120, "loss": 0.02, "seconds": 60.0, "seed": 1, "plant_margin_delay_ms": 0.0}
	var i: int = 0
	while i < a.size():
		var key: String = a[i]
		var value: String = a[i + 1] if i + 1 < a.size() else ""
		match key:
			"--rtt":
				_args["rtt_ms"] = value.to_int()
			"--loss":
				_args["loss"] = value.to_float()
			"--minutes":
				_args["seconds"] = value.to_float() * 60.0
			"--seed":
				_args["seed"] = value.to_int()
			"--out":
				_out_dir = value
			"--plant-margin-delay-ms":
				_args["plant_margin_delay_ms"] = value.to_float()
			_:
				printerr("probe_report: unknown argument %s" % key)
				quit(2)
				return
		i += 2
	if _out_dir.is_empty():
		var rtt: int = _args["rtt_ms"]
		var loss: float = _args["loss"]
		_out_dir = "res://build/probes/rtt%d_loss%d" % [rtt, roundi(loss * 100.0)]


func _process(_delta: float) -> bool:
	if _done:
		return false
	_done = true
	root.get_node(^"/root/Tuning").call(&"load_server")
	var runner: GDScript = load("res://tools/bots/probe_run.gd")
	var r: Dictionary = runner.call(&"run", _args)
	var dir: String = ProjectSettings.globalize_path(_out_dir) if _out_dir.begins_with("res://") else _out_dir
	DirAccess.make_dir_recursive_absolute(dir)
	# Reports are not game resources: keep the editor and exports from importing the CSV.
	_write(dir.get_base_dir().path_join(".gdignore"), "")
	var md: String = runner.call(&"markdown", r)
	_write(dir.path_join("report.md"), md)
	_write(dir.path_join("samples.csv"), str(r["csv"]))
	var summary: Dictionary = r.duplicate()
	summary.erase("csv")
	_write(dir.path_join("summary.json"), JSON.stringify(summary, "\t"))
	print(md)
	print("probe_report: wrote %s" % dir)
	var passed: bool = r["criterion4_pass"]
	quit(0 if passed else 1)
	return true


func _write(path: String, text: String) -> void:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()

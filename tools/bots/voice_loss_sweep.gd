extends SceneTree
## SND-08's sweep (GDD §15.13, the register's "rates swept against failed utterances"):
##   godot --headless --path . -s tools/bots/voice_loss_sweep.gd -- [--utterances N] [--seed S] [--out DIR]
## Simulates utterances of 0.5-4 s through the live loss model (LbVoiceLoss.mask_for, the forwarder's
## own process) across distances from half range to the edge and every mix of the Stythe and a run,
## and reports, per cell, the share of utterances that keep under half their frames. The rates are
## the server's tuning. Writes DIR/voice_loss_sweep.md when --out is given; exits 2 on bad arguments.

const FRAME_S: float = 0.02
## Distance as a share of the route's range: clean up to voice.clean_range_fraction, the edge at 1.
const DISTANCES: Array[float] = [0.5, 0.6, 0.7, 0.8, 0.9, 1.0]
## [name, Stythe, running]
const MIXES: Array[Array] = [["clean", false, false], ["running", false, true], ["Stythe", true, false],
	["Stythe + running", true, true]]

var _args: Dictionary = {"utterances": 500, "seed": 1}
var _out_dir: String = ""
var _done: bool = false


func _initialize() -> void:
	var a: PackedStringArray = OS.get_cmdline_user_args()
	var i: int = 0
	while i < a.size():
		var value: String = a[i + 1] if i + 1 < a.size() else ""
		match a[i]:
			"--utterances":
				_args["utterances"] = value.to_int()
			"--seed":
				_args["seed"] = value.to_int()
			"--out":
				_out_dir = value
			_:
				printerr("voice_loss_sweep: unknown argument %s" % a[i])
				_done = true
				quit(2)
				return
		i += 2


func _process(_delta: float) -> bool:
	if _done:
		return false
	_done = true
	var tuning: Node = root.get_node(^"/root/Tuning")
	tuning.call(&"load_server")
	for key: StringName in [&"voice.clean_range_fraction", &"voice.edge_loss", &"voice.stythe_loss", &"voice.running_loss",
			&"voice.loss_run_min_frames", &"voice.loss_run_max_frames"]:
		_args[String(key).trim_prefix("voice.")] = tuning.call(&"f", key)
	var r: Dictionary = sweep(_args)
	var md: String = markdown(r)
	print(md)
	if not _out_dir.is_empty():
		var dir: String = ProjectSettings.globalize_path(_out_dir) if _out_dir.begins_with("res://") else _out_dir
		DirAccess.make_dir_recursive_absolute(dir)
		var f: FileAccess = FileAccess.open(dir.path_join("voice_loss_sweep.md"), FileAccess.WRITE)
		if f != null:
			f.store_string(md)
			f.close()
			print("voice_loss_sweep: wrote %s" % dir)
	quit(0)
	return true


## args: utterances (per cell), seed, clean_range_fraction, edge_loss, stythe_loss, running_loss,
## loss_run_min_frames, loss_run_max_frames. Returns {args, rows: [{distance, mix, p, kept, failed}]}:
## `kept` is the share of frames that arrived, `failed` the share of utterances keeping under half.
static func sweep(args: Dictionary) -> Dictionary:
	var n: int = int(Variants.number(args["utterances"]))
	var run_seed: int = int(Variants.number(args["seed"]))
	var run_min: int = roundi(float(Variants.number(args["loss_run_min_frames"])))
	var run_max: int = roundi(float(Variants.number(args["loss_run_max_frames"])))
	var lengths: RandomNumberGenerator = RandomNumberGenerator.new()
	lengths.seed = run_seed
	var rows: Array[Dictionary] = []
	var utterance: int = 0
	for fraction: float in DISTANCES:
		var dl: float = LbVoiceLoss.distance_loss(fraction, 1.0, float(Variants.number(args["clean_range_fraction"])),
			float(Variants.number(args["edge_loss"])))
		for mix: Array in MIXES:
			var p: float = LbVoiceLoss.combine(PackedFloat64Array([dl,
				float(Variants.number(args["stythe_loss"])) if Variants.flag(mix[1]) else 0.0,
				float(Variants.number(args["running_loss"])) if Variants.flag(mix[2]) else 0.0]))
			var frames_all: int = 0
			var kept_all: int = 0
			var failed: int = 0
			for u: int in n:
				utterance += 1
				var frames: int = roundi(lengths.randf_range(0.5, 4.0) / FRAME_S)
				var mask: PackedByteArray = LbVoiceLoss.mask_for(run_seed, utterance, 1, frames, p, run_min, run_max)
				var kept: int = 0
				for b: int in mask:
					kept += b
				frames_all += frames
				kept_all += kept
				if kept * 2 < frames:
					failed += 1
			rows.append({"distance": fraction, "mix": mix[0], "p": p, "kept": float(kept_all) / frames_all,
				"failed": float(failed) / n})
	return {"args": args, "rows": rows}


static func markdown(r: Dictionary) -> String:
	var args: Dictionary = r["args"]
	var lines: PackedStringArray = PackedStringArray([
		"# Voice loss sweep (SND-08)", "",
		"%d utterances of 0.5-4 s per cell, seed %d. Edge loss %.2f, Stythe %.2f, running %.2f, runs of %d-%d frames." % [
			int(Variants.number(args["utterances"])), int(Variants.number(args["seed"])), float(Variants.number(args["edge_loss"])),
			float(Variants.number(args["stythe_loss"])), float(Variants.number(args["running_loss"])),
			roundi(float(Variants.number(args["loss_run_min_frames"]))), roundi(float(Variants.number(args["loss_run_max_frames"])))],
		"", "Each cell: frames kept / utterances keeping under half their frames.", ""])
	var header: String = "| distance (share of range) |"
	var rule: String = "|---|"
	for mix: Array in MIXES:
		header += " %s |" % mix[0]
		rule += "---|"
	lines.append(header)
	lines.append(rule)
	var rows: Array = r["rows"]
	var i: int = 0
	for fraction: float in DISTANCES:
		var line: String = "| %.1f |" % fraction
		for mix: Array in MIXES:
			var row: Dictionary = rows[i]
			line += " %.0f%% / %.1f%% |" % [float(Variants.number(row["kept"])) * 100.0, float(Variants.number(row["failed"])) * 100.0]
			i += 1
		lines.append(line)
	return "\n".join(lines) + "\n"

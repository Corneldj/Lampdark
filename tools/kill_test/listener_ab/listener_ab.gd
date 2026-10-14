extends Node
## QA-01 criterion 5's blind A/B harness (Gameplay §6.10). On headphones (HRTF), a tone or a footstep
## plays 4 tiles north or south of the tester's miner; the tester answers N or S. Under the
## facing-relative listener the tester may turn (Left and Right, or Q and E) before answering; under
## screen-up the ears stay north whatever the facing. Conditions show only as A and B. Each answer is
## a JSON line in the results file; the meaning of A and B is written once, at the top.
##   godot --path . res://tools/kill_test/listener_ab/listener_ab.tscn -- --tester T07 --seed 7 \
##     [--out user://listener_ab] [--speakers] [--trials 20]
## Results pool across testers with tools/kill_test/listener_ab_report.py.

const Plan = preload("res://tools/kill_test/listener_ab/listener_ab_plan.gd")
const DISTANCE_TILES: float = 4.0
const TURN_DEG_S: float = 120.0
const LISTENER: Vector2 = Vector2(50.0, 50.0)

var tester: String = "T00"
var seed_value: int = 0
var trials_per_condition: int = Plan.TRIALS
var out_dir: String = "user://listener_ab"
var headphones: bool = true
## Tests answer by script: a Callable(trial) -> "N" or "S"; empty means the keyboard.
var auto_answer: Callable = Callable()
var plan: Dictionary = {}
var results: Array[Dictionary] = []
var mixer: SpatialMixer = null
var listener: MinerListener = null
var label: Label = Label.new()
var _index: int = -1
var _facing_deg: float = 270.0
var _started_ms: int = 0
var _file: FileAccess = null
var _screen_up_ok: bool = true

signal finished(path: String)


func _ready() -> void:
	_read_args(OS.get_cmdline_user_args())
	mixer = SpatialMixer.new()
	add_child(mixer)
	mixer.set_mode(SpatialMixer.Mode.HEADPHONES if headphones else SpatialMixer.Mode.SPEAKERS)
	listener = MinerListener.new(mixer)
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 40)
	add_child(label)
	plan = Plan.make(seed_value, trials_per_condition)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var path: String = out_dir.path_join("%s.jsonl" % tester)
	_file = FileAccess.open(path, FileAccess.WRITE)
	_file.store_line(JSON.stringify({"tester": tester, "seed": seed_value, "codes": plan["codes"], "headphones": headphones,
		"hrtf": mixer.hrtf_name(), "trials_per_condition": trials_per_condition}))
	_next()


func _read_args(args: PackedStringArray) -> void:
	var i: int = 0
	while i < args.size():
		var a: String = args[i]
		var v: String = args[i + 1] if i + 1 < args.size() else ""
		match a:
			"--tester":
				tester = v
				i += 1
			"--seed":
				seed_value = v.to_int()
				i += 1
			"--out":
				out_dir = v
				i += 1
			"--trials":
				trials_per_condition = maxi(2, v.to_int())
				i += 1
			"--speakers":
				headphones = false
		i += 1


func _trial() -> Dictionary:
	return Variants.dict(Variants.array(plan["trials"])[_index])


func _next() -> void:
	_index += 1
	if _index >= Variants.array(plan["trials"]).size():
		_finish()
		return
	var t: Dictionary = _trial()
	_facing_deg = 270.0  # every trial starts facing north, as screen-up always is
	_screen_up_ok = listener.set_mode(str(t["condition"]))
	listener.follow(LISTENER, Intents.facing_u16(_facing_deg))
	var at: Vector2 = LISTENER + Vector2(0.0, -DISTANCE_TILES if str(t["source"]) == "north" else DISTANCE_TILES)
	var wav: AudioStreamWAV = SampleBank.make("bell" if str(t["sound"]) == "tone" else "thump", 0.6, 9000 + _index)
	mixer.add(SampleBank.pcm(wav), SampleBank.RATE, at, -6.0, "Sfx")
	label.text = "%s\n\nNorth or south?   N  /  S" % Plan.shown(t)
	_started_ms = Time.get_ticks_msec()
	if auto_answer.is_valid():
		_answer.call_deferred(str(auto_answer.call(t)))


func _process(delta: float) -> void:
	if _index < 0 or auto_answer.is_valid():
		return
	var turn: float = 0.0
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_Q):
		turn -= 1.0
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_E):
		turn += 1.0
	if turn != 0.0:
		_facing_deg = fposmod(_facing_deg + turn * TURN_DEG_S * delta, 360.0)
		listener.follow(LISTENER, Intents.facing_u16(_facing_deg))


func _unhandled_input(event: InputEvent) -> void:
	var k: InputEventKey = event as InputEventKey
	if k == null or not k.pressed or k.echo or auto_answer.is_valid():
		return
	if k.keycode == KEY_N:
		_answer("N")
	elif k.keycode == KEY_S:
		_answer("S")


func _answer(answer: String) -> void:
	var t: Dictionary = _trial()
	var r: Dictionary = {"trial": t["index"], "code": t["code"], "source": t["source"], "sound": t["sound"], "answer": answer,
		"correct": (answer == "N") == (str(t["source"]) == "north"), "ms": Time.get_ticks_msec() - _started_ms,
		"turned_deg": snappedf(_facing_deg - 270.0, 1.0), "screen_up_available": _screen_up_ok}
	results.append(r)
	_file.store_line(JSON.stringify(r))
	_next()


func _finish() -> void:
	var path: String = _file.get_path_absolute()
	_file.close()
	label.text = "Thank you. That is all."
	finished.emit(path)

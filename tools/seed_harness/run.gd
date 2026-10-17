extends SceneTree
## GEN-14: the seed harness's command line (tools/seed_harness/harness_main.gd has its usage;
## tools/seed_harness/run.sh wraps this from the game's root). The harness reads the Tuning
## autoload, which exists only once the tree runs, so the harness loads on the first frame.


func _initialize() -> void:
	process_frame.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	var main: GDScript = load("res://tools/seed_harness/harness_main.gd")
	var code: int = Variants.whole(main.call("main", OS.get_cmdline_user_args()))
	quit(code)

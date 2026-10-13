extends Node
## The boot scene (FND-03): reads the build's tags and launch arguments, sets up logging,
## and hands a typed config to the server or client main. It loads the role's main by
## path at run time, because each export carries only its own role's code.

const SERVER_MAIN: String = "res://server/server_main.gd"
const CLIENT_MAIN: String = "res://client/client_main.gd"

## Tests replace this before the node enters the tree.
var features: FeatureProvider = FeatureProvider.new()


func _ready() -> void:
	var build: BuildInfo = BuildInfo.detect(features)
	var args: LaunchArgs = LaunchArgs.from_os(build)
	if not args.ok:
		printerr("lampblack: " + args.error)
		printerr(LaunchArgs.USAGE)
		get_tree().quit(ExitCode.BAD_ARGUMENTS)
		return

	var role: BuildInfo.Role = build.role_for(args.wants_server)
	var server_role: bool = role == BuildInfo.Role.SERVER
	var log_path: String = args.log_path
	if not server_role and log_path.is_empty():
		log_path = Log.CLIENT_LOG_DIR.path_join("client.log")
	Log.configure("server" if server_role else "client", args.log_level,
		server_role or not build.is_release(), log_path, build.is_release())
	Log.info("LAMPBLACK %s %s build, engine %s" % [
		build.flavour_name(), "server" if server_role else "client",
		Engine.get_version_info()["string"]])
	_log_native_core()
	for warning: String in args.warnings:
		Log.warn(warning)
	if args.wants_server and not server_role:
		Log.warn("--server ignored: this build runs the client")

	var main: Node = _instantiate(SERVER_MAIN if server_role else CLIENT_MAIN)
	if main == null:
		Log.error("role main missing from this build")
		get_tree().quit(ExitCode.FATAL)
		return
	get_tree().root.add_child.call_deferred(main)
	if server_role:
		main.call_deferred("start", args.server)
	else:
		main.call_deferred("start", args.client)
	queue_free()


## Every role needs lampblack_core (FND-02). Logs its version and build type.
func _log_native_core() -> void:
	if not ClassDB.class_exists(&"LbCoreInfo"):
		Log.error("native core lampblack_core is not loaded")
		return
	var version: String = str(ClassDB.class_call_static(&"LbCoreInfo", &"version"))
	var build_type: String = str(ClassDB.class_call_static(&"LbCoreInfo", &"build_type"))
	var sum: int = ClassDB.class_call_static(&"LbCoreInfo", &"add_i64", 0x7FFFFFFFFFFFFFFF, 1)
	Log.info("native core %s (%s), int64 wrap %s" % [version, build_type,
		"ok" if sum == -0x7FFFFFFFFFFFFFFF - 1 else "BROKEN"])


func _instantiate(path: String) -> Node:
	if not ResourceLoader.exists(path):
		return null
	var script: GDScript = load(path) as GDScript
	if script == null or not script.can_instantiate():
		return null
	var instance: Object = script.new()
	if instance == null or not instance.has_method(&"start"):
		return null
	return instance as Node

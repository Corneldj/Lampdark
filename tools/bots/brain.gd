extends RefCounted
## The base of every bot brain (FND-09): tools/bots/brains/<name>.gd extends this. The bot
## client (sockets) and the scenario kit's accelerated soaks (stream capture) drive the same
## brains: setup once, then think() once per client tick, returning that tick's input.

const BotContext = preload("res://tools/bots/bot_context.gd")
## The size of a dummy voice frame per tick: Opus at 24 kbps over 50 ms.
const VOICE_BYTES_PER_TICK: int = 150

var rng: LbRng = LbRng.from_seed(0)
var args: Dictionary = {}
var held: InputRecord = InputRecord.new()
## What this brain cannot do yet, for the bot's stats (for example, waiting on NET-04).
var notes: PackedStringArray = PackedStringArray()


func setup(seed_value: int, brain_args: Dictionary) -> void:
	rng = LbRng.from_seed(seed_value)
	args = brain_args


func think(_ctx: BotContext) -> InputRecord:
	return held


## Loads tools/bots/brains/<name>.gd; "name:arg" passes arg as args["arg"]. Null if unknown.
static func create(spec: String, seed_value: int) -> RefCounted:
	var name: String = spec.get_slice(":", 0)
	var path: String = "res://tools/bots/brains/%s.gd" % name
	if not ResourceLoader.exists(path):
		push_error("no bot brain named '%s' (%s)" % [name, path])
		return null
	var script: GDScript = load(path)
	var brain: RefCounted = script.new()
	var brain_args: Dictionary = {}
	if spec.contains(":"):
		brain_args["arg"] = spec.substr(name.length() + 1)
	brain.call(&"setup", seed_value, brain_args)
	return brain


static func direction_byte(deg: float) -> int:
	return posmod(roundi(fposmod(deg, 360.0) / 360.0 * InputRecord.DIRECTIONS), InputRecord.DIRECTIONS)


static func facing_u16(deg: float) -> int:
	return posmod(roundi(fposmod(deg, 360.0) / 360.0 * 65536.0), 65536)

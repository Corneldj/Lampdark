class_name DebugCommands
extends RefCounted
## FND-08: the one command registry the client console (backtick) and the server console (stdin)
## share, and its parser. Dev and QA builds only: this folder is not in a release pack. Every
## command is logged with its issuer and tick by whoever runs it; state-changing ones taint the run.
## A command whose system does not exist yet answers "not available" and changes nothing.
##
## Syntax (Proposed):
##   help [command]
##   spawn <moth|tapper|stythe> [here|x y] [state]      spawn item <type> [here|x y]
##   teleport <me|slot> <x> <y>
##   set_pull <all|slot> <0-100>                        set_intensity <all|slot> <0-100>
##   creatures <on|off> [moth|tapper|stythe]            freeze_ai <on|off>
##   apex <on|off>
##   truth <on|off> [layers...]                         overlay <on|off>
##   tuning set <key> <value>                           tuning reload
##   ring_override <0-4|off>                            seed
##   listener_mode <facing|screen_up>                   deafen <me|slot> [seconds]
##   sdr_fake <lag_ms> <loss_pct> | sdr_fake off

const CREATURES: Array[String] = ["moth", "tapper", "stythe"]
const LAYERS: Array[String] = ["entities", "creatures", "light", "vision", "sound", "director", "lies"]
## Where a command runs: on the issuing client only, or on the server (sent over the debug lane).
enum Where { CLIENT, SERVER, BOTH }

## name -> {usage, where, taints, help}
const SPEC: Dictionary = {
	"help": {"usage": "help [command]", "where": Where.CLIENT, "taints": false, "help": "lists the commands"},
	"spawn": {"usage": "spawn <moth|tapper|stythe> [here|x y] [state] | spawn item <type> [here|x y]", "where": Where.SERVER,
		"taints": true, "help": "places the run's single creature (moving it if present), or an item"},
	"teleport": {"usage": "teleport <me|slot> <x> <y>", "where": Where.SERVER, "taints": true,
		"help": "moves a miner to the tile, or the nearest open tile"},
	"set_pull": {"usage": "set_pull <all|slot> <0-100>", "where": Where.SERVER, "taints": true, "help": "sets the Pull (DIR-03)"},
	"set_intensity": {"usage": "set_intensity <all|slot> <0-100>", "where": Where.SERVER, "taints": true,
		"help": "sets the Draught intensity (DIR-01)"},
	"creatures": {"usage": "creatures <on|off> [moth|tapper|stythe]", "where": Where.SERVER, "taints": true,
		"help": "takes creatures out of the simulation and every perception, or puts them back"},
	"freeze_ai": {"usage": "freeze_ai <on|off>", "where": Where.SERVER, "taints": true,
		"help": "creatures, Hands and Bess stop deciding and moving; their timers pause"},
	"apex": {"usage": "apex <on|off>", "where": Where.SERVER, "taints": true,
		"help": "LFT-09's apex: the pit wakes (or sleeps again) whatever the engine"},
	"truth": {"usage": "truth <on|off> [entities|creatures|light|vision|sound|director|lies ...]", "where": Where.BOTH, "taints": false,
		"help": "the truth view on this client"},
	"overlay": {"usage": "overlay <on|off>", "where": Where.BOTH, "taints": false, "help": "the magenta illusion tags (QA servers)"},
	"tuning": {"usage": "tuning set <key> <value> | tuning reload", "where": Where.SERVER, "taints": true,
		"help": "FND-05's dev overrides"},
	"ring_override": {"usage": "ring_override <0-4|off>", "where": Where.SERVER, "taints": true,
		"help": "every ring lookup returns this ring"},
	"seed": {"usage": "seed", "where": Where.SERVER, "taints": false, "help": "the run seed, to this client only"},
	"listener_mode": {"usage": "listener_mode <facing|screen_up>", "where": Where.CLIENT, "taints": false,
		"help": "the ears face the miner's way, or north (criterion 5's A/B)"},
	"deafen": {"usage": "deafen <me|slot> [seconds]", "where": Where.SERVER, "taints": true,
		"help": "deafens a miner as a shot would (until MNR-16)"},
	"sdr_fake": {"usage": "sdr_fake <lag_ms> <loss_pct> | sdr_fake off", "where": Where.CLIENT, "taints": false,
		"help": "Steam's fake lag (round trip) and loss on this client's SDR connections (STM-03; M2's bad-connection tests)"},
}


## {ok, command, args, error, clamped (an argument was brought into range)}.
static func parse(line: String) -> Dictionary:
	var words: PackedStringArray = line.strip_edges().split(" ", false)
	if words.is_empty():
		return _fail("", "empty command")
	var name: String = words[0].to_lower()
	if not SPEC.has(name):
		return _fail(name, "unknown command '%s' (try help)" % name)
	var a: PackedStringArray = words.slice(1)
	var out: Dictionary = {"ok": true, "command": name, "args": {}, "error": "", "clamped": false}
	var args: Dictionary = out["args"]
	match name:
		"help":
			if a.size() > 1:
				return _usage(name)
			args["topic"] = a[0].to_lower() if a.size() == 1 else ""
		"spawn":
			if a.is_empty():
				return _usage(name)
			var what: String = a[0].to_lower()
			var rest: PackedStringArray = a.slice(1)
			if what == "item":
				if rest.is_empty():
					return _usage(name)
				args["what"] = "item"
				args["item"] = rest[0].to_lower()
				rest = rest.slice(1)
			elif CREATURES.has(what):
				args["what"] = what
			else:
				return _fail(name, "spawn what? %s" % SPEC[name]["usage"])
			var at: Variant = _place(rest)
			if at == null:
				return _usage(name)
			args["at"] = at
			var used: int = 0 if rest.is_empty() else (1 if rest[0].to_lower() == "here" else 2)
			if what == "item" and rest.size() > used:
				return _usage(name)
			args["state"] = rest[used].to_lower() if rest.size() > used else ""
			if rest.size() > used + 1:
				return _usage(name)
		"teleport":
			if a.size() != 3 or not a[1].is_valid_int() or not a[2].is_valid_int():
				return _usage(name)
			var who: Variant = _who(a[0], false)
			if who == null:
				return _usage(name)
			args["who"] = who
			args["tile"] = Vector2i(a[1].to_int(), a[2].to_int())
		"set_pull", "set_intensity":
			if a.size() != 2 or not a[1].is_valid_float():
				return _usage(name)
			var who: Variant = _who(a[0], true)
			if who == null:
				return _usage(name)
			args["who"] = who
			var v: float = a[1].to_float()
			var clamped_v: float = clampf(v, 0.0, 100.0)
			args["value"] = clamped_v
			out["clamped"] = v != clamped_v
		"creatures", "freeze_ai", "apex", "truth", "overlay":
			if a.is_empty() or not ["on", "off"].has(a[0].to_lower()):
				return _usage(name)
			args["on"] = a[0].to_lower() == "on"
			var rest: PackedStringArray = a.slice(1)
			if name == "creatures":
				if rest.size() > 1 or (rest.size() == 1 and not CREATURES.has(rest[0].to_lower())):
					return _usage(name)
				args["kind"] = rest[0].to_lower() if rest.size() == 1 else ""
			elif name == "truth":
				var layers: PackedStringArray = PackedStringArray()
				for l: String in rest:
					if not LAYERS.has(l.to_lower()):
						return _fail(name, "unknown layer '%s' (%s)" % [l, ", ".join(LAYERS)])
					layers.append(l.to_lower())
				args["layers"] = layers if not layers.is_empty() else PackedStringArray(LAYERS)
			elif not rest.is_empty():
				return _usage(name)
		"tuning":
			if a.size() == 1 and a[0].to_lower() == "reload":
				args["action"] = "reload"
			elif a.size() == 3 and a[0].to_lower() == "set":
				args["action"] = "set"
				args["key"] = a[1]
				args["value"] = a[2]
			else:
				return _usage(name)
		"ring_override":
			if a.size() != 1:
				return _usage(name)
			if a[0].to_lower() == "off":
				args["ring"] = -1
			elif a[0].is_valid_int():
				var r: int = a[0].to_int()
				var ring: int = clampi(r, 0, 4)
				args["ring"] = ring
				out["clamped"] = r != ring
			else:
				return _usage(name)
		"seed":
			if not a.is_empty():
				return _usage(name)
		"listener_mode":
			if a.size() != 1 or not ["facing", "screen_up"].has(a[0].to_lower()):
				return _usage(name)
			args["mode"] = a[0].to_lower()
		"sdr_fake":
			if a.size() == 1 and a[0].to_lower() == "off":
				args["lag_ms"] = 0
				args["loss_pct"] = 0.0
			elif a.size() == 2 and a[0].is_valid_int() and a[1].is_valid_float():
				args["lag_ms"] = clampi(a[0].to_int(), 0, 2000)
				args["loss_pct"] = clampf(a[1].to_float(), 0.0, 50.0)
				out["clamped"] = args["lag_ms"] != a[0].to_int() or args["loss_pct"] != a[1].to_float()
			else:
				return _usage(name)
		"deafen":
			if a.is_empty() or a.size() > 2 or (a.size() == 2 and not a[1].is_valid_float()):
				return _usage(name)
			var who: Variant = _who(a[0], false)
			if who == null:
				return _usage(name)
			args["who"] = who
			var s: float = a[1].to_float() if a.size() == 2 else -1.0
			var seconds: float = clampf(s, 0.0, 60.0) if s >= 0.0 else -1.0
			args["seconds"] = seconds
			out["clamped"] = s >= 0.0 and s != seconds
	return out


static func where(name: String) -> Where:
	return Variants.dict(SPEC.get(name, {})).get("where", Where.SERVER)


static func taints(name: String) -> bool:
	return Variants.flag(Variants.dict(SPEC.get(name, {})).get("taints", false))


static func help(topic: String = "") -> String:
	if topic.is_empty():
		var names: Array = SPEC.keys()
		names.sort()
		return "commands: " + ", ".join(PackedStringArray(names)) + " (help <command>)"
	if not SPEC.has(topic):
		return "unknown command '%s'" % topic
	var spec: Dictionary = SPEC[topic]
	return "%s: %s" % [spec["usage"], spec["help"]]


## "here", "x y" or nothing (here) -> "here" or a Vector2i; null when malformed.
static func _place(rest: PackedStringArray) -> Variant:
	if rest.is_empty() or rest[0].to_lower() == "here":
		return "here"
	if rest.size() >= 2 and rest[0].is_valid_int() and rest[1].is_valid_int():
		return Vector2i(rest[0].to_int(), rest[1].to_int())
	return null


## "me", a slot number, or (with `all_ok`) "all"; null when malformed.
static func _who(word: String, all_ok: bool) -> Variant:
	var w: String = word.to_lower()
	if w == "me" or (all_ok and w == "all"):
		return w
	if w.is_valid_int() and w.to_int() >= 0:
		return w.to_int()
	return null


static func _usage(name: String) -> Dictionary:
	return _fail(name, "usage: " + str(SPEC[name]["usage"]))


static func _fail(name: String, error: String) -> Dictionary:
	return {"ok": false, "command": name, "args": {}, "error": error, "clamped": false}

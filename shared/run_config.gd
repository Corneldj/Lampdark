class_name RunOptions
extends RefCounted
## MOD-03 (Gameplay §13.5, §13.6, §3.3; GDD §13.8): what a lobby's host picks for a run, and the only
## part of its setup that clients, lobby metadata (STM-02) and rich presence ever see: the mode, the
## repair list, a hard variant (one at most) and Hired Hands in empty places. What is secret (the
## seed, the draw, the staging level, the plan) is fixed on the server when the run is created
## (RunSetup) and never sent. The server validates every choice (RunSetup.refusal); a client only
## mirrors it.

## The repair list, as LFT-03's RepairList.Kind numbers it.
enum List { SHORT = 0, STANDARD = 1, FULL = 2 }

const LIST_NAMES: Array[String] = ["short", "standard", "full"]
## Gameplay §13.6's hard variants, as the run header names them (GEN-09, MOD-10).
const HARD_VARIANTS: Array[String] = ["one_lamp", "no_chalk", "dead_lines"]
const MODE_NAMES: Array[String] = ["friends", "public", "nightshift"]

var mode: ServerConfig.Mode = ServerConfig.Mode.FRIENDS
var list: List = List.STANDARD
## "" for none; more than one (comma-separated, as a malformed lobby might carry) is refused.
var hard_variant: String = ""
var hands_in_empty_places: bool = false


## A mode's starting options: the Escape on modes.default_list with no variant and Hands off
## (modes.hands_default_friends); public quick-play on the Short list, Hands filling at 45 s;
## Night Shift on the Short list.
static func defaults(of_mode: ServerConfig.Mode) -> RunOptions:
	var o: RunOptions = RunOptions.new()
	o.mode = of_mode
	match of_mode:
		ServerConfig.Mode.PUBLIC:
			o.list = List.SHORT
			o.hands_in_empty_places = true
		ServerConfig.Mode.NIGHTSHIFT:
			o.list = List.SHORT
		_:
			o.list = list_from(Tuning.s(&"modes.default_list")) if Tuning.current.has_key(&"modes.default_list") else List.STANDARD
			o.hands_in_empty_places = Tuning.current.has_key(&"modes.hands_default_friends") and Tuning.b(&"modes.hands_default_friends")
	return o


static func list_from(name: String) -> List:
	var i: int = LIST_NAMES.find(name.to_lower())
	return (i if i >= 0 else List.STANDARD) as List


static func mode_from(name: String) -> ServerConfig.Mode:
	var i: int = MODE_NAMES.find(name.to_lower())
	return (i if i >= 0 else ServerConfig.Mode.FRIENDS) as ServerConfig.Mode


## The variants named (more than one when malformed).
func hard_variants() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for raw: String in hard_variant.split(",", false):
		var v: String = raw.strip_edges()
		if not v.is_empty():
			out.append(v)
	return out


## STM-02's lobby form ({mode, list, hard, hands}: lb_mode, lb_list, lb_hard, lb_hands).
func to_dict() -> Dictionary:
	return {"mode": MODE_NAMES[int(mode)], "list": LIST_NAMES[int(list)], "hard": hard_variant, "hands": hands_in_empty_places}


static func from_dict(d: Dictionary) -> RunOptions:
	var o: RunOptions = RunOptions.new()
	o.mode = mode_from(str(d.get("mode", "friends")))
	o.list = list_from(str(d.get("list", "standard")))
	o.hard_variant = str(d.get("hard", "")) if str(d.get("hard", "")) != "none" else ""
	o.hands_in_empty_places = Variants.flag(d.get("hands", false))
	return o


## The server's command line for these options (LocalServerHost passes them on).
func to_args() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray(["--list", LIST_NAMES[int(list)]])
	if not hard_variant.is_empty():
		out.append_array(PackedStringArray(["--hard", hard_variant]))
	if hands_in_empty_places:
		out.append("--hands")
	return out

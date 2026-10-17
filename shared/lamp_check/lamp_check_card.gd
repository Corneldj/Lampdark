class_name LampCheckCard
extends RefCounted
## RSC-06: the Lamp Check card's text (Gameplay §11.9, GDD §14.3): 'Morrow Main, first shift. Up 4
## of 5. Left Below: Ada Rowe, Lamp 114. Deepest: the Third Level. Below 1 h 42 min.' A revolver
## death brought home adds a line ('Dead: Wilfred Dodd, Lamp 207, brought home.') and counts in Up;
## a wipe reads 'Up none of 4.'. Miners are named by their period name and lamp number (MOD-01),
## never a Steam name or a lobby code, and listed by lamp number; the Level is DIR-04's name, never
## a ring. Below is the run's own time, 'N h M min', or 'M min' under the hour. The words are
## data/text/lamp_check.json.
##
## Facts (built on the server from LFT-11's outcome record): {up, crew, left_below: [{name, lamp}],
## dead: [{name, lamp}], deepest_ring, below_s}.

const PATH: String = "res://data/text/lamp_check.json"
const LEVELS: String = "res://data/text/levels.json"

static var _strings: Dictionary = {}


static func text(facts: Dictionary) -> String:
	var up: int = int(Variants.number(facts.get("up", 0)))
	var crew: int = int(Variants.number(facts.get("crew", 0)))
	var parts: PackedStringArray = PackedStringArray([word("card.heading")])
	if up <= 0:
		parts.append(word("card.up_none").format({"crew": crew}))
	else:
		parts.append(word("card.up").format({"up": up, "crew": crew}))
	var below: PackedStringArray = PackedStringArray()
	for raw: Variant in Variants.array(facts.get("left_below", [])):
		below.append(miner(Variants.dict(raw)))
	if not below.is_empty():
		parts.append(word("card.left_below").format({"miners": word("card.miners_joiner").join(below)}))
	parts.append(word("card.deepest").format({"level": level(int(Variants.number(facts.get("deepest_ring", 0))))}))
	parts.append(time_below(Variants.number(facts.get("below_s", 0.0))))
	var lines: PackedStringArray = PackedStringArray([" ".join(parts)])
	for raw: Variant in Variants.array(facts.get("dead", [])):
		lines.append(word("card.dead").format({"miner": miner(Variants.dict(raw))}))
	return "\n".join(lines)


## 'Ada Rowe, Lamp 114', or 'Lamp 114' for a miner with no name yet.
static func miner(m: Dictionary) -> String:
	var name: String = str(m.get("name", ""))
	var lamp: int = int(Variants.number(m.get("lamp", 0)))
	return word("card.miner_unnamed").format({"lamp": lamp}) if name.is_empty() else word("card.miner").format({"name": name, "lamp": lamp})


## 'Below 1 h 42 min.', or 'Below 42 min.' under the hour (whole minutes, rounded down).
static func time_below(seconds: float) -> String:
	var minutes: int = floori(maxf(0.0, seconds) / 60.0)
	if minutes >= 60:
		return word("card.below_hours").format({"h": minutes / 60, "m": minutes % 60})
	return word("card.below_minutes").format({"m": minutes})


## DIR-04's Level name for a ring (levels.json), never the ring.
static func level(ring: int) -> String:
	_load()
	return str(_strings.get("level.%d" % clampi(ring, 0, 4), ""))


## A word of the card or the screen by key ("" for an unknown one).
static func word(key: String) -> String:
	_load()
	return str(_strings.get(key, ""))


static func _load() -> void:
	if not _strings.is_empty():
		return
	for path: String in [PATH, LEVELS]:
		if FileAccess.file_exists(path):
			var doc: Dictionary = Variants.dict(JSON.parse_string(FileAccess.get_file_as_string(path)))
			_strings.merge(Variants.dict(doc.get("strings", {})))

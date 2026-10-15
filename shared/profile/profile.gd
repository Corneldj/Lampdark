class_name Profile
extends RefCounted
## MOD-01 (Gameplay §13.1, §13.2, §10.10, §13.5): a player's persistent profile, keyed by SteamID64.
## It holds a roster of three named miners (founded once, then changed only by the log), the
## preferred cap badge, and an append-only log of OutcomeEvents from which everything else is
## derived: who is on the roster and who is Below, who left and the three fresh names offered for
## each, the New Brigade count and the hard-variant unlocks. Copies (the local file, Steam Cloud
## through STM-05, the backend through STM-10) merge by union of the log; an outcome that leaves for
## good beats any other. It never keeps stats, items, currency or anything found below.
##
## Schema 2. Schema 1 (a flat miner list with one "name" and an "outcomes" list) migrates on load;
## fields this version does not know are kept, never dropped.

const SCHEMA_VERSION: int = 2
const KNOWN: Array[String] = ["schema_version", "steam_id", "seed", "founding", "events", "preferred_badge"]

var steam_id: int = 0
## The profile's own random stream (names, lamp numbers), never a run's.
var profile_seed: int = 0
var founding: Array[RosterMiner] = []
var events: Array[Dictionary] = []
## One of the six cap badges (VIS-06), -1 for none: MOD-03 applies it when free.
var preferred_badge: int = -1
## Fields a newer version wrote, kept as they were.
var extra: Dictionary = {}


## What the log comes to: the roster now, those who left, the offers, the count and the unlocks.
class State:
	extends RefCounted
	## The current roster, in order (Available or Below).
	var roster: Array[RosterMiner] = []
	var gone: Array[RosterMiner] = []
	## replaced miner id -> three fresh names [{given, surname, woman}], until one is hired.
	var offers: Dictionary = {}
	var new_brigade_runs: int = 0
	var unlocked_variants: bool = false

	func miner(miner_id: int) -> RosterMiner:
		for m: RosterMiner in roster:
			if m.id == miner_id:
				return m
		return null

	func new_brigade() -> bool:
		return new_brigade_runs < Tuning.i(&"modes.new_brigade_runs")


static func create(player_steam_id: int, stream_seed: int) -> Profile:
	var p: Profile = Profile.new()
	p.steam_id = player_steam_id
	p.profile_seed = stream_seed
	var names: Array[Dictionary] = NameDrawer.draw(stream_seed, 0, Tuning.i(&"modes.roster_size"), [] as Array[String])
	var numbers: Array[int] = []
	for i: int in names.size():
		var lamp: int = LampNumbers.draw(stream_seed, 0, i, numbers)
		numbers.append(lamp)
		p.founding.append(RosterMiner.make(i + 1, names[i], lamp))
	return p


## Adds events (a Lamp Check's outcomes, a run's start or end, a hire). An event already held is
## kept as the stronger of the two (OutcomeEvent.stronger), so applying it again changes nothing.
func add(new_events: Array[Dictionary]) -> void:
	var by_key: Dictionary = {}
	for e: Dictionary in events:
		by_key[OutcomeEvent.key(e)] = e
	for e: Dictionary in new_events:
		var k: String = OutcomeEvent.key(e)
		var held: Dictionary = by_key.get(k, {})
		by_key[k] = OutcomeEvent.stronger(held, e) if not held.is_empty() else e.duplicate()
	events.clear()
	for raw: Variant in by_key.values():
		events.append(Variants.dict(raw))
	OutcomeEvent.sort(events)


## Another copy's events merged in (union; the stronger of two versions of one event).
func merge(other: Profile) -> void:
	add(other.events)
	if preferred_badge < 0:
		preferred_badge = other.preferred_badge


## Replays the log from the founding roster.
func state() -> State:
	var s: State = State.new()
	for m: RosterMiner in founding:
		s.roster.append(RosterMiner.from_dict(m.to_dict()))
	var next_id: int = founding.size() + 1
	var counted: Dictionary = {}
	var sorted: Array[Dictionary] = events.duplicate()
	OutcomeEvent.sort(sorted)
	for e: Dictionary in sorted:
		var kind: int = int(Variants.number(e.get("kind", -1)))
		var run: String = str(e.get("run", ""))
		var miner: RosterMiner = s.miner(int(Variants.number(e.get("miner", 0))))
		match kind:
			OutcomeEvent.Kind.RUN_START:
				if miner != null and miner.available():
					miner.below_run = run
			OutcomeEvent.Kind.RUN_END:
				if int(Variants.number(e.get("how", -1))) == OutcomeEvent.End.VOIDED:
					for m: RosterMiner in s.roster:
						if m.below_run == run:
							m.below_run = ""
			OutcomeEvent.Kind.OUTCOME:
				if miner == null:
					continue
				counted[run] = true  # a run counts once, when it ends at Lamp Check with one of ours in it
				var what: int = int(Variants.number(e["outcome"]))
				if what == OutcomeEvent.Outcome.ESCAPED:
					miner.below_run = ""
					s.unlocked_variants = true
				elif OutcomeEvent.LEAVES.has(what):
					miner.left = OutcomeEvent.OUTCOME_NAMES[what]
					miner.below_run = ""
					s.roster.erase(miner)
					s.gone.append(miner)
					s.offers[miner.id] = NameDrawer.draw(profile_seed, miner.id, Tuning.i(&"modes.replacement_offers"), _taken(s))
			OutcomeEvent.Kind.HIRE:
				var replaced: int = int(Variants.number(e.get("miner", 0)))
				var offered: Array = Variants.array(s.offers.get(replaced, []))
				var choice: int = int(Variants.number(e.get("choice", -1)))
				if choice < 0 or choice >= offered.size() or s.roster.size() >= Tuning.i(&"modes.roster_size"):
					continue
				var numbers: Array[int] = []
				for m: RosterMiner in s.roster:
					numbers.append(m.lamp_number)
				var hired: RosterMiner = RosterMiner.make(next_id, Variants.dict(offered[choice]), LampNumbers.draw(profile_seed, replaced, 0, numbers))
				next_id += 1
				s.roster.append(hired)
				s.offers.erase(replaced)
	s.new_brigade_runs = counted.size()
	return s


## RSC-06's miner_outcome at Lamp Check, for one of this player's miners.
func apply_outcome(run_uuid: String, miner_id: int, what: OutcomeEvent.Outcome, at: int) -> void:
	add([OutcomeEvent.outcome(run_uuid, miner_id, what, at)] as Array[Dictionary])


## The player sends a miner below (MOD-03): refused for a miner who is not Available.
func send_below(run_uuid: String, miner_id: int, at: int) -> bool:
	var m: RosterMiner = state().miner(miner_id)
	if m == null or not m.available():
		return false
	add([OutcomeEvent.run_start(run_uuid, miner_id, at)] as Array[Dictionary])
	return true


## A run that ended without Lamp Check: VOIDED (public) gives its miners back unchanged; ABNORMAL
## (friends, Night Shift) leaves them Below until it resumes and ends.
func end_without_lamp_check(run_uuid: String, how: OutcomeEvent.End, at: int) -> void:
	add([OutcomeEvent.run_end(run_uuid, how, at)] as Array[Dictionary])


## The replacement: one of the three names offered for a miner who left.
func hire(replaced_id: int, choice: int, at: int) -> bool:
	if not state().offers.has(replaced_id):
		return false
	add([OutcomeEvent.hire(replaced_id, choice, at)] as Array[Dictionary])
	return true


func to_dict() -> Dictionary:
	var out: Dictionary = extra.duplicate(true)
	var miners: Array = []
	for m: RosterMiner in founding:
		miners.append(m.to_dict())
	out["schema_version"] = SCHEMA_VERSION
	out["steam_id"] = str(steam_id)
	out["seed"] = str(profile_seed)
	out["founding"] = miners
	out["events"] = events.duplicate(true)
	out["preferred_badge"] = preferred_badge
	return out


## Any earlier schema migrates first; unknown fields are kept in `extra`.
static func from_dict(raw: Dictionary) -> Profile:
	var d: Dictionary = migrate(raw)
	var p: Profile = Profile.new()
	p.steam_id = Variants.whole(d.get("steam_id", 0))
	p.profile_seed = Variants.whole(d.get("seed", 0))
	for m: Variant in Variants.array(d.get("founding", [])):
		p.founding.append(RosterMiner.from_dict(Variants.dict(m)))
	var list: Array[Dictionary] = []
	for e: Variant in Variants.array(d.get("events", [])):
		list.append(_int_fields(Variants.dict(e)))
	p.add(list)
	p.preferred_badge = int(Variants.number(d.get("preferred_badge", -1)))
	for k: Variant in d.keys():
		if not KNOWN.has(str(k)):
			p.extra[k] = d[k]
	return p


## Schema 1 -> 2: "miners" [{id, name ("Given Surname"), lamp}] become founding miners with a voice,
## and "outcomes" [{run, miner, outcome (name)}] become OUTCOME events.
static func migrate(d: Dictionary) -> Dictionary:
	var v: int = int(Variants.number(d.get("schema_version", SCHEMA_VERSION)))
	if v >= SCHEMA_VERSION:
		return d
	var out: Dictionary = d.duplicate(true)
	if v == 1:
		var founding_list: Array = []
		for raw: Variant in Variants.array(d.get("miners", [])):
			var m: Dictionary = Variants.dict(raw)
			var parts: PackedStringArray = str(m.get("name", "")).split(" ", false, 1)
			var name: Dictionary = {"given": parts[0] if parts.size() > 0 else "", "surname": parts[1] if parts.size() > 1 else ""}
			for n: Dictionary in NameDrawer.period_names():
				if NameDrawer.full(n) == NameDrawer.full(name):
					name = n
			founding_list.append(RosterMiner.make(int(Variants.number(m.get("id", 0))), name, int(Variants.number(m.get("lamp", 0)))).to_dict())
		var list: Array = []
		for raw: Variant in Variants.array(d.get("outcomes", [])):
			var o: Dictionary = Variants.dict(raw)
			var what: int = OutcomeEvent.OUTCOME_NAMES.find(str(o.get("outcome", "")))
			if what >= 0:
				list.append(OutcomeEvent.outcome(str(o.get("run", "")), int(Variants.number(o.get("miner", 0))), what as OutcomeEvent.Outcome,
					int(Variants.number(o.get("at", 0)))))
		out.erase("miners")
		out.erase("outcomes")
		out["founding"] = founding_list
		out["events"] = list
		out["preferred_badge"] = -1
	out["schema_version"] = SCHEMA_VERSION
	return out


## JSON reads numbers as floats: the event's numbers back to ints, its run uuid a string.
static func _int_fields(e: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k: Variant in e.keys():
		var v: Variant = e[k]
		out[k] = int(Variants.number(v)) if (v is float or v is int) else v
	return out


func _taken(s: State) -> Array[String]:
	var out: Array[String] = []
	for m: RosterMiner in s.roster:
		out.append(m.full_name())
	for raw: Variant in s.offers.values():
		for n: Variant in Variants.array(raw):
			out.append(NameDrawer.full(Variants.dict(n)))
	return out

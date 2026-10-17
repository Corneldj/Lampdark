class_name LampCheckFacts
extends RefCounted
## RSC-06: what Lamp Check shows, built from LFT-11's outcome record (Gameplay §11.9, GDD §14.3).
## - Hooks: one per counted miner (every player's miner, a Hand-held one for a dropped player
##   included; never a Hired Hand's own place), by lamp number (Proposed). A hook's check hangs for
##   whoever came up, the dead brought home included; it is empty for the Left Below, and on a wipe
##   for everyone.
## - The remark: the cause of the run's most recent fall or death (Proposed), none if nobody fell.
## - The card: LampCheckCard's text from the same facts.
## What a client is sent of it names only lamp numbers, period names and the cause: never an
## entity id, a Steam name or a lobby code. Server-only (the record is).


## {hooks: [{lamp, hangs}], card_facts, card (text), remark (FallCause name, "" for none), wipe}.
static func build(record: Dictionary, last_cause: int) -> Dictionary:
	var miners: Array[Dictionary] = []
	for raw: Variant in Variants.array(record.get("miners", [])):
		miners.append(Variants.dict(raw))
	miners.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var la: int = int(Variants.number(a.get("lamp_number", 0)))
		var lb: int = int(Variants.number(b.get("lamp_number", 0)))
		return la < lb if la != lb else int(Variants.number(a.get("miner_id", 0))) < int(Variants.number(b.get("miner_id", 0))))
	var hooks: Array = []
	var left_below: Array = []
	var dead: Array = []
	for m: Dictionary in miners:
		var up: bool = str(m.get("outcome", "")) == "escaped"
		var who: Dictionary = {"name": str(m.get("name", "")), "lamp": int(Variants.number(m.get("lamp_number", 0)))}
		hooks.append({"lamp": who["lamp"], "hangs": up})
		if not up:
			left_below.append(who)
		elif Variants.flag(m.get("dead", false)):
			dead.append(who)
	var facts: Dictionary = {"up": int(Variants.number(record.get("up_count", 0))), "crew": int(Variants.number(record.get("crew_size", 0))),
		"left_below": left_below, "dead": dead, "deepest_ring": int(Variants.number(record.get("deepest_ring", 0))),
		"below_s": Variants.number(record.get("time_below_s", 0.0))}
	return {"hooks": hooks, "card_facts": facts, "card": LampCheckCard.text(facts),
		"remark": FallCause.name_of(last_cause) if last_cause >= 0 else "", "wipe": Variants.flag(record.get("wipe", false))}


## A miner's outcome as MOD-01's roster takes it: escaped, dead (brought home) or left_below.
static func outcome_name(m: Dictionary) -> String:
	if str(m.get("outcome", "")) != "escaped":
		return "left_below"
	return "dead" if Variants.flag(m.get("dead", false)) else "escaped"

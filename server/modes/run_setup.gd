class_name RunSetup
extends RefCounted
## MOD-03 (Gameplay §13.5, §13.6, §3.3, §8.4, §10.10, §11.11, §12.6; GDD §13.8, §14.1, §15.9, §15.10):
## a run created from its lobby's options, on the server. In order (Proposed):
## 1. the options validated (refusal): the modes table's lists and player counts, hard variants
##    only among friends, one at most, and only one the host has unlocked;
## 2. each joiner seated as they say Hello (CrewSeating): the first of their roster miners whose lamp
##    number no seated miner holds, and its badge (the player's own when free, else the next free
##    one; Hired Hands take only badges no living player holds);
## 3. the seed: 64 bits from the OS CSPRNG (new_seed), every other stream derived from it;
## 4. at the start (a hosted run's Go down; a dev or fleet server's launch), the staging level from
##    the crew's New Brigade runs (DIR-06 applies what it stages), before the list, since a staged
##    run 1 plays the Short list and runs 1-3 the defaults;
## 5. the list (LFT-03: solo forbids the drum gear; Full only while lift.full_list_enabled);
## 6. the draw (HAZ-07's, a stub until then: the defaults and no condition);
## 7. the plan (GEN-08's RunPlan.fix in server_main's _begin_run, from the header's inputs: the list,
##    the solo rule, the draw, the staging and the hard variant), well before 0:20 of the cold open;
## 8. the header sealed, with the rule flags: public (quick-play), saved (friends and Night Shift),
##    solo_rules (Night Shift, or a friends lobby of one human at start) and hands_fill (public, or
##    friends with Hands on). Nothing in it changes after (a joiner, a knock-off, a resume).
## Lobby metadata carries the options alone; the seed, the draw, the staging and the plan stay here.
## Server-only.

## The cap badges (GDD §14.1, VIS-06's MinerCues): clear, green, violet, grey, rose and brown.
const BADGES: int = 6


## A fresh run's seed: 64 bits from the OS's cryptographic source, so no two runs share a mine and
## nobody sees, shares or chooses one.
static func new_seed() -> int:
	return Crypto.new().generate_random_bytes(8).decode_s64(0)


## The places a run of `mode` holds (Gameplay §13.5, A.10): friends' lobbies 1 to
## modes.friends_lobby_max, public quick-play modes.public_places, Night Shift one.
static func places(mode: ServerConfig.Mode) -> int:
	match mode:
		ServerConfig.Mode.PUBLIC:
			return roundi(Tuning.f(&"modes.public_places"))
		ServerConfig.Mode.NIGHTSHIFT:
			return 1
	return Tuning.i(&"modes.friends_lobby_max")


## The options a server was launched with (ServerConfig's --list, --hard and --hands), or its mode's
## defaults.
static func options_of(config: ServerConfig) -> RunOptions:
	var o: RunOptions = RunOptions.defaults(config.mode)
	if not config.list_name.is_empty():
		o.list = RunOptions.list_from(config.list_name)
	o.hard_variant = config.hard_variant
	o.hands_in_empty_places = o.hands_in_empty_places or config.hands
	return o


## The hard variants a host has unlocked: every one after their first escape (MOD-01's unlock, as the
## host's client reads it from its own profile), else none.
static func unlocked_variants(variants_unlocked: bool) -> Array[String]:
	var out: Array[String] = []
	if variants_unlocked:
		out.assign(RunOptions.HARD_VARIANTS)
	return out


## Why these options cannot make a run, or "" (the plain words a host is shown).
## `unlocked`: the hard variants the host has unlocked; `humans`: the lobby's humans at the start
## (-1 when not known yet: the places alone hold the count, ServerNet's slots).
static func refusal(options: RunOptions, unlocked: Array[String] = [], humans: int = -1) -> String:
	var variants: PackedStringArray = options.hard_variants()
	if variants.size() > roundi(Tuning.f(&"modes.hard_variants_max")):
		return "A run takes one hard variant at most."
	for v: String in variants:
		if not RunOptions.HARD_VARIANTS.has(v):
			return "There is no hard variant called '%s'." % v
	match options.mode:
		ServerConfig.Mode.PUBLIC:
			if options.list != RunOptions.List.SHORT:
				return "Public quick-play plays the Short list."
			if not variants.is_empty():
				return "Hard variants are for friends' lobbies."
			if humans > places(ServerConfig.Mode.PUBLIC):
				return "A public run has %d places." % places(ServerConfig.Mode.PUBLIC)
		ServerConfig.Mode.NIGHTSHIFT:
			if options.list == RunOptions.List.FULL:
				return "Night Shift plays the Short or the Standard list."
			if not variants.is_empty():
				return "Hard variants are for friends' lobbies."
			if humans > 1:
				return "Night Shift is played alone."
		_:
			if humans >= 0 and (humans < 1 or humans > Tuning.i(&"modes.friends_lobby_max")):
				return "A friends' lobby holds 1 to %d players." % Tuning.i(&"modes.friends_lobby_max")
			if options.list == RunOptions.List.FULL and not Tuning.b(&"lift.full_list_enabled"):
				return "The Full list is not open yet."
			for v: String in variants:
				if not unlocked.has(v):
					return "The host has not unlocked that hard variant yet."
	return ""


## The run's rule flags from its options and the humans seated at its start.
static func rule_flags(options: RunOptions, humans_at_start: int) -> Dictionary:
	var public: bool = options.mode == ServerConfig.Mode.PUBLIC
	var nightshift: bool = options.mode == ServerConfig.Mode.NIGHTSHIFT
	return {
		"public": public,
		"saved": not public,
		"solo_rules": nightshift or (options.mode == ServerConfig.Mode.FRIENDS and humans_at_start == 1),
		"hands_fill": public or (options.mode == ServerConfig.Mode.FRIENDS and options.hands_in_empty_places),
	}


## Gameplay §10.10's staging level from the crew's New Brigade runs (MOD-01's count, -1 unknown):
## when every player is New Brigade, the least-experienced player's run (1 to modes.new_brigade_runs);
## 0 (the full game) when anyone is an Old Hand or unknown, or nobody is seated.
static func staging_level(brigade_runs: Array[int]) -> int:
	if brigade_runs.is_empty():
		return 0
	var least: int = brigade_runs[0]
	for r: int in brigade_runs:
		if r < 0 or r >= Tuning.i(&"modes.new_brigade_runs"):
			return 0
		least = mini(least, r)
	return least + 1


## The header's staging: the level as text ("1" to "5"), "" unstaged. DIR-06 applies what each
## level stages; until it lands only the list (Short in run 1) and the draw (defaults until run 4)
## follow it, with a warning.
static func staging(brigade_runs: Array[int]) -> String:
	var level: int = staging_level(brigade_runs)
	if level == 0:
		return ""
	Log.warn("run setup: staged run %d; DIR-06's staging content is not built yet, so only the list and the draw follow it" % level)
	return str(level)


## HAZ-07's draw of variants and a condition (a stub until it lands: the defaults, no condition).
static func draw(_run_seed: int, _staging: String) -> PackedStringArray:
	Log.warn("run setup: HAZ-07's draw is not built yet; the run plays the defaults with no condition")
	return PackedStringArray()


## Steps 4 to 8 at the start, from the options and the crew seated now (`humans`, and their New
## Brigade runs): the staging, the list, the draw and the rule flags, sealed into the header; the
## plan follows (RunPlan.fix reads them). "" when made, else the refusal (nothing changed). A later
## joiner never changes any of it. `humans` -1: not known at the start (a dev or fleet server whose
## crew joins after it): the places hold the count, and the run is not staged.
static func create(run: RunState, options: RunOptions, humans: int = -1, brigade_runs: Array[int] = [],
		host_unlocked: Array[String] = []) -> String:
	var why: String = refusal(options, host_unlocked, humans)
	if not why.is_empty():
		return why
	var h: RunState.Header = run.header
	h.options = options
	h.humans_at_start = maxi(humans, 0)
	h.staging = staging(brigade_runs if humans > 0 else ([] as Array[int]))
	h.draw = draw(h.run_seed, h.staging)
	h.rule_flags = rule_flags(options, h.humans_at_start)
	if run.repair != null:
		var kind: RepairList.Kind = int(list_kind(options, h.staging)) as RepairList.Kind
		var list: RepairList = RepairList.for_run(h.run_seed, kind, Variants.flag(h.rule_flags["solo_rules"]))
		if list == null:
			return "The %s list cannot be drawn." % RunOptions.LIST_NAMES[int(kind)]
		run.repair.set_list(list)
	return ""


## The list a run plays: the options' own, but a staged run 1's is Short (§10.10).
static func list_kind(options: RunOptions, staged: String) -> RunOptions.List:
	return RunOptions.List.SHORT if staged == "1" else options.list


## A badge for a seat: the player's own when no living miner wears it, else the next free one
## (counting up and round); -1 with none free. `worn`: the badges living miners wear.
static func badge_for(preferred: int, worn: Array[int]) -> int:
	for k: int in BADGES:
		var b: int = posmod(preferred + k, BADGES)
		if not worn.has(b):
			return b
	return -1


## Badges for Hired Hands: only those no living player wears, in order.
static func badges_for_hands(count: int, worn: Array[int]) -> Array[int]:
	var out: Array[int] = []
	for b: int in BADGES:
		if out.size() >= count:
			break
		if not worn.has(b):
			out.append(b)
	return out

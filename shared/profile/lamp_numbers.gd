class_name LampNumbers
extends RefCounted
## MOD-01 (Gameplay §13.2): a lamp number is three digits for life (modes.lamp_number_min to _max, so
## every one speaks as three: 'Lamp one-one-four'), distinct within a player's roster. No lobby seats
## two miners with one number: a clashing joiner sends another of their three (MOD-03 calls seatable).


## One number for `purpose` (0: the first roster's, in order; else the replaced miner's id) that none
## of `taken` holds, from the profile's own stream.
static func draw(profile_seed: int, purpose: int, nth: int, taken: Array[int]) -> int:
	var lo: int = Tuning.i(&"modes.lamp_number_min")
	var hi: int = Tuning.i(&"modes.lamp_number_max")
	var rng: LbRng = LbRng.from_seed(LbHash.sub_seed(profile_seed, HashDomain.PROFILE_LAMP_NUMBERS, PackedInt64Array([purpose, nth]), 0))
	for _i: int in 1000:
		var n: int = rng.range(lo, hi)
		if not taken.has(n):
			return n
	for n: int in range(lo, hi + 1):
		if not taken.has(n):
			return n
	return lo


## The joiner's miners that may sit beside `seated` numbers: Available, with an unclaimed number.
## Empty means the join is refused with a plain message (the odds are below one in a million).
static func seatable(seated: Array[int], roster: Array[RosterMiner]) -> Array[RosterMiner]:
	var out: Array[RosterMiner] = []
	for m: RosterMiner in roster:
		if m.available() and not seated.has(m.lamp_number):
			out.append(m)
	return out

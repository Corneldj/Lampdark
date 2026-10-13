class_name FallCause
extends RefCounted
## RSC-01: why a miner fell (Gameplay §11.2). Wire and log values: append only. SHOT_DEAD is
## RSC-05's (a friendly hit that kills).

enum Cause { MOTH_SMOTHER = 0, DRAG = 1, PIN = 2, BLAST = 3, BLACKDAMP = 4, ROOF_FALL = 5, HATCH = 6, FRIENDLY_HIT = 7, SHOT_DEAD = 8 }

## How SND-15 sounds the fall: a full 1.5 s scream, a drag victim's muffled whisper, or none
## (a revolver hit, a Hired Hand).
enum Scream { FULL = 0, MUFFLED_WHISPER = 1, NONE = 2 }


static func name_of(cause: int) -> String:
	return str(Cause.find_key(cause)).to_lower()


## The cause behind MNR-03's own cause strings, for falls that reach Unconscious by another route
## (a pin running out through end_grab, a drag through RSC-03's holds); -1 if unknown.
static func from_state_cause(text: String) -> int:
	if text.begins_with("pin"):
		return Cause.PIN
	if text.begins_with("drag"):
		return Cause.DRAG
	for raw: Variant in Cause.keys():
		var key: String = str(raw).to_lower()
		if text == key or text.begins_with(key + ":"):
			return int(Variants.number(Cause[raw]))
	return -1

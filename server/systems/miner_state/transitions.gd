class_name MinerTransitions
extends RefCounted
## MNR-03's transition table as data (Gameplay §11.1, §11.3): for each hook, the life states it
## may act on and the state it leads to. Hooks with richer rules (a pin over a trap, a drag over
## a body) are handled in MinerStateSystem, guarded by this table.

enum Life { UPRIGHT = 0, CAUGHT = 1, GRABBED = 2, UNCONSCIOUS = 3, DEAD = 4 }
enum Outcome { NONE = 0, ESCAPED = 1, LEFT_BELOW = 2 }

## Priority of same-tick requests by the state they lead to (Proposed): Dead first.
const PRIORITY: Dictionary = {Life.DEAD: 0, Life.UNCONSCIOUS: 1, Life.GRABBED: 2, Life.CAUGHT: 3, Life.UPRIGHT: 4}

## hook -> {from life state: to life state}. A missing pair is illegal. -1 keeps the state.
const TABLE: Dictionary = {
	"enter_caught": {Life.UPRIGHT: Life.CAUGHT, Life.UNCONSCIOUS: -1},
	"release_caught": {Life.CAUGHT: Life.UPRIGHT, Life.UNCONSCIOUS: -1},
	"enter_grabbed": {Life.UPRIGHT: Life.GRABBED, Life.CAUGHT: Life.GRABBED, Life.UNCONSCIOUS: -1},
	"end_grab": {Life.GRABBED: Life.UPRIGHT, Life.UNCONSCIOUS: -1},
	"fall_unconscious": {Life.UPRIGHT: Life.UNCONSCIOUS, Life.CAUGHT: Life.UNCONSCIOUS, Life.GRABBED: Life.UNCONSCIOUS},
	"kill": {Life.UPRIGHT: Life.DEAD, Life.CAUGHT: Life.DEAD, Life.GRABBED: Life.DEAD, Life.UNCONSCIOUS: Life.DEAD},
	"revive": {Life.UNCONSCIOUS: Life.UPRIGHT},
	"make_hurt": {Life.UPRIGHT: -1, Life.CAUGHT: -1, Life.GRABBED: -1, Life.UNCONSCIOUS: -1},
	"add_mark": {Life.UPRIGHT: -1, Life.CAUGHT: -1, Life.GRABBED: -1, Life.UNCONSCIOUS: -1},
	"cure_mark": {Life.UPRIGHT: -1, Life.CAUGHT: -1, Life.GRABBED: -1, Life.UNCONSCIOUS: -1},
	"set_rock_touched": {Life.UPRIGHT: -1, Life.CAUGHT: -1, Life.GRABBED: -1, Life.UNCONSCIOUS: -1},
	"set_outcome": {Life.UPRIGHT: -1, Life.CAUGHT: -1, Life.GRABBED: -1, Life.UNCONSCIOUS: -1, Life.DEAD: -1},
}

## Capabilities by life state (the §4.2 table; Grabbed may turn, Proposed).
## interact: "yes", "reach" (within reach), "self_rescue" (RSC-09) or "no".
const CAPABILITIES: Dictionary = {
	Life.UPRIGHT: {"move": true, "turn": true, "voice": true, "lamp": true, "belt": true, "interact": "yes", "signals": true},
	Life.CAUGHT: {"move": false, "turn": true, "voice": true, "lamp": true, "belt": true, "interact": "reach", "signals": true},
	Life.GRABBED: {"move": false, "turn": true, "voice": true, "lamp": false, "belt": false, "interact": "self_rescue", "signals": false},
	Life.UNCONSCIOUS: {"move": false, "turn": false, "voice": false, "lamp": false, "belt": false, "interact": "no", "signals": false},
	Life.DEAD: {"move": false, "turn": false, "voice": false, "lamp": false, "belt": false, "interact": "no", "signals": false},
}


static func allowed(hook: String, from: Life) -> bool:
	return Variants.dict(TABLE.get(hook, {})).has(from)


static func target(hook: String, from: Life) -> int:
	return int(Variants.number(Variants.dict(TABLE.get(hook, {})).get(from, -2)))

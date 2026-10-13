class_name CaughtHold
extends RefCounted
## RSC-03: a miner held by a trap until freed, or torn out by a Stythe's drag. An unconscious
## miner stays held. Freeing progress and lone struggles are HAZ-01 to HAZ-03's.

enum Kind { MAN_TRAP = 0, TIMBER_PIN = 1, STAPLE_PIT = 2 }
enum Outcome { NONE = 0, FREED = 1, TORN_OUT = 2 }

const SOURCES: Array[StringName] = [&"man_trap", &"timber_pin", &"staple_pit"]

var trap_id: int = 0
var kind: Kind = Kind.MAN_TRAP
var victim: int = 0
var outcome: Outcome = Outcome.NONE
var began_tick: int = 0


func source() -> StringName:
	return SOURCES[kind]

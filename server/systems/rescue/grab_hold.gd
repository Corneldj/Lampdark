class_name GrabHold
extends RefCounted
## RSC-03: one grab, from the strike or grab that began it to its end. A Tapper's ReStrike is the
## same grab: its id survives and its elapsed count resumes, never restarting. The count runs
## only while ACTIVE; a drag past its conscious limit becomes a BODY, with no timer.

enum Kind { STYTHE_DRAG = 0, TAPPER_PIN = 1 }
enum State { ACTIVE = 0, SUSPENDED = 1, BODY = 2, ENDED = 3 }
enum Outcome { NONE = 0, BROKEN = 1, TIMED_OUT = 2, RETREAT = 3, SELF_RESCUED = 4, ABANDONED = 5 }

var id: int = 0
var kind: Kind = Kind.TAPPER_PIN
var creature: int = 0
var victim: int = 0
var limit_ticks: int = 0
var elapsed: int = 0
var state: State = State.ACTIVE
var outcome: Outcome = Outcome.NONE
var began_tick: int = 0
## The self-rescue's one attempt is spent (solo and lone human only).
var rescue_spent: bool = false


## MNR-03's name for the kind.
func mnr_kind() -> StringName:
	return &"drag" if kind == Kind.STYTHE_DRAG else &"pin"


func is_live() -> bool:
	return state != State.ENDED

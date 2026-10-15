class_name TimedAction
extends RefCounted
## MNR-04's generic timed action (Gameplay §4.3, GDD §14.5, §15.2): it completes only if held to
## its end, and its effect applies only then, exactly once. It is cancelled, with nothing spent,
## when its input is released, a constraint breaks (standing still, crouch pace, touch range, a
## partner who must hold too), the miner's capabilities change, the target becomes invalid, or
## inputs stop (NET-03's input_starved). Hold-or-toggle (MNR-15) only latches the input bit on
## the client, so toggling never shortens it. InventorySystem runs one per miner at a time.
## Server-only.

signal completed(action: TimedAction)
signal cancelled(action: TimedAction, reason: StringName)

const RELEASED: StringName = &"released"
const MOVED: StringName = &"moved"
const STATE: StringName = &"state"
const TARGET: StringName = &"target"
const RANGE: StringName = &"range"
const STARVED: StringName = &"starved"
const PARTNER: StringName = &"partner"

var actor: int = 0
var verb: StringName = &""
var ticks_needed: int = 1
var ticks_done: int = 0
var started_tick: int = 0
## The InputRecord.HOLD_* bit that must stay held; 0 for none (MNR-10's chalk runs on by itself
## once started, cancelled only by its constraints).
var hold_bit: int = InputRecord.HOLD_INTERACT
## Which capability (MinerTransitions.CAPABILITIES) it needs: &"interact" or &"belt".
var capability: StringName = &"interact"
var needs_still: bool = false
var needs_crouch: bool = false
## A second miner who must hold the same bit throughout (sharing oil, passing a flame).
var partner: int = 0
## MNR-05's both-hold: further participants, each holding the bit and within touch range.
var partners: Array[int] = []
## Who let go, when a partner's release (or leaving touch range) cancelled it.
var let_go: int = 0
## The target to stay within `reach` of (+ items.range_tolerance): an entity, else a point.
var target_entity: int = 0
var target_point: Vector2 = Vector2.ZERO
var reach: float = -1.0
## () -> bool: the target is still valid. () -> void: the effect, applied once on completion.
var valid: Callable = Callable()
var effect: Callable = Callable()
## Called once when InventorySystem accepts it (MNR-13's lift hooks the lamp then).
var on_start: Callable = Callable()
## The life state it started in; any change is a capability change.
var life_at_start: int = -1
var done: bool = false


## An action of `seconds` for `actor`, held on `hold_bit`.
static func make(of_actor: int, of_verb: StringName, seconds: float, bit: int) -> TimedAction:
	var a: TimedAction = TimedAction.new()
	a.actor = of_actor
	a.verb = of_verb
	a.hold_bit = bit
	a.ticks_needed = maxi(1, roundi(seconds * Tuning.f(&"net.tick_hz")))
	return a


func finish() -> void:
	done = true
	if effect.is_valid():
		effect.call()
	completed.emit(self)


func cancel(reason: StringName) -> void:
	done = true
	cancelled.emit(self, reason)

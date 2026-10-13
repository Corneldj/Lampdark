class_name KitUse
extends RefCounted
## RSC-02 (Gameplay §11.5): one use of a healing kit, as MNR-04's timed action. It takes
## rescue.kit_use_s (100 ticks) standing still (0.3 tiles/s or slower) holding interact (or Use, on
## yourself from the belt); releasing, moving, being grabbed or falling, the target leaving touch
## range or leaving its table, or the inputs stopping cancel it with the kit unspent. On completion,
## in one tick, it either cures one sickness (HAZ-06's cure) or revives an unconscious miner lying
## on a medbay table, never both, and only then is one kit spent (the lowest belt slot holding one).

enum Mode { CURE = 0, REVIVE = 1 }


## The lowest belt slot holding a healing kit, or -1.
static func kit_slot(run: RunState, user: int) -> int:
	if run.inventory == null:
		return -1
	var h: HandsAndBelt = run.inventory.hands_of(user)
	for i: int in h.slots.size():
		var item: Item = h.slots[i]
		if item != null and item.kind == ItemKinds.Kind.HEALING_KIT:
			return i
	return -1


## The timed action; `revival` applies the outcome. `bit` is HOLD_INTERACT from the ring, HOLD_USE
## for the belt's use on yourself.
static func make(run: RunState, revival: Revival, user: int, target: int, mode: Mode, bit: int = InputRecord.HOLD_INTERACT) -> TimedAction:
	var a: TimedAction = TimedAction.make(user, &"kit_cure" if mode == Mode.CURE else &"kit_revive", Tuning.f(&"rescue.kit_use_s"), bit)
	a.needs_still = true
	if target != user:
		a.target_entity = target
		a.reach = Tuning.f(&"vision.touch_range_tiles")
	a.valid = func() -> bool:
		if kit_slot(run, user) < 0 or not revival.may_use(run, user):
			return false
		return revival.may_revive(run, user, target) if mode == Mode.REVIVE else revival.may_cure(run, user, target)
	a.effect = func() -> void:
		if mode == Mode.REVIVE:
			revival.complete_revive(run, user, target)
		else:
			revival.complete_cure(run, user, target)
	return a

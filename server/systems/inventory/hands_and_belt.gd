class_name HandsAndBelt
extends RefCounted
## MNR-04: one miner's lamp hand, free hand, belt slots and the three things that need no slot
## (Gameplay §4.3). Pure bookkeeping, with no world access: InventorySystem moves items between
## this and the floor. The lamp check, chalk and the Pocket Book are never Items, so nothing can
## drop, hand over or take them. Server-only; the owner's client gets InventoryWire's encoding.
## Hands (MOD-08) and Bess's saddle (MOD-07) can reuse it.

var owner: int = 0
var lamp_hand: Item = null
## The lamp hangs on the belt hook during a two-handed action (radius 2.5, oil x0.5: MNR-06).
var hooked: bool = false
## What fills both hands during a two-handed action, as NET-04's held bits show it (MNR-13's body:
## ItemKinds.LOAD_BODY), 0 for none.
var load_kind: int = 0
var free_hand: Item = null
var slots: Array[Item] = []
var selected: int = 0
## Two-handed actions in progress (a carry, a tub, freeing a trapped teammate).
var two_handed: bool = false
## No slot (§4.3): the brass lamp check's number, chalk and the Pocket Book with its found notes.
var lamp_check: int = 0
var chalk: bool = true
var pocket_book: bool = true
var notes: Array[Item] = []


static func create(entity: int, check_number: int) -> HandsAndBelt:
	var h: HandsAndBelt = HandsAndBelt.new()
	h.owner = entity
	h.lamp_check = check_number
	for _i: int in Tuning.i(&"items.belt_slots"):
		h.slots.append(null)
	return h


## Stores an item by the §4.3 rules: a lamp to an empty lamp hand, a can to an empty free hand,
## a note into the Pocket Book; anything else onto a matching partial stack (same kind and same
## state: a half-burnt candle keeps its own slot), then an empty slot. A lamp with its hand full
## falls back to a slot. MNR-09: a lit candle goes to an empty lamp hand like a lamp; a burning
## flare only to an empty free hand, never the belt. Returns the count that did not fit (0: all
## stored; the caller keeps any remainder as the same Item with the count reduced).
func store(item: Item) -> int:
	if burning_flare(item):
		if free_hand != null:
			return item.count
		free_hand = item
		return 0
	if lit_candle(item) and lamp_hand == null:
		lamp_hand = item
		return 0
	match ItemKinds.hand_class(item.kind):
		ItemKinds.HandClass.BOOK:
			notes.append(item)
			return 0
		ItemKinds.HandClass.FREE_ONLY:
			if free_hand != null:
				return item.count
			free_hand = item
			return 0
		ItemKinds.HandClass.LAMP:
			if lamp_hand == null:
				lamp_hand = item
				return 0
	var cap: int = ItemKinds.stack_size(item.kind)
	for s: Item in slots:
		if s != null and stacks_with(s, item) and s.count < cap:
			var moved: int = mini(cap - s.count, item.count)
			s.count += moved
			item.count -= moved
			if item.count == 0:
				return 0
	# A stack never exceeds its cap anywhere, so what is left always fits one empty slot.
	for i: int in slots.size():
		if slots[i] == null and item.count <= cap:
			slots[i] = item
			return 0
	return item.count


## Whether `item` would fit whole without a swap.
func fits(item: Item) -> bool:
	if burning_flare(item):
		return free_hand == null
	if lit_candle(item) and lamp_hand == null:
		return true
	match ItemKinds.hand_class(item.kind):
		ItemKinds.HandClass.LOAD:
			return false  # MNR-14: a load is carried or pushed, never held
		ItemKinds.HandClass.BOOK:
			return true
		ItemKinds.HandClass.FREE_ONLY:
			return free_hand == null
		ItemKinds.HandClass.LAMP:
			if lamp_hand == null:
				return true
	var cap: int = ItemKinds.stack_size(item.kind)
	var room: int = 0
	for s: Item in slots:
		if s == null:
			room += cap
		elif stacks_with(s, item):
			room += cap - s.count
	return room >= item.count


static func stacks_with(a: Item, b: Item) -> bool:
	return a.kind == b.kind and a.state == b.state


static func lit_candle(item: Item) -> bool:
	return item != null and item.kind == ItemKinds.Kind.CANDLE and Variants.flag(item.state.get("lit", false))


static func burning_flare(item: Item) -> bool:
	return item != null and item.kind == ItemKinds.Kind.FLARE and Variants.flag(item.state.get("lit", false))


## Takes a slot's whole contents out (null if empty).
func take_slot(slot: int) -> Item:
	if slot < 0 or slot >= slots.size():
		return null
	var it: Item = slots[slot]
	slots[slot] = null
	return it


func count_of(kind: int) -> int:
	var n: int = 0
	for it: Item in held_items():
		if it.kind == kind:
			n += it.count
	return n


## Every Item this miner holds: hands, slots and notes (never the no-slot things).
func held_items() -> Array[Item]:
	var out: Array[Item] = []
	if lamp_hand != null:
		out.append(lamp_hand)
	if free_hand != null:
		out.append(free_hand)
	for s: Item in slots:
		if s != null:
			out.append(s)
	out.append_array(notes)
	return out


## Removes `n` of a kind, from the highest-numbered slot's stack first; all or nothing. The hands
## count too (a can in the free hand, a candle in the lamp hand).
func consume(kind: int, n: int) -> bool:
	if n <= 0 or count_of(kind) < n:
		return false
	var left: int = n
	for i: int in range(slots.size() - 1, -1, -1):
		var s: Item = slots[i]
		if s == null or s.kind != kind or left == 0:
			continue
		var used: int = mini(left, s.count)
		s.count -= used
		left -= used
		if s.count == 0:
			slots[i] = null
	if left > 0 and free_hand != null and free_hand.kind == kind:
		var used: int = mini(left, free_hand.count)
		free_hand.count -= used
		left -= used
		if free_hand.count == 0:
			free_hand = null
	if left > 0 and lamp_hand != null and lamp_hand.kind == kind:
		lamp_hand.count -= left
		if lamp_hand.count == 0:
			lamp_hand = null
	return true


## The free hand's holder blocks this action (§4.7): the drawn revolver, a can or a lit flare
## block everything but feeling, levers and phones. Both hands busy block every free-hand action.
func free_hand_blocked(action: StringName) -> bool:
	if two_handed:
		return true
	if free_hand == null:
		return false
	if ItemKinds.FREE_HAND_BLOCKERS.has(free_hand.kind):
		return not ItemKinds.BLOCKER_EXCEPTIONS.has(action)
	return true

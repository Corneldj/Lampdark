class_name Item
extends RefCounted
## MNR-04: one item, or one stack of a kind, wherever it is: on the floor (ItemWorld), in a hand,
## in a belt slot or in the Pocket Book. `uid` is unique for the run and never reused, so no item
## can be duplicated or lost unseen; a stack keeps the uid of its first item. `state` is the owning
## ticket's (a lamp's oil and notches, a candle's burn, a box's rounds). Server-only.

var uid: int = 0
var kind: ItemKinds.Kind = ItemKinds.Kind.NONE
var count: int = 1
var state: Dictionary = {}


static func make(item_uid: int, item_kind: ItemKinds.Kind, item_count: int = 1, item_state: Dictionary = {}) -> Item:
	var it: Item = Item.new()
	it.uid = item_uid
	it.kind = item_kind
	it.count = item_count
	it.state = item_state.duplicate(true)
	return it

extends GutTest
## MNR-04: stacks cap at candles 3, stones 3, fuses 3, rope clamps 4 and rounds 12, everything
## else 1; a fourth candle takes a new slot; consume is all or nothing.


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_caps() -> void:
	var caps: Dictionary = {ItemKinds.Kind.CANDLE: 3, ItemKinds.Kind.STONE: 3, ItemKinds.Kind.FUSE: 3,
		ItemKinds.Kind.ROPE_CLAMP: 4, ItemKinds.Kind.ROUNDS: 12, ItemKinds.Kind.SPANNER: 1, ItemKinds.Kind.FLARE: 1,
		ItemKinds.Kind.HEALING_KIT: 1, ItemKinds.Kind.MAGNETO: 1}
	for raw: Variant in caps.keys():
		var kind: int = int(Variants.number(raw))
		assert_eq(ItemKinds.stack_size(kind), int(Variants.number(caps[raw])), str(ItemKinds.Kind.find_key(kind)))


func test_one_at_a_time_fills_then_spills() -> void:
	for kind: ItemKinds.Kind in [ItemKinds.Kind.CANDLE, ItemKinds.Kind.STONE, ItemKinds.Kind.FUSE, ItemKinds.Kind.ROPE_CLAMP, ItemKinds.Kind.ROUNDS]:
		var b: HandsAndBelt = HandsAndBelt.create(1, 1)
		var cap: int = ItemKinds.stack_size(kind)
		for i: int in cap + 1:
			assert_eq(b.store(Item.make(i + 1, kind)), 0)
		assert_eq(b.slots[0].count, cap, "%s: the first slot holds %d" % [ItemKinds.Kind.find_key(kind), cap])
		assert_eq(b.slots[1].count, 1, "one more takes a new slot")
		assert_null(b.slots[2])


func test_fourth_candle_takes_a_new_slot() -> void:
	var b: HandsAndBelt = HandsAndBelt.create(1, 1)
	b.store(Item.make(1, ItemKinds.Kind.CANDLE, 3))
	b.store(Item.make(2, ItemKinds.Kind.CANDLE))
	assert_eq(b.slots[0].count, 3)
	assert_eq(b.slots[1].kind, ItemKinds.Kind.CANDLE)
	assert_eq(b.slots[1].count, 1)


func test_partial_stacks_merge() -> void:
	var b: HandsAndBelt = HandsAndBelt.create(1, 1)
	b.store(Item.make(1, ItemKinds.Kind.ROUNDS, 6))
	b.store(Item.make(2, ItemKinds.Kind.ROUNDS, 6))
	assert_eq(b.slots[0].count, 12, "two boxes of 6 make one box of 12")
	assert_null(b.slots[1])
	b.store(Item.make(3, ItemKinds.Kind.ROUNDS, 6))
	assert_eq(b.slots[1].count, 6)


func test_consume_all_or_nothing() -> void:
	var b: HandsAndBelt = HandsAndBelt.create(1, 1)
	b.store(Item.make(1, ItemKinds.Kind.FUSE, 3))
	b.store(Item.make(2, ItemKinds.Kind.FUSE, 1))
	assert_false(b.consume(ItemKinds.Kind.FUSE, 5), "not enough: nothing spent")
	assert_eq(b.count_of(ItemKinds.Kind.FUSE), 4)
	assert_true(b.consume(ItemKinds.Kind.FUSE, 2))
	assert_eq(b.count_of(ItemKinds.Kind.FUSE), 2)
	assert_true(b.consume(ItemKinds.Kind.FUSE, 2))
	assert_eq(b.count_of(ItemKinds.Kind.FUSE), 0)
	for it: Item in b.slots:
		assert_null(it, "an emptied stack frees its slot")

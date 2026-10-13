extends GutTest
## NET-01's EntityRegistry: IDs, ordering, spatial buckets, state round-trip, the mirror.


func test_ids_rise_from_one_and_are_never_reused() -> void:
	var registry: EntityRegistry = EntityRegistry.new()
	var a: SimEntity = registry.create(WorldIds.EntityKind.MINER, Vector2.ZERO)
	var b: SimEntity = registry.create(WorldIds.EntityKind.ITEM, Vector2.ONE)
	assert_eq(a.id, 1)
	assert_eq(b.id, 2)
	assert_true(registry.destroy(1))
	var c: SimEntity = registry.create(WorldIds.EntityKind.ITEM, Vector2.ONE)
	assert_eq(c.id, 3, "a destroyed entity's ID is not reused")
	assert_false(registry.destroy(1), "destroying twice fails")
	assert_eq(registry.ids(), PackedInt64Array([2, 3]))


func test_ascending_iteration_after_churn() -> void:
	var registry: EntityRegistry = EntityRegistry.new()
	for i: int in 20:
		registry.create(WorldIds.EntityKind.ITEM, Vector2(i, 0))
	for id: int in [4, 9, 1, 20]:
		registry.destroy(id)
	var ids: PackedInt64Array = registry.ids()
	var sorted_ids: PackedInt64Array = ids.duplicate()
	sorted_ids.sort()
	assert_eq(ids, sorted_ids)
	assert_eq(ids.size(), 16)


func test_spatial_buckets_follow_moves_including_negative_cells() -> void:
	var registry: EntityRegistry = EntityRegistry.new()
	var miner: SimEntity = registry.create(WorldIds.EntityKind.MINER, Vector2(5.5, 5.5))
	var item: SimEntity = registry.create(WorldIds.EntityKind.ITEM, Vector2(-0.5, 3.0))
	assert_eq(registry.ids_in_cell(Vector2i(0, 0)), PackedInt64Array([miner.id]))
	assert_eq(registry.ids_in_cell(Vector2i(-1, 0)), PackedInt64Array([item.id]))
	registry.move(miner.id, Vector2(-25.0, 41.0))
	assert_eq(registry.ids_in_cell(Vector2i(0, 0)), PackedInt64Array())
	assert_eq(registry.ids_in_cell(Vector2i(-2, 2)), PackedInt64Array([miner.id]))
	assert_eq(registry.ids_near_cell(Vector2i(-1, 1), 1), PackedInt64Array([miner.id, item.id]))
	registry.destroy(item.id)
	assert_eq(registry.ids_in_cell(Vector2i(-1, 0)), PackedInt64Array())


func test_state_round_trip() -> void:
	var registry: EntityRegistry = EntityRegistry.new()
	for i: int in 5:
		registry.create(WorldIds.EntityKind.ITEM, Vector2(i * 7.25, -i))
	registry.destroy(2)
	var writer: SimStateWriter = SimStateWriter.new()
	registry.write_state(writer)
	var restored: EntityRegistry = EntityRegistry.new()
	restored.read_state(SimStateReader.new(writer.bytes()))
	assert_eq(restored.ids(), registry.ids())
	assert_eq(restored.next_id(), 6)
	assert_eq(restored.create(WorldIds.EntityKind.ITEM, Vector2.ZERO).id, 6, "the counter survives a restore")
	assert_eq(restored.get_entity(4).position, Vector2(21.75, -3))
	assert_eq(restored.ids_in_cell(Vector2i(1, -1)), PackedInt64Array([4, 5]))


func test_packed_mirror_round_trips_through_native() -> void:
	var registry: EntityRegistry = EntityRegistry.new()
	registry.create(WorldIds.EntityKind.MINER, Vector2(1.25, 2.5), 3)
	registry.create(WorldIds.EntityKind.MOTH, Vector2(-700.0, 12.0))
	var mirror: Dictionary = registry.packed_mirror()
	var mirrored_ids: PackedInt64Array = mirror["ids"]
	assert_eq(mirrored_ids, PackedInt64Array([1, 2]))
	assert_true(registry.push_mirror(9))
	assert_eq(LbEntityMirror.mirrored_tick(), 9)
	assert_eq(LbEntityMirror.count(), 2)
	var moth: Dictionary = LbEntityMirror.find(2)
	assert_eq(int(Variants.number(moth["kind"])), WorldIds.EntityKind.MOTH)
	assert_eq(Variants.number(moth["x"]), -700.0)
	var miner: Dictionary = LbEntityMirror.find(1)
	assert_eq(int(Variants.number(miner["flags"])), 3)
	assert_true(LbEntityMirror.find(3).is_empty())

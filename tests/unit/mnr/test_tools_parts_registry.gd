extends GutTest
## MNR-12: the four tools take a belt slot each and the five parts their §4.6 slot use (fuses 3 a
## slot, rope clamps 4, the rest one); every job names the design's tools and parts.


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_tools_one_slot_each() -> void:
	assert_eq(ToolsParts.TOOLS.size(), 4)
	for kind: ItemKinds.Kind in ToolsParts.TOOLS:
		assert_eq(ItemKinds.hand_class(kind), ItemKinds.HandClass.BELT, ItemKinds.text_key(kind))
		assert_eq(ItemKinds.stack_size(kind), 1, "%s: one slot, unstacked" % ItemKinds.text_key(kind))
		assert_false(ToolsParts.is_part_kind(kind))


func test_parts_slot_use() -> void:
	var want: Dictionary = {ItemKinds.Kind.FUSE: 3, ItemKinds.Kind.MAGNETO: 1, ItemKinds.Kind.DRIVE_BELT: 1,
		ItemKinds.Kind.BRAKE_SHOE: 1, ItemKinds.Kind.ROPE_CLAMP: 4}
	assert_eq(ToolsParts.PARTS.size(), 5)
	for kind: ItemKinds.Kind in ToolsParts.PARTS:
		assert_eq(ItemKinds.hand_class(kind), ItemKinds.HandClass.BELT)
		assert_eq(ItemKinds.stack_size(kind), int(Variants.number(want[kind])), "%s a slot" % ItemKinds.text_key(kind))
		assert_false(ToolsParts.is_tool_kind(kind))


func test_jobs_name_the_design_tools_and_parts() -> void:
	var S: ItemKinds.Kind = ItemKinds.Kind.SPANNER
	var H: ItemKinds.Kind = ItemKinds.Kind.HAMMER
	var want: Dictionary = {
		&"magneto": [[S], {ItemKinds.Kind.MAGNETO: 1}],
		&"brake_shoes": [[S], {ItemKinds.Kind.BRAKE_SHOE: 2}],
		&"drum_gear": [[S, H], {}],
		&"rope_clamps": [[S], {ItemKinds.Kind.ROPE_CLAMP: 4}],
		&"drive_belt": [[H], {ItemKinds.Kind.DRIVE_BELT: 1}],
		&"free_the_cage": [[ItemKinds.Kind.CROWBAR], {}],
		&"power": [[ItemKinds.Kind.WIRE_CUTTERS], {ItemKinds.Kind.FUSE: 3}],
	}
	assert_eq(ToolsParts.JOBS.size(), want.size())
	for job: StringName in want.keys():
		var got: Dictionary = ToolsParts.JOBS[job]
		var w: Array = want[job]
		assert_eq(str(got["tools"]), str(w[0]), "%s's tools" % job)
		assert_eq(str(got["parts"]), str(w[1]), "%s's parts" % job)

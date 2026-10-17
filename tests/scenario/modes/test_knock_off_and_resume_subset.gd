extends "res://tests/scenario/kit/scenario_test.gd"
## MOD-05 (Gameplay §13.11, §3.5): four players knock off. Every member holds the same save (the
## host's file, byte for byte) and is at the Pithead with no Lamp Check. Two come back on another
## PC's copy: the run resumes from that moment (the same tick, positions and draw). The absent
## conscious miner is gone from the world, so out of the crew count and beyond every creature, its
## lamp and belt on the bench; the absent unconscious miner lies where it was, a body. Its egg clock
## (a stand-in for CRT-06's) shows the same time left when its player returns, however long the
## others played, and so does its Hurt; the returning miner stands up in base camp with an empty belt
## and no lamp, its marks as they were.

const K = preload("res://tests/unit/modes/knock_off_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_four_knock_off_and_two_come_back() -> void:
	K.S.clear(5011)
	var s: Scenario = make(K.cfg(5011))
	K.camp(s)
	var ann: MinerHandle = K.miner(s, "ann", 0)
	var bob: MinerHandle = K.miner(s, "bob", 1)
	var cat: MinerHandle = K.miner(s, "cat", 2)
	var dot: MinerHandle = K.miner(s, "dot", 3)
	K.S.L.lit_in_hand(s, cat)
	assert_true(s.run.inventory.give(s.run, cat.entity_id, s.run.inventory.world.make(ItemKinds.Kind.SPANNER)))
	s.run.miner_state.miner(cat.entity_id).overlays.marks[MinerOverlays.INFESTED] = true
	s.run.miner_state.miner(cat.entity_id).overlays.hurt_until = s.run.tick + 600
	assert_true(s.run.falls.fall_unconscious(s.run, dot.entity_id, FallCause.Cause.BLAST))
	s.run.header.draw = PackedStringArray(["dry_stores"])  # as HAZ-07 will draw it
	s.step(5)
	assert_true(s.run.knock_off.available)
	var tick: int = s.run.tick
	var at: Dictionary = {}
	for h: MinerHandle in [ann, bob, dot]:
		at[h.name] = s.run.registry.get_entity(h.entity_id).position
	var uuid: String = s.run.header.run_uuid
	assert_eq(K.knock_off(s), "", "the crew knocked off")
	assert_true(s.run.frozen, "every timer frozen")
	var host_bytes: PackedByteArray = FileAccess.get_file_as_bytes(K.knockoff_path(s))
	assert_eq(str(SaveContainer.read_header(host_bytes)["kind"]), "knockoff")
	for h: MinerHandle in [ann, bob, cat, dot]:
		assert_eq(h.connection.state, ClientConnection.State.REJECTED, "%s at the Pithead" % h.name)
		assert_eq(h.connection.reject_reason, Protocol.Reject.KNOCKED_OFF)
		assert_true(h.connection.lamp_check.is_empty(), "no Lamp Check shown")
		assert_eq(SaveContainer.hash_of(FileAccess.get_file_as_bytes(K.client_copy(s, h, uuid))), SaveContainer.hash_of(host_bytes),
			"%s holds the host's save, byte for byte" % h.name)
	var copy: String = K.client_copy(s, bob, uuid)
	K.S.kill(s)
	# Another PC: Bob's copy.
	var b: Scenario = K.resume(make, 5011, copy)[0]
	assert_eq(b.run.tick, tick, "from that moment")
	# Exactly the frozen state: captured again at once, every system as the knock-off saved it, but
	# NET-11's Hands, which hold each player's conscious miner until its player is back (or it waits).
	var saved: Dictionary = SaveResume.open_file(copy)["sections"]
	var again: Dictionary = Snapshot.capture(b.run, b.net)
	var state_was: Dictionary = Variants.dict(bytes_to_var(Snapshot.section(saved, Snapshot.SECTION_STATE)))
	var state_now: Dictionary = Variants.dict(bytes_to_var(Snapshot.section(again, Snapshot.SECTION_STATE)))
	assert_eq(state_now.size(), state_was.size(), "the same systems")
	for raw: Variant in state_was.keys():
		if str(raw) != "hands":
			assert_eq(var_to_str(state_now.get(raw, null)), var_to_str(state_was[raw]), "system %s as saved" % str(raw))
	assert_true(Snapshot.section(again, Snapshot.SECTION_DIFF_LOG) == Snapshot.section(saved, Snapshot.SECTION_DIFF_LOG), "the diff log as saved")
	assert_eq(b.run.header.draw, PackedStringArray(["dry_stores"]), "the draw holds")
	assert_true(b.run.header.resumed)
	var eggs: Dictionary = {cat.entity_id: b.run.tick + 3000}
	b.run.absent.register_keeper("eggs", func(r: RunState, e: int) -> Variant:
			return int(Variants.number(eggs[e])) - r.tick if eggs.has(e) else null,
		func(r: RunState, e: int, left: Variant, _frozen: int) -> void:
			if left != null:
				eggs[e] = r.tick + int(Variants.number(left)))
	var back_ann: MinerHandle = b.rejoin("ann")
	var back_bob: MinerHandle = b.rejoin("bob")
	assert_eq(b.run.absent.park_absent(b.run), 1, "Cat waits; Dot lies where she is")
	b.step(2)
	assert_false(b.run.registry.has(cat.entity_id), "Cat's miner is gone from the world")
	assert_true(b.run.absent.is_waiting("cat"))
	assert_true(b.run.registry.has(dot.entity_id), "Dot's body lies where it was")
	var dot_at: Vector2 = at["dot"]
	assert_lt(b.run.registry.get_entity(dot.entity_id).position.distance_to(dot_at), 0.01)
	assert_eq(b.run.miner_state.life(dot.entity_id), MinerTransitions.Life.UNCONSCIOUS)
	for h: MinerHandle in [back_ann, back_bob]:
		var stood: Vector2 = at[h.name]
		assert_lt(b.run.registry.get_entity(h.entity_id).position.distance_to(stood), 0.01, "%s where she stood" % h.name)
	assert_eq(b.run.crew.compute(b.run), 2, "out of the crew count: Ann and Bob")
	var bench: Array[int] = K.on_bench(b)
	assert_true(bench.has(ItemKinds.Kind.GAUZE_LAMP) and bench.has(ItemKinds.Kind.SPANNER), "Cat's lamp and belt on the bench: %s" % [bench])
	b.step(1000)
	var back_cat: MinerHandle = b.rejoin("cat")
	var e: int = back_cat.entity_id
	assert_eq(int(Variants.number(eggs[e])) - b.run.tick, 3000, "the egg clock waited with her")
	b.step(2)
	assert_false(b.run.absent.is_waiting("cat"))
	assert_true(b.run.registry.has(e) and e != cat.entity_id, "Cat stands up again")
	var pos: Vector2 = b.run.registry.get_entity(e).position
	assert_true(b.run.base_camp.inside_tiles.has(Vector2i(floori(pos.x), floori(pos.y))), "in base camp")
	assert_eq(b.run.miner_state.life(e), MinerTransitions.Life.UPRIGHT)
	assert_null(b.run.lamps.lamp_in_hand(e), "no lamp")
	assert_eq(b.run.inventory.hands_of(e).held_items().size(), 0, "an empty belt")
	assert_true(b.run.miner_state.miner(e).overlays.marks.has(MinerOverlays.INFESTED), "her marks as they were")
	assert_eq(int(Variants.number(eggs[e])) - b.run.tick, 2998, "and runs again now she is back")
	var hurt_left: int = b.run.miner_state.miner(e).overlays.hurt_until - b.run.tick
	assert_between(hurt_left, 590, 600, "and her Hurt (%d ticks left)" % hurt_left)


## Both absent players' miners conscious: both wait off the map, out of the crew count and beyond
## every creature (no entity of theirs in the world), and both lamps and belts lie on the bench.
func test_two_absent_wait_off_the_map() -> void:
	K.S.clear(5012)
	var s: Scenario = make(K.cfg(5012))
	K.camp(s)
	K.miner(s, "ann", 0)
	K.miner(s, "bob", 1)
	var cat: MinerHandle = K.miner(s, "cat", 2)
	var dot: MinerHandle = K.miner(s, "dot", 3)
	for h: MinerHandle in [cat, dot]:
		K.S.L.lit_in_hand(s, h)
	assert_true(s.run.inventory.give(s.run, dot.entity_id, s.run.inventory.world.make(ItemKinds.Kind.SPANNER)))
	s.step(5)
	var uuid: String = s.run.header.run_uuid
	assert_eq(K.knock_off(s), "", "the crew knocked off")
	var copy: String = K.client_copy(s, cat, uuid)
	K.S.kill(s)
	var b: Scenario = K.resume(make, 5012, copy)[0]
	b.rejoin("ann")
	b.rejoin("bob")
	assert_eq(b.run.absent.park_absent(b.run), 2, "Cat and Dot both wait")
	b.step(2)
	var gone: Array[int] = [cat.entity_id, dot.entity_id]
	for h: MinerHandle in [cat, dot]:
		assert_false(b.run.registry.has(h.entity_id), "%s's miner is off the map" % h.name)
		assert_true(b.run.absent.is_waiting(h.name))
	for id: int in b.run.registry.ids():
		var e: SimEntity = b.run.registry.get_entity(id)
		if e.kind == WorldIds.EntityKind.MINER:
			assert_false(gone.has(id), "no miner of theirs for a creature to find")
	assert_eq(b.run.crew.compute(b.run), 2, "out of the crew count")
	var bench: Array[int] = K.on_bench(b)
	assert_eq(bench.count(ItemKinds.Kind.GAUZE_LAMP), 2, "both lamps on the bench: %s" % [bench])
	assert_true(bench.has(ItemKinds.Kind.SPANNER), "and Dot's belt")

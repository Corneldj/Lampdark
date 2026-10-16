extends GutTest
## The first playtest's standard elements (Gameplay §14.3, Proposed): the hotbar, the pick-up notice,
## the status line and the key hints. Each reads only the client's own records (the inventory, the
## own block, StatusWire) and draws only text keys and key labels.

const W = preload("res://tests/unit/ui/inplay_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_client())


static func _inv(slots: Array, free: Array = [0, 0], lamp: Array = [0, 0], selected: int = 0) -> Dictionary:
	return {"lamp": lamp, "hooked": false, "free": free, "slots": slots, "selected": selected, "lamp_shut": false, "lamp_wick": 1}


func test_the_clients_life_values_are_the_servers() -> void:
	assert_eq([StatusWire.LIFE_UPRIGHT, StatusWire.LIFE_CAUGHT, StatusWire.LIFE_GRABBED, StatusWire.LIFE_UNCONSCIOUS, StatusWire.LIFE_DEAD],
		[MinerTransitions.Life.UPRIGHT, MinerTransitions.Life.CAUGHT, MinerTransitions.Life.GRABBED, MinerTransitions.Life.UNCONSCIOUS,
			MinerTransitions.Life.DEAD])
	assert_eq(StatusWire.LIFE_UNCONSCIOUS, DarkView.LIFE_UNCONSCIOUS)


func test_the_hotbar_shows_hands_and_belt_in_play_only() -> void:
	var h: Hotbar = Hotbar.new()
	add_child_autofree(h)
	var store: BindingsStore = BindingsStore.new()
	var inv: Dictionary = _inv([[ItemKinds.Kind.SPANNER, 1], [ItemKinds.Kind.FUSE, 3], [0, 0], [0, 0]], [0, 0],
		[ItemKinds.Kind.GAUZE_LAMP, 1], 1)
	h.update(true, inv, false, store, "kbm", 0.0)
	assert_true(h.visible)
	assert_eq(h.slot_keys, ["1", "2", "3", "4"] as Array[String], "the slots by their keys")
	h.update(true, _inv(Variants.array(inv["slots"]), [0, 0], [ItemKinds.Kind.GAUZE_LAMP, 1], 0), false, store, "kbm", 1.0)
	assert_eq(h.name_key, "item.spanner", "the selected item named when the selection changes")
	h.update(true, _inv(Variants.array(inv["slots"]), [0, 0], [ItemKinds.Kind.GAUZE_LAMP, 1], 0), false, store, "kbm", 1.0 + Tuning.f(&"camera.hotbar_name_s") + 0.1)
	assert_eq(h.name_key, "", "then gone")
	h.update(false, inv, false, store, "kbm", 9.0)
	assert_false(h.visible, "hidden out of play (the Dark, Check Lamp, a close-up)")
	for i: int in 6:
		assert_true(Rect2(Vector2.ZERO, ScreenElementRegistry.CANVAS).encloses(Hotbar.box(i)), "box %d on the canvas" % i)
	h.queue_redraw()
	await wait_process_frames(1)


func test_the_pick_up_notice_names_what_arrived_and_where() -> void:
	var before: Dictionary = _inv([[0, 0], [0, 0], [0, 0], [0, 0]])
	var spanner: Dictionary = _inv([[0, 0], [ItemKinds.Kind.SPANNER, 1], [0, 0], [0, 0]])
	assert_eq(PickupNotice.gained_place(before, spanner), {"kind": ItemKinds.Kind.SPANNER, "place": "toast.belt", "slot": 1})
	var lamp: Dictionary = _inv([[0, 0], [0, 0], [0, 0], [0, 0]], [0, 0], [ItemKinds.Kind.GAUZE_LAMP, 1])
	assert_eq(PickupNotice.gained_place(before, lamp), {"kind": ItemKinds.Kind.GAUZE_LAMP, "place": "toast.lamp_hand", "slot": -1})
	var can: Dictionary = _inv([[0, 0], [0, 0], [0, 0], [0, 0]], [ItemKinds.Kind.PARAFFIN_CAN, 1])
	var can_place: String = PickupNotice.gained_place(before, can)["place"]
	assert_eq(can_place, "toast.free_hand")
	var fuses_1: Dictionary = _inv([[ItemKinds.Kind.FUSE, 1], [0, 0], [0, 0], [0, 0]])
	var fuses_2: Dictionary = _inv([[ItemKinds.Kind.FUSE, 2], [0, 0], [0, 0], [0, 0]])
	var fuse_slot: int = PickupNotice.gained_place(fuses_1, fuses_2)["slot"]
	assert_eq(fuse_slot, 0, "a second fuse on its stack")
	var hooked: Dictionary = lamp.duplicate(true)
	hooked["hooked"] = true
	assert_eq(PickupNotice.gained_place(lamp, hooked), {}, "hooking the lamp is no pick-up")
	var slotted: Dictionary = _inv([[ItemKinds.Kind.GAUZE_LAMP, 1], [0, 0], [0, 0], [0, 0]])
	assert_eq(PickupNotice.gained_place(lamp, slotted), {}, "nor moving it to the belt")
	var n: PickupNotice = PickupNotice.new()
	add_child_autofree(n)
	var store: BindingsStore = BindingsStore.new()
	n.update(true, before, store, "kbm", 0.0)
	assert_false(n.visible, "the first record (the welcome) shows nothing")
	n.update(true, spanner, store, "kbm", 1.0)
	assert_true(n.visible)
	assert_eq([n.item_key, n.place_key, n.key_label], ["item.spanner", "toast.belt", "2"])
	n.update(true, spanner, store, "kbm", 1.0 + Tuning.f(&"camera.pickup_notice_s") + 0.1)
	assert_false(n.visible, "for a moment only")


func test_the_status_line_explains_the_body() -> void:
	var s: StatusBanner = StatusBanner.new()
	add_child_autofree(s)
	var pinned: Dictionary = {"cues": MinerCues.HALF_IN_WALL, "flags": StatusWire.STRUGGLE}
	s.update(true, MinerTransitions.Life.GRABBED, false, pinned, 0, 0.0)
	assert_eq([s.title_key, s.sub_key], ["status.pinned", ""], "pinned; the ring and the hint offer the struggle")
	s.update(true, MinerTransitions.Life.GRABBED, false, {"cues": MinerCues.DRAGGED, "flags": 0}, 0, 0.2)
	assert_eq([s.title_key, s.sub_key], ["status.dragged", "status.sub.teammate_pull"], "in a crew: a teammate pulls you free")
	s.update(true, MinerTransitions.Life.UPRIGHT, false, {}, 0, 0.3)
	assert_eq(s.title_key, "status.broke_free", "a moment's line on getting free")
	s.update(true, MinerTransitions.Life.UPRIGHT, false, {}, 0, 0.3 + Tuning.f(&"camera.status_flash_s") + 0.1)
	assert_false(s.visible)
	s.update(true, MinerTransitions.Life.UNCONSCIOUS, false, {"cues": MinerCues.LYING_BREATHING, "flags": 0}, 0, 5.0)
	assert_eq([s.title_key, s.sub_key], ["status.unconscious", "status.sub.carry"])
	var counting: Dictionary = {"cues": MinerCues.LYING_BREATHING, "flags": StatusWire.REVIVE_COUNTING, "revive_due_tick": 600,
		"revive_ticks": 600}
	s.update(true, MinerTransitions.Life.UNCONSCIOUS, false, counting, 300, 6.0)
	assert_eq(s.sub_key, "status.sub.self_revive")
	assert_almost_eq(s.ring, 0.5, 1e-6, "the count as a ring, never a number")
	s.update(true, MinerTransitions.Life.UNCONSCIOUS, true, counting, 300, 7.0)
	assert_eq(s.title_key, "status.coming_round")
	for key: String in ["status.pinned", "status.dragged", "status.held", "status.caught", "status.caught_jaws", "status.caught_prop",
			"status.caught_pit", "status.unconscious", "status.coming_round", "status.dead", "status.broke_free", "status.came_round",
			"status.sub.teammate_pull", "status.sub.teammate_free", "status.sub.carry", "status.sub.self_revive",
			"status.sub.revive_waits", "hint.light", "hint.open_shutter", "hint.switch_on", "hint.shutter", "hint.wick",
			"hint.struggle", "hint.crawl", "hint.call_help", "toast.picked_up", "toast.belt", "toast.lamp_hand", "toast.free_hand",
			"hotbar.lamp", "hotbar.hand"]:
		assert_ne(UiText.text(key), "", "%s has text" % key)
	s.queue_redraw()
	await wait_process_frames(1)


func test_the_key_hints_say_what_to_press() -> void:
	var k: KeyHints = KeyHints.new()
	add_child_autofree(k)
	var store: BindingsStore = BindingsStore.new()
	var r: InputRouter = InputRouter.new(store, "kbm")
	var out: Dictionary = _inv([], [0, 0], [ItemKinds.Kind.GAUZE_LAMP, 1])
	k.update(true, MinerTransitions.Life.UPRIGHT, false, out, false, {}, r, store, 0.0)
	assert_eq(k.hints.size(), 1)
	assert_eq([k.hints[0][0], k.hints[0][1]], ["R", "hint.light"], "a lamp out in hand: Hold R, light it")
	var hold_s: float = Variants.number(k.hints[0][2])
	assert_almost_eq(hold_s, Tuning.f(&"lamp.flint_time"), 1e-6, "held, at the flint's time")
	var shut: Dictionary = out.duplicate(true)
	shut["lamp_shut"] = true
	k.update(true, MinerTransitions.Life.UPRIGHT, false, shut, false, {}, r, store, 0.5)
	assert_eq([k.hints[0][0], k.hints[0][1]], ["Q", "hint.open_shutter"])
	k.update(true, MinerTransitions.Life.UPRIGHT, false, out, true, {}, r, store, 1.0)
	assert_eq(k.hints.map(func(h: Array) -> String: return str(h[1])), ["hint.shutter", "hint.wick"], "first lit: the shutter and wick keys")
	k.update(true, MinerTransitions.Life.UPRIGHT, false, out, true, {}, r, store, 1.0 + Tuning.f(&"camera.lamp_hint_s") + 0.1)
	assert_false(k.visible, "for a while only")
	var offered: Dictionary = {"cues": MinerCues.HALF_IN_WALL, "flags": StatusWire.STRUGGLE}
	k.update(true, MinerTransitions.Life.GRABBED, false, out, true, offered, r, store, 20.0)
	assert_eq([k.hints[0][0], k.hints[0][1]], ["E", "hint.struggle"], "pinned: E, press in the zone")
	var press_hold: float = Variants.number(k.hints[0][2])
	assert_eq(press_hold, 0.0, "a press, not a hold")
	k.update(true, MinerTransitions.Life.GRABBED, false, out, true, {"cues": MinerCues.DRAGGED, "flags": 0}, r, store, 22.0)
	assert_false(k.visible, "no struggle offered (dragged in a crew): no hint")
	k.update(true, MinerTransitions.Life.UNCONSCIOUS, true, out, false, {}, r, store, 30.0)
	assert_eq(k.hints.map(func(h: Array) -> String: return str(h[1])), ["hint.crawl", "hint.call_help"], "coming round")
	assert_eq(str(k.hints[0][0]), "W A S D")
	k.queue_redraw()
	await wait_process_frames(1)


func test_the_struggle_ring_turns_at_the_servers_pace() -> void:
	var ring: StruggleRing = StruggleRing.new()
	add_child_autofree(ring)
	var st: Dictionary = {"flags": StatusWire.STRUGGLE, "epoch": 100, "sweep_ticks": 28, "zone_start": 180.0, "zone_size": 70.0,
		"hits": 1, "needed": 3, "lockout_until": 0}
	ring.update(true, st, Vector2(960, 540), 107.0)
	assert_true(ring.visible)
	assert_almost_eq(ring.needle, 90.0, 1e-6, "a quarter turn after a quarter of the sweep")
	assert_false(ring.locked)
	st["lockout_until"] = 110
	ring.update(true, st, Vector2(960, 540), 108.0)
	assert_true(ring.locked, "dimmed through a miss's lockout")
	ring.update(true, {"flags": 0}, Vector2(960, 540), 108.0)
	assert_false(ring.visible, "no struggle: no ring")
	ring.queue_redraw()
	await wait_process_frames(1)

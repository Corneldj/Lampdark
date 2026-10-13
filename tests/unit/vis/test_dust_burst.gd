extends "res://tests/scenario/kit/scenario_test.gd"
## VIS-09: dust_burst (CRT-06's laying, MNR-16's flinch) reaches a viewer who sees a lit tile within
## its radius, as a VisualEvents.DUST_BURST carrying the radius and the length; others get none.
## The client draws it and never plays it.

const A = preload("res://tests/unit/sound/audio_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _bursts(h: MinerHandle) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in h.connection.events:
		if int(Variants.number(e["type"])) == VisualEvents.Type.DUST_BURST:
			out.append(e)
	return out


func test_burst_to_who_sees_it() -> void:
	var s: Scenario = make({"seed": 93, "fixture": A.hall()})
	var ann: MinerHandle = s.add_miner("ann", Vector2i(5, 3), {"facing_deg": 0.0})
	var bob: MinerHandle = s.add_miner("bob", Vector2i(26, 3), {"facing_deg": 0.0})
	preload("res://tests/unit/mnr/lamp_world.gd").lit_in_hand(s, ann)
	s.step(4)
	s.run.tells.dust_burst(Vector2(7.5, 3.5), 1.0, 1.5)
	s.step(3)
	var a: Array[Dictionary] = _bursts(ann)
	assert_eq(a.size(), 1, "Ann sees the place lit")
	assert_almost_eq(float(Variants.number(a[0]["level_np"])), 1.0, 0.3, "the radius rides along")
	assert_almost_eq(float(Variants.number(a[0]["duration_s"])), 1.5, 0.11)
	assert_eq(_bursts(bob).size(), 0, "Bob, facing away down the dark hall, gets none")
	var p: EventPlayer = EventPlayer.new()
	add_child_autofree(p)
	p.play(AudioRecord.from_event(a[0]), 1)
	assert_eq(p.voices.size(), 0, "drawn, never played")

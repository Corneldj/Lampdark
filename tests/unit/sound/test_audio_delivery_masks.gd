extends "res://tests/scenario/kit/scenario_test.gd"
## SND-03: every player delivery runs the masks in order; a mask returning DROP (null) sends nothing:
## no record, no caption, no audit entry; a mask's change (gain, flags) rides on the record. The audit
## log has one entry per delivered record, with its event id, path length and portal.

const A = preload("res://tests/unit/sound/audio_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _setup(run_seed: int) -> Array:
	var s: Scenario = make({"seed": run_seed, "fixture": A.hall()})
	var ann: MinerHandle = s.add_miner("ann", Vector2i(5, 3))
	var bob: MinerHandle = s.add_miner("bob", Vector2i(20, 3))
	s.step(2)
	return [s, ann, bob, A.capture(s)]


func test_drop_sends_nothing() -> void:
	var parts: Array = _setup(1)
	var s: Scenario = parts[0]
	var ann: MinerHandle = parts[1]
	var bob: MinerHandle = parts[2]
	var got: Array[Array] = parts[3]
	var deaf: int = ann.slot
	s.run.audio.register_mask("deafen", func(_run: RunState, slot: int, _r: AudioRecord) -> Variant:
		return null if slot == deaf else {})
	var log_before: int = s.run.audio.deliveries.size()
	s.run.noise.emit(NoiseTypes.Type.SHOT, Vector2i(12, 3), {})
	s.step(2)
	var slots: Array[int] = []
	for g: Array in got:
		slots.append(int(Variants.number(g[0])))
	assert_false(slots.has(ann.slot), "dropped: no record for Ann")
	assert_true(slots.has(bob.slot), "Bob hears it")
	assert_eq(s.run.audio.deliveries.size() - log_before, 1, "one audit entry: Bob's")
	s.step(3)
	var heard: int = 0
	for e: Dictionary in ann.connection.events:
		if int(Variants.number(e["type"])) == NoiseTypes.Type.SHOT:
			heard += 1
	assert_eq(heard, 0, "nothing reaches Ann's client, so no caption either")


func test_changes_ride_on_the_record_in_order() -> void:
	var parts: Array = _setup(2)
	var s: Scenario = parts[0]
	var got: Array[Array] = parts[3]
	var order: Array[String] = []
	s.run.audio.register_mask("fan", func(_run: RunState, _slot: int, _r: AudioRecord) -> Variant:
		order.append("fan")
		return {"gain_db": -6})
	s.run.audio.register_mask("unconscious", func(_run: RunState, _slot: int, _r: AudioRecord) -> Variant:
		order.append("unconscious")
		return {"gain_db": -3, "flags": AudioRecord.MUFFLED})
	s.run.noise.emit(NoiseTypes.Type.SHOT, Vector2i(12, 3), {})
	s.step(2)
	assert_gt(got.size(), 0)
	for g: Array in got:
		var r: AudioRecord = g[1]
		assert_eq(r.gain_db, -9)
		assert_eq(r.flags & AudioRecord.MUFFLED, AudioRecord.MUFFLED)
	assert_eq(order.slice(0, 2), ["fan", "unconscious"] as Array[String], "in registration order")


func test_audit_log() -> void:
	var parts: Array = _setup(3)
	var s: Scenario = parts[0]
	var got: Array[Array] = parts[3]
	s.run.noise.emit(NoiseTypes.Type.SHOT, Vector2i(12, 3), {})
	s.step(2)
	var logged: Array = s.run.audio.deliveries.slice(s.run.audio.deliveries.size() - got.size())
	assert_eq(logged.size(), got.size(), "one entry per record")
	for e: Variant in logged:
		var d: Dictionary = e
		assert_true(d.has("event_id") and d.has("path_tiles") and d.has("via") and d.has("client"))
		assert_gt(float(Variants.number(d["path_tiles"])), 0.0)

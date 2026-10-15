extends "res://tests/scenario/kit/scenario_test.gd"
## NET-11: remove_player sends the client away with `removed`, a Hand takes the miner, and every
## later handshake from that player is refused with `removed`.

const R = preload("res://tests/unit/mnr/revolver_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_a_removed_player_stays_removed() -> void:
	var s: Scenario = make({"seed": 1311, "fixture": R.hall()})
	var ann: MinerHandle = R.miner(s, "ann", Vector2i(3, 2))
	R.miner(s, "bob", Vector2i(8, 2))
	s.step(3)
	var miner: int = ann.entity_id
	assert_true(s.run.drops.remove_player(s.run, "ann", "kicked", DropHandler.Takeover.KICKED))
	s.step(10)
	assert_eq(ann.connection.reject_reason, Protocol.Reject.REMOVED, "sent to the Pithead: removed")
	assert_false(ann.is_connected_now())
	assert_true(s.run.drops.hand_driven.has(miner), "a Hand takes the miner")
	ann.at(s.run.tick).reconnect_at()
	s.step(20)
	assert_false(ann.is_connected_now(), "never back")
	assert_eq(ann.connection.reject_reason, Protocol.Reject.REMOVED)

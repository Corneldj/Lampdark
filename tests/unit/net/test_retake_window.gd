extends "res://tests/scenario/kit/scenario_test.gd"
## NET-11: among friends a player retakes their miner after 20 minutes away; in public at 2:59, and
## at 3:01 is refused with seat_kept, the Hand keeping the place.

const R = preload("res://tests/unit/mnr/revolver_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


## Ann away from her seat for `away_s` (her drop moved back in time), then back.
func _away(mode: ServerConfig.Mode, away_s: float, run_seed: int) -> Array:
	var s: Scenario = make({"seed": run_seed, "fixture": R.hall(), "mode": mode})
	var ann: MinerHandle = R.miner(s, "ann", Vector2i(3, 2))
	R.miner(s, "bob", Vector2i(8, 2))
	s.step(3)
	var miner: int = ann.entity_id
	var slot: int = ann.slot
	ann.at(s.run.tick).disconnect_at()
	s.step(40)
	var seat: SeatTable.Seat = s.net.seats.seat_of("ann")
	assert_eq(seat.state, SeatTable.State.RESERVED, "her seat is held")
	seat.dropped_tick = s.run.tick - roundi(away_s * Tuning.f(&"net.tick_hz"))
	ann.at(s.run.tick).reconnect_at()
	s.step(20)
	return [s, ann, miner, slot]


func test_among_friends_after_twenty_minutes() -> void:
	var w: Array = _away(ServerConfig.Mode.FRIENDS, 20 * 60.0, 1301)
	var s: Scenario = w[0]
	var ann: MinerHandle = w[1]
	var miner: int = w[2]
	var slot: int = w[3]
	assert_true(ann.is_connected_now(), "back in")
	assert_eq(ann.slot, slot, "her own seat")
	assert_eq(s.run.movement.miner(ann.slot).entity_id, miner, "driving her own miner")
	assert_false(s.run.hands.hands.has(miner), "handed back")
	assert_eq(s.run.drops.retakes.size(), 1)


func test_public_at_two_fifty_nine_and_three_oh_one() -> void:
	var early: Array = _away(ServerConfig.Mode.PUBLIC, 179.0, 1302)
	var ann: MinerHandle = early[1]
	assert_true(ann.is_connected_now(), "2:59: back in")
	var late: Array = _away(ServerConfig.Mode.PUBLIC, 181.0, 1303)
	var s2: Scenario = late[0]
	var ann2: MinerHandle = late[1]
	assert_false(ann2.is_connected_now(), "3:01: refused")
	assert_eq(ann2.connection.reject_reason, Protocol.Reject.SEAT_KEPT, "the Hand keeps the place")
	var kept: int = late[2]
	assert_true(s2.run.hands.hands.has(kept), "still Hand-driven")

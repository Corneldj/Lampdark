extends GutTest
## NET-11: the seat table. A dropped player's seat is held for it, never handed to a newcomer, and
## retaken by identity or token; in public only within net.public_retake_window_s, after which the
## Hand keeps the place; a removed player is refused.


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_held_retaken_and_never_given_away() -> void:
	var t: SeatTable = SeatTable.new()
	t.on_seated("ann", 0, "tok-a", 10)
	t.on_seated("bob", 1, "tok-b", 10)
	assert_eq(t.on_hello("ann", "", 20, false), {}, "seated, nothing to retake")
	assert_not_null(t.on_dropped(0, 77, 30))
	assert_eq(t.held_slots(), {0: true}, "her slot is held")
	assert_eq(t.on_hello("cara", "", 40, false), {}, "a newcomer: a fresh seat (never slot 0)")
	assert_eq(t.on_hello("ann", "", 40, false), {"slot": 0}, "she retakes it by identity")
	assert_eq(t.on_hello("someone", "tok-a", 40, false), {"slot": 0}, "or by her token")
	assert_eq(t.seat_of("ann").miner, 77, "with her miner")
	t.on_seated("ann", 0, "tok-a2", 41)
	assert_eq(t.held_slots(), {}, "seated again")


func test_public_window_and_removal() -> void:
	var t: SeatTable = SeatTable.new()
	var hz: int = roundi(Tuning.f(&"net.tick_hz"))
	var window: int = roundi(Tuning.f(&"net.public_retake_window_s")) * hz
	assert_eq(window, 3600, "3 minutes")
	t.on_seated("ann", 0, "a", 0)
	t.on_dropped(0, 5, 100)
	assert_eq(t.on_hello("ann", "", 100 + window - 20, true), {"slot": 0}, "2:59: she retakes")
	t.on_seated("bob", 1, "b", 0)
	t.on_dropped(1, 6, 100)
	assert_eq(t.on_hello("bob", "", 100 + window + 20, true), {"reject": Protocol.Reject.SEAT_KEPT}, "3:01: the Hand keeps the place")
	assert_eq(t.seat_of("bob").state, SeatTable.State.HAND_KEEPS)
	assert_true(t.held_slots().has(1), "and the place stays out of a newcomer's reach")
	t.on_seated("cara", 2, "c", 0)
	t.on_dropped(2, 7, 100)
	assert_eq(t.on_hello("cara", "", 100 + 24000, false), {"slot": 2}, "among friends there is no window")
	t.on_removed("cara", 200, "kicked")
	assert_eq(t.on_hello("cara", "", 300, false), {"reject": Protocol.Reject.REMOVED}, "removed: refused")

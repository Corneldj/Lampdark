extends GutTest
## UI-02's input context: entering a close-up makes the mine's actions inert (no movement, holds,
## wheels, lamp keys or shots) while the close-up's own actions are live, and asks STM-06 for the
## "close_up" Steam Input action set; leaving restores the mine and its set.


func before_all() -> void:
	assert_true(Tuning.load_server())


## Everything the mine reads, held down at once, plus a close-up action.
func _frame(now: float) -> Dictionary:
	var down: Dictionary = {}
	for a: String in ["move_right", "interact", "use", "set_down", "relight", "check_lamp", "fire", "tap_rock", "callout", "wick_up",
			"shutter", "pencil", "close"]:
		down[a] = true
	return {"now_s": now, "down": down, "move": Vector2(1.0, 0.0), "facing_vec": Vector2(0.0, 1.0)}


func test_mine_actions_are_inert_and_close_up_actions_live() -> void:
	var router: InputRouter = InputRouter.new()
	var sets: Array[String] = []
	var ctx: CloseupInputContext = CloseupInputContext.new(router, null)
	ctx.activate_steam_set = func(set_name: String) -> void: sets.append(set_name)
	ctx.enter()
	assert_eq(router.context, InputContexts.Context.CLOSE_UP)
	assert_eq(ctx.active_steam_set, CloseupInputContext.STEAM_SET_CLOSE_UP)
	router.sample({"now_s": 0.0, "down": {}})
	var r: InputRecord = router.sample(_frame(0.05))
	assert_eq(r.move_dir, InputRecord.NO_DIRECTION, "the miner stands")
	assert_eq(r.holds, 0, "no held mine action")
	assert_eq(router.actions, [] as Array[Array], "no wheel, tap or shot")
	assert_true(router.close_up_events.has("pencil"))
	assert_true(router.close_up_events.has("close"))
	ctx.leave()
	assert_eq(router.context, InputContexts.Context.MINE)
	assert_eq(ctx.active_steam_set, CloseupInputContext.STEAM_SET_MINE)
	assert_eq(sets, ["close_up", "mine"] as Array[String], "STM-06 asked for each set in turn")
	router.sample({"now_s": 0.1, "down": {}})
	r = router.sample(_frame(0.15))
	assert_ne(r.move_dir, InputRecord.NO_DIRECTION, "back in the mine, movement is live again")
	assert_eq(router.close_up_events, [] as Array[String])

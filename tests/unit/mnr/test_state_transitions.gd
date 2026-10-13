extends GutTest
## MNR-03: every hook on every life state. Legal pairs give the §11.1 result; illegal ones are
## refused (a grab on Grabbed, a revive on Dead, any hook on Dead but the outcome).

const Life = MinerTransitions.Life

var sm: MinerStateSystem
var tick: int = 0


func before_all() -> void:
	assert_true(Tuning.load_server())


func before_each() -> void:
	sm = MinerStateSystem.new()
	tick = 0


func _flush() -> Array:
	tick += 1
	return sm.flush(tick)


## A fresh miner brought into a life state through the hooks themselves.
func _miner_in(state: int, entity: int) -> void:
	sm.add_miner(entity)
	match state:
		Life.CAUGHT:
			sm.enter_caught(entity, &"staple_pit", 1)
		Life.GRABBED:
			sm.enter_grabbed(entity, &"drag", 99)
		Life.UNCONSCIOUS:
			sm.fall_unconscious(entity, "smother")
		Life.DEAD:
			sm.kill(entity, "shot")
	_flush()
	assert_eq(sm.life(entity), state)


func _call(hook: String, entity: int) -> void:
	match hook:
		"enter_caught": sm.enter_caught(entity, &"man_trap", 3)
		"release_caught": sm.release_caught(entity, "teammate")
		"enter_grabbed": sm.enter_grabbed(entity, &"drag", 99)
		"end_grab": sm.end_grab(entity, true)
		"fall_unconscious": sm.fall_unconscious(entity, "blast")
		"kill": sm.kill(entity, "shot")
		"revive": sm.revive(entity, &"kit")
		"make_hurt": sm.make_hurt(entity, "blackdamp")
		"add_mark": sm.add_mark(entity, MinerOverlays.INFESTED)
		"set_rock_touched": sm.set_rock_touched(entity, 5000)
		"set_outcome": sm.set_outcome(entity, MinerTransitions.Outcome.ESCAPED)


func test_every_hook_on_every_state() -> void:
	# state -> hook -> the life state after it, or "refused"
	var expect: Dictionary = {
		Life.UPRIGHT: {"enter_caught": Life.CAUGHT, "release_caught": "refused", "enter_grabbed": Life.GRABBED,
			"end_grab": "refused", "fall_unconscious": Life.UNCONSCIOUS, "kill": Life.DEAD, "revive": "refused",
			"make_hurt": Life.UPRIGHT, "add_mark": Life.UPRIGHT, "set_rock_touched": Life.UPRIGHT, "set_outcome": Life.UPRIGHT},
		Life.CAUGHT: {"enter_caught": "refused", "release_caught": Life.UPRIGHT, "enter_grabbed": Life.GRABBED,
			"end_grab": "refused", "fall_unconscious": Life.UNCONSCIOUS, "kill": Life.DEAD, "revive": "refused",
			"make_hurt": Life.CAUGHT, "add_mark": Life.CAUGHT, "set_rock_touched": Life.CAUGHT, "set_outcome": Life.CAUGHT},
		Life.GRABBED: {"enter_caught": "refused", "release_caught": "refused", "enter_grabbed": "refused",
			"end_grab": Life.UPRIGHT, "fall_unconscious": Life.UNCONSCIOUS, "kill": Life.DEAD, "revive": "refused",
			"make_hurt": Life.GRABBED, "add_mark": Life.GRABBED, "set_rock_touched": Life.GRABBED, "set_outcome": Life.GRABBED},
		Life.UNCONSCIOUS: {"enter_caught": Life.UNCONSCIOUS, "release_caught": "refused", "enter_grabbed": Life.UNCONSCIOUS,
			"end_grab": "refused", "fall_unconscious": "refused", "kill": Life.DEAD, "revive": Life.UPRIGHT,
			"make_hurt": Life.UNCONSCIOUS, "add_mark": Life.UNCONSCIOUS, "set_rock_touched": Life.UNCONSCIOUS, "set_outcome": Life.UNCONSCIOUS},
		Life.DEAD: {"enter_caught": "refused", "release_caught": "refused", "enter_grabbed": "refused",
			"end_grab": "refused", "fall_unconscious": "refused", "kill": "refused", "revive": "refused",
			"make_hurt": "refused", "add_mark": "refused", "set_rock_touched": "refused", "set_outcome": Life.DEAD},
	}
	var entity: int = 1
	var refusals: int = 0
	for state: Variant in expect.keys():
		var row: Dictionary = expect[state]
		for hook: Variant in row.keys():
			_miner_in(int(Variants.number(state)), entity)
			_call(str(hook), entity)
			var result: Array = Variants.array(_flush()[0])
			var want: Variant = row[hook]
			if want is String:
				assert_false(Variants.flag(result[2]), "%s on %s is refused" % [hook, Life.find_key(int(Variants.number(state)))])
				refusals += 1
			else:
				assert_true(Variants.flag(result[2]), "%s on %s is legal" % [hook, Life.find_key(int(Variants.number(state)))])
				assert_eq(sm.life(entity), int(Variants.number(want)), "%s on %s" % [hook, Life.find_key(int(Variants.number(state)))])
			entity += 1
	assert_push_error_count(refusals, "each refusal is an error in a debug build")


func test_a_cure_needs_the_mark_and_an_outcome_is_set_once() -> void:
	sm.add_miner(1)
	sm.cure_mark(1, MinerOverlays.SOOT_LUNG)
	assert_false(Variants.flag(Variants.array(_flush()[0])[2]))
	sm.set_outcome(1, MinerTransitions.Outcome.LEFT_BELOW)
	sm.set_outcome(1, MinerTransitions.Outcome.ESCAPED)
	var results: Array = _flush()
	assert_true(Variants.flag(Variants.array(results[0])[2]))
	assert_false(Variants.flag(Variants.array(results[1])[2]), "an outcome is set once")
	assert_push_error_count(2)


func test_same_tick_requests_apply_dead_first() -> void:
	sm.add_miner(1)
	sm.fall_unconscious(1, "smother")
	sm.revive(1, &"kit")
	sm.kill(1, "shot")
	var results: Array = _flush()
	assert_eq(results.map(func(r: Variant) -> String: return str(Variants.array(r)[0])), ["kill", "fall_unconscious", "revive"])
	assert_eq(sm.life(1), Life.DEAD, "the kill wins; nothing revives the dead")
	assert_push_error_count(2)

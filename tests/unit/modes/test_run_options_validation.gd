extends GutTest
## MOD-03: every row of the modes table (Gameplay §13.5, §13.6) is enforced on the server. The Escape
## takes any list (Full while it is open), 1-5 players, Hands off by default, and one hard variant the
## host has unlocked; public quick-play only the Short list, no variant, its places; Night Shift the
## Short or Standard list alone, no variant. Each mode's places are the server's slots. The rule flags
## follow the mode and the humans at start.


func before_all() -> void:
	assert_true(Tuning.load_server())


func _opts(mode: ServerConfig.Mode, list: RunOptions.List, hard: String = "", hands: bool = false) -> RunOptions:
	var o: RunOptions = RunOptions.new()
	o.mode = mode
	o.list = list
	o.hard_variant = hard
	o.hands_in_empty_places = hands
	return o


func test_the_escape_takes_any_list_and_one_unlocked_variant() -> void:
	var unlocked: Array[String] = ["dead_lines"]
	for list: RunOptions.List in [RunOptions.List.SHORT, RunOptions.List.STANDARD, RunOptions.List.FULL]:
		assert_eq(RunSetup.refusal(_opts(ServerConfig.Mode.FRIENDS, list), unlocked, 3), "", "friends on %s" % RunOptions.LIST_NAMES[list])
	assert_eq(RunSetup.refusal(_opts(ServerConfig.Mode.FRIENDS, RunOptions.List.STANDARD, "dead_lines"), unlocked, 2), "")
	assert_ne(RunSetup.refusal(_opts(ServerConfig.Mode.FRIENDS, RunOptions.List.STANDARD, "one_lamp"), unlocked, 2), "",
		"a variant the host has not unlocked")
	assert_ne(RunSetup.refusal(_opts(ServerConfig.Mode.FRIENDS, RunOptions.List.STANDARD, "dead_lines,one_lamp"),
		["dead_lines", "one_lamp"] as Array[String], 2), "", "two variants")
	assert_ne(RunSetup.refusal(_opts(ServerConfig.Mode.FRIENDS, RunOptions.List.STANDARD, "fog"), unlocked, 2), "", "no such variant")
	assert_eq(RunSetup.refusal(_opts(ServerConfig.Mode.FRIENDS, RunOptions.List.STANDARD), [], 1), "", "a lobby of one")
	assert_ne(RunSetup.refusal(_opts(ServerConfig.Mode.FRIENDS, RunOptions.List.STANDARD), [], Tuning.i(&"modes.friends_lobby_max") + 1), "",
		"more than the lobby holds")
	Tuning.set_dev_override("lift.full_list_enabled", false)
	assert_ne(RunSetup.refusal(_opts(ServerConfig.Mode.FRIENDS, RunOptions.List.FULL), [], 2), "", "Full while it is cut")
	Tuning.clear_dev_overrides()


func test_public_quick_play_is_the_short_list_without_variants() -> void:
	assert_eq(RunSetup.refusal(_opts(ServerConfig.Mode.PUBLIC, RunOptions.List.SHORT, "", true), [], 2), "")
	assert_ne(RunSetup.refusal(_opts(ServerConfig.Mode.PUBLIC, RunOptions.List.STANDARD), [], 2), "", "Standard in public")
	assert_ne(RunSetup.refusal(_opts(ServerConfig.Mode.PUBLIC, RunOptions.List.FULL), [], 2), "", "Full in public")
	assert_ne(RunSetup.refusal(_opts(ServerConfig.Mode.PUBLIC, RunOptions.List.SHORT, "dead_lines"), ["dead_lines"] as Array[String], 2), "",
		"a variant in public")
	assert_ne(RunSetup.refusal(_opts(ServerConfig.Mode.PUBLIC, RunOptions.List.SHORT), [], roundi(Tuning.f(&"modes.public_places")) + 1), "")


func test_night_shift_is_alone_on_the_short_or_standard_list() -> void:
	assert_eq(RunSetup.refusal(_opts(ServerConfig.Mode.NIGHTSHIFT, RunOptions.List.SHORT), [], 1), "")
	assert_eq(RunSetup.refusal(_opts(ServerConfig.Mode.NIGHTSHIFT, RunOptions.List.STANDARD), [], 1), "")
	assert_ne(RunSetup.refusal(_opts(ServerConfig.Mode.NIGHTSHIFT, RunOptions.List.FULL), [], 1), "", "Full in Night Shift")
	assert_ne(RunSetup.refusal(_opts(ServerConfig.Mode.NIGHTSHIFT, RunOptions.List.SHORT, "one_lamp"), ["one_lamp"] as Array[String], 1), "")
	assert_ne(RunSetup.refusal(_opts(ServerConfig.Mode.NIGHTSHIFT, RunOptions.List.SHORT), [], 2), "", "Night Shift is played alone")


func test_each_mode_holds_its_places() -> void:
	assert_eq(RunSetup.places(ServerConfig.Mode.FRIENDS), 5, "friends' lobbies: 1 to 5")
	assert_eq(RunSetup.places(ServerConfig.Mode.PUBLIC), 4, "public quick-play: 2 to 4 humans")
	assert_eq(RunSetup.places(ServerConfig.Mode.NIGHTSHIFT), 1, "Night Shift: alone")
	assert_eq(RunSetup.refusal(_opts(ServerConfig.Mode.FRIENDS, RunOptions.List.STANDARD)), "",
		"no crew known yet (a dev server's launch): the places hold the count")
	assert_ne(RunSetup.refusal(_opts(ServerConfig.Mode.FRIENDS, RunOptions.List.STANDARD), [], 0), "",
		"a start with nobody seated")


func test_defaults_follow_the_modes_table() -> void:
	var friends: RunOptions = RunOptions.defaults(ServerConfig.Mode.FRIENDS)
	assert_eq(friends.list, RunOptions.list_from(Tuning.s(&"modes.default_list")))
	assert_eq(friends.hands_in_empty_places, Tuning.b(&"modes.hands_default_friends"), "Hands off by default among friends")
	assert_eq(friends.hard_variant, "")
	var public: RunOptions = RunOptions.defaults(ServerConfig.Mode.PUBLIC)
	assert_eq(public.list, RunOptions.List.SHORT)
	assert_true(public.hands_in_empty_places)
	assert_eq(RunOptions.defaults(ServerConfig.Mode.NIGHTSHIFT).list, RunOptions.List.SHORT)
	# The lobby form round-trips.
	var o: RunOptions = _opts(ServerConfig.Mode.FRIENDS, RunOptions.List.FULL, "no_chalk", true)
	var back: RunOptions = RunOptions.from_dict(o.to_dict())
	assert_eq(back.to_dict(), o.to_dict())
	assert_eq(o.to_args(), PackedStringArray(["--list", "full", "--hard", "no_chalk", "--hands"]))


func test_the_rule_flags_follow_the_mode_and_the_humans_at_start() -> void:
	var one: Dictionary = RunSetup.rule_flags(_opts(ServerConfig.Mode.FRIENDS, RunOptions.List.STANDARD), 1)
	assert_true(Variants.flag(one["solo_rules"]), "a friends lobby of one plays the solo rules")
	assert_false(Variants.flag(one["hands_fill"]), "Hands only when the host chose them")
	assert_true(Variants.flag(one["saved"]))
	assert_false(Variants.flag(one["public"]))
	var with_hands: Dictionary = RunSetup.rule_flags(_opts(ServerConfig.Mode.FRIENDS, RunOptions.List.STANDARD, "", true), 1)
	assert_true(Variants.flag(with_hands["solo_rules"]) and Variants.flag(with_hands["hands_fill"]))
	var two: Dictionary = RunSetup.rule_flags(_opts(ServerConfig.Mode.FRIENDS, RunOptions.List.STANDARD), 2)
	assert_false(Variants.flag(two["solo_rules"]), "two or more humans: not solo")
	var public: Dictionary = RunSetup.rule_flags(_opts(ServerConfig.Mode.PUBLIC, RunOptions.List.SHORT), 1)
	assert_true(Variants.flag(public["public"]) and Variants.flag(public["hands_fill"]))
	assert_false(Variants.flag(public["saved"]), "public runs are not saved")
	assert_false(Variants.flag(public["solo_rules"]))
	var night: Dictionary = RunSetup.rule_flags(_opts(ServerConfig.Mode.NIGHTSHIFT, RunOptions.List.SHORT), 1)
	assert_true(Variants.flag(night["solo_rules"]) and Variants.flag(night["saved"]))
	# A staged run 1 plays the Short list.
	assert_eq(RunSetup.list_kind(_opts(ServerConfig.Mode.FRIENDS, RunOptions.List.FULL), "1"), RunOptions.List.SHORT)
	assert_eq(RunSetup.list_kind(_opts(ServerConfig.Mode.FRIENDS, RunOptions.List.FULL), "2"), RunOptions.List.FULL)

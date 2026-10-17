extends GutTest
## MOD-03 (Gameplay §10.10): staging applies only when every player in the lobby is New Brigade, and
## follows the least-experienced player; one Old Hand (or a player with no profile) plays the full
## game. It is fixed when the run is created, so a later joiner never changes it; a staged run 1
## plays the Short list whatever the host chose, later staged runs the host's.

var hub: InProcessTransport.Hub
var run: RunState
var net: ServerNet


func before_all() -> void:
	assert_true(Tuning.load_server())


func before_each() -> void:
	hub = InProcessTransport.Hub.new()
	run = RunState.create(61, ServerConfig.Mode.FRIENDS, false)
	var server: InProcessTransport = InProcessTransport.new(hub)
	assert_eq(server.listen("server", 1), OK)
	net = ServerNet.new(server, 5)
	ServerSystems.install(run, net)


func test_the_level_follows_the_least_experienced_player() -> void:
	var brigade: int = Tuning.i(&"modes.new_brigade_runs")
	assert_eq(brigade, 5, "New Brigade for a player's first five runs")
	assert_eq(RunSetup.staging_level([0, 2, 4] as Array[int]), 1, "one of them on their first run: run 1")
	assert_eq(RunSetup.staging_level([3, 2] as Array[int]), 3)
	assert_eq(RunSetup.staging_level([4] as Array[int]), 5, "a lobby of one on their fifth run")
	assert_eq(RunSetup.staging_level([0, brigade] as Array[int]), 0, "one Old Hand: the full game")
	assert_eq(RunSetup.staging_level([1, -1] as Array[int]), 0, "a player with no profile counts as an Old Hand")
	assert_eq(RunSetup.staging_level([] as Array[int]), 0)
	assert_eq(RunSetup.staging([2, 2] as Array[int]), "3", "the header's staging: the level")
	assert_eq(RunSetup.staging([0, 9] as Array[int]), "", "unstaged")


func _options(list: RunOptions.List) -> RunOptions:
	var o: RunOptions = RunOptions.defaults(ServerConfig.Mode.FRIENDS)
	o.list = list
	return o


func test_a_staged_first_run_plays_the_short_list() -> void:
	assert_eq(RunSetup.create(run, _options(RunOptions.List.FULL), 2, [0, 3] as Array[int]), "")
	assert_eq(run.header.staging, "1")
	assert_eq(run.repair.list.kind, RepairList.Kind.SHORT, "staged run 1 is always the Short list")
	assert_eq(run.header.draw, PackedStringArray(), "staged runs play the defaults, with no condition")
	var later: RunState = RunState.create(62, ServerConfig.Mode.FRIENDS, false)
	ServerSystems.install(later, ServerNet.new(InProcessTransport.new(InProcessTransport.Hub.new()), 5))
	assert_eq(RunSetup.create(later, _options(RunOptions.List.FULL), 2, [1, 3] as Array[int]), "")
	assert_eq(later.header.staging, "2")
	assert_eq(later.repair.list.kind, RepairList.Kind.FULL, "from run 2 the host's list")


func test_one_old_hand_plays_the_full_game() -> void:
	assert_eq(RunSetup.create(run, _options(RunOptions.List.STANDARD), 3, [0, 0, 7] as Array[int]), "")
	assert_eq(run.header.staging, "", "a mixed lobby is not staged")
	assert_eq(run.repair.list.kind, RepairList.Kind.STANDARD)


func test_a_later_joiner_never_changes_the_level() -> void:
	assert_eq(RunSetup.create(run, _options(RunOptions.List.STANDARD), 1, [0] as Array[int]), "")
	var staged: String = run.header.staging
	var draw: PackedStringArray = run.header.draw.duplicate()
	var jobs: Array[StringName] = run.repair.list.jobs.duplicate()
	var flags: Dictionary = run.header.rule_flags.duplicate()
	assert_eq(staged, "1")
	# An Old Hand joins the run in progress.
	var old_hand: ClientConnection = ClientConnection.new(InProcessTransport.new(hub))
	old_hand.identity = "old_hand"
	old_hand.new_brigade_runs = 40
	old_hand.candidates = [{"id": 1, "name": "Tom Pike", "lamp_number": 512, "voice_id": 3, "book_pages": []}] as Array[Dictionary]
	assert_true(old_hand.start("server", 1))
	for _i: int in 8:
		old_hand.poll()
		run.run_tick()
	old_hand.poll()
	assert_eq(old_hand.state, ClientConnection.State.CONNECTED)
	assert_eq(net.crew.of_slot(old_hand.welcome.slot).brigade_runs, 40, "the joiner's runs were heard")
	assert_eq(run.header.staging, staged, "the staging never changes after creation")
	assert_eq(run.header.draw, draw, "nor the draw")
	assert_eq(run.repair.list.jobs, jobs, "nor the list")
	assert_eq(run.header.rule_flags, flags, "nor the rule flags")
	assert_eq(run.header.humans_at_start, 1)

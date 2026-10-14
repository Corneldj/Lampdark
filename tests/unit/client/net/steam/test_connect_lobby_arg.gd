extends GutTest
## STM-02: Steam launches the game with `+connect_lobby <id>` for an invite accepted while it was
## closed; FND-03's parser hands it to the client, which joins after STM-01's init.


func test_parsed_into_the_client_config() -> void:
	var build: BuildInfo = BuildInfo.new()
	var a: LaunchArgs = LaunchArgs.parse(PackedStringArray(["+connect_lobby", "109775241234567890"]), PackedStringArray(), build)
	assert_true(a.ok, a.error)
	assert_eq(a.client.connect_lobby, "109775241234567890")
	assert_eq(a.client.connect_lobby.to_int(), 109775241234567890, "a full 64-bit lobby id")
	var bad: LaunchArgs = LaunchArgs.parse(PackedStringArray(["+connect_lobby"]), PackedStringArray(), build)
	assert_false(bad.ok, "an id is required")


func test_the_client_joins_it_after_steam() -> void:
	var src: String = FileAccess.get_file_as_string("res://client/client_main.gd")
	var steam_at: int = src.find("if not _start_steam():")
	var lobby_at: int = src.find("lobby.join(config.connect_lobby.to_int())")
	assert_gt(steam_at, 0)
	assert_gt(lobby_at, 0)
	assert_lt(steam_at, src.find("_start_lobby()"), "Steam first, then the lobby service, then the join")

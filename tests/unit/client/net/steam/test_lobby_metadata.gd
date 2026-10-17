extends GutTest
## STM-02's lobby and member data: every key written, this game and build, nothing about the seed,
## the draw, the staging level, the plan or a miner's state, and no address or port in a release build.

const FORBIDDEN: Array[String] = ["seed", "draw", "staging", "plan", "position", "health", "oil", "flame", "inventory", "miner_state"]


func before_all() -> void:
	assert_true(Tuning.load_client())


func test_every_key_and_this_build() -> void:
	var d: Dictionary = LobbyMetadata.lobby_data({}, LobbyMetadata.PITHEAD, "AB12CD", "10.0.0.5:24600", false)
	for key: String in LobbyMetadata.LOBBY_KEYS:
		assert_true(d.has(key), key)
	assert_eq(d.keys().size(), LobbyMetadata.LOBBY_KEYS.size(), "nothing else")
	assert_eq(str(d["lb_game"]), "lampblack")
	assert_eq(str(d["lb_build"]), Protocol.build_id())
	assert_eq(str(d["lb_proto"]), str(Protocol.PROTOCOL_VERSION))
	assert_eq(str(d["lb_list"]), "standard", "Standard by default")
	assert_eq(str(d["lb_hands"]), "0", "Hands off by default")
	assert_eq(str(d["lb_dev_addr"]), "10.0.0.5:24600", "dev, QA and kill-test builds")
	assert_true(LobbyMetadata.compatible(d))
	var other: Dictionary = d.duplicate()
	other["lb_build"] = "someone-else"
	assert_false(LobbyMetadata.compatible(other), "another build: Different version")
	other = d.duplicate()
	other["lb_game"] = "spacewar"
	assert_false(LobbyMetadata.compatible(other), "another game's lobby")


func test_release_writes_no_address_or_port() -> void:
	var d: Dictionary = LobbyMetadata.lobby_data({}, LobbyMetadata.RUNNING, "AB12CD", "10.0.0.5:24600", true)
	var all: String = JSON.stringify(d)
	assert_eq(str(d["lb_dev_addr"]), "")
	var ip: RegEx = RegEx.create_from_string("\\d+\\.\\d+\\.\\d+\\.\\d+|:\\d{2,5}\\b|\\[[0-9a-f:]+\\]")
	assert_null(ip.search(all), "no address or port anywhere: %s" % all)


func test_no_forbidden_content() -> void:
	var d: Dictionary = LobbyMetadata.lobby_data({"mode": "friends", "list": "full", "hard": "one_lamp", "hands": true}, LobbyMetadata.PITHEAD,
		"AB12CD", "", true, "4f1c", "")
	var m: Dictionary = LobbyMetadata.member_data(true, "Ann", 3, 2, false)
	for blob: Dictionary in [d, m]:
		for key: Variant in blob.keys():
			for word: String in FORBIDDEN:
				assert_false(str(key).contains(word), "%s carries no %s" % [key, word])
	assert_eq(m.keys().size(), LobbyMetadata.MEMBER_KEYS.size())
	for key: String in LobbyMetadata.MEMBER_KEYS:
		assert_true(m.has(key))
	assert_eq(LobbyMetadata.code_filters("AB12CD"), {"lb_game": "lampblack", "lb_build": Protocol.build_id(), "lb_code": "AB12CD"})

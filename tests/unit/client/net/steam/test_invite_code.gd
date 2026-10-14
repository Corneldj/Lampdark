extends GutTest
## STM-02's invite codes: net.invite_code_length Crockford base32 characters from a secure source;
## entry ignores case, spaces and dashes and reads O as 0, I and L as 1; the spread is even; a host
## redraws while a live lobby holds its code.

const R = preload("res://tests/unit/client/net/steam/lobby_rig.gd")


func before_all() -> void:
	assert_true(Tuning.load_client())


func test_alphabet_and_length() -> void:
	assert_eq(InviteCode.ALPHABET.length(), 32)
	for banned: String in ["I", "L", "O", "U"]:
		assert_false(InviteCode.ALPHABET.contains(banned), "no %s" % banned)
	assert_eq(InviteCode.size(), 6)
	for _i: int in 50:
		var c: String = InviteCode.generate()
		assert_eq(c.length(), 6)
		for ch: String in c:
			assert_true(InviteCode.ALPHABET.contains(ch))


func test_normalisation() -> void:
	assert_eq(InviteCode.normalise("ab12cd"), "AB12CD")
	assert_eq(InviteCode.normalise(" o1-il 2x "), "0111" + "2X", "O as 0, I and L as 1, spaces and dashes dropped")
	assert_eq(InviteCode.normalise("AB12C"), "", "too short")
	assert_eq(InviteCode.normalise("AB12CDE"), "", "too long")
	assert_eq(InviteCode.normalise("AB12CU"), "", "U is never in a code")
	assert_eq(InviteCode.normalise("AB12C!"), "")
	assert_eq(InviteCode.masked("AB12CD"), "••••••", "streamer mode")


func test_even_spread() -> void:
	var counts: Dictionary = {}
	var draws: int = 3200
	for _i: int in draws:
		for ch: String in InviteCode.generate():
			counts[ch] = Variants.whole(counts.get(ch, 0)) + 1
	assert_eq(counts.size(), 32, "every symbol appears")
	var expected: float = draws * 6 / 32.0
	var chi: float = 0.0
	for k: Variant in counts.keys():
		var d: float = float(Variants.number(counts[k])) - expected
		chi += d * d / expected
	gut.p("chi-square over 32 symbols: %.1f" % chi)
	assert_lt(chi, 70.0, "even (chi-square, 31 degrees of freedom, p < 0.0002 to fail)")
	assert_eq(InviteCode.generate(PackedByteArray([0, 1, 31, 32, 63, 255])), "01Z0ZZ", "five low bits per byte")


func test_a_host_redraws_while_a_live_lobby_holds_the_code() -> void:
	var rig: R.Rig = R.make(self)
	var a: LobbyService = rig.client("ann")
	a.create()
	await rig.settle()
	var taken: String = a.code
	assert_eq(taken.length(), 6)
	var b: LobbyService = rig.client("bo")
	var draws: Array[String] = []
	b.backend.search_done.connect(func(_ids: PackedInt64Array) -> void: draws.append(b.code))
	R.force_codes(b, [taken, taken])
	b.create()
	await rig.settle()
	assert_eq(b.state, LobbyService.State.IN_LOBBY)
	assert_ne(b.code, taken, "redrawn: no two live lobbies share a code")
	assert_eq(draws.size(), 3, "two clashes, then a free code")

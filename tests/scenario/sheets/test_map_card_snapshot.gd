extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-14: the map card (Gameplay §12.7; GDD §14.3). At the cage's departure (LFT-10) or a wipe
## (LFT-11) the sheet freezes: nothing more is drawn, every client, the fallen too, is sent all of
## it and its digest, and each draws the same card, byte for byte, apart from what filtering and
## blocks change. The card adds nothing of its own: no names, SteamIDs or lobby codes. The player
## may keep it as user://map_cards/<run_uuid>.png and in Steam's screenshot library.

const T = preload("res://tests/scenario/sheets/table_world.gd")
const FakeSteam = preload("res://tests/unit/client/net/steam/fake_steam_api.gd")
const CARD_PX: int = 384


func before_all() -> void:
	assert_true(Tuning.load_server())


func _draw_a_map(s: Scenario, ann: MinerHandle, bob: MinerHandle) -> void:
	T.draw(ann, T.line(Vector2(-900, 0), Vector2(900, 0), 18))
	T.draw(ann, T.line(Vector2(0, -900), Vector2(0, 900), 18))
	ann.connection.sheet.commit_label(Vector2(200, -300), "Here be the Stythe", Transport.now_usec())
	T.draw(bob, T.line(Vector2(-600, 600), Vector2(600, 600), 12))
	T.draw(bob, PackedVector2Array([Vector2(300, 300)]))
	s.step(10)


func _until_cards(s: Scenario, hs: Array[MinerHandle]) -> bool:
	var ready: Callable = func(_sc: Scenario) -> bool:
		for h: MinerHandle in hs:
			if not h.connection.sheet.card_ready():
				return false
		return true
	return s.run_until(ready, 200)


func test_every_client_draws_the_same_card_of_the_frozen_sheet() -> void:
	var s: Scenario = T.camp(1801, self)
	var ann: MinerHandle = T.walk_up(s, "ann")
	var bob: MinerHandle = T.walk_up(s, "bob", 1)
	var deck: Vector2i = Basecamp.fixture(T.C.SEED, "cage_deck", s.run.base_camp.side)[0]["position"]
	var cat: MinerHandle = s.add_miner("cat", deck)
	var dan: MinerHandle = s.add_miner("dan", deck + Vector2i(1, 0))
	assert_true(s.run.falls.fall_unconscious(s.run, dan.entity_id, FallCause.Cause.ROOF_FALL))
	s.step(3)
	_draw_a_map(s, ann, bob)
	assert_eq(dan.connection.sheet.sheet.count(), 0, "Dan, unconscious, was sent nothing")
	s.run.sheets.table.freeze(s.run, "cage_departed")
	T.send_raw(ann, SheetCodec.commit_stroke(99, T.line(Vector2(0, 2000), Vector2(500, 2000), 5)))
	var hs: Array[MinerHandle] = [ann, bob, cat, dan]
	assert_true(_until_cards(s, hs), "every client holds the frozen sheet")
	assert_true(T.refused_whys(s).has("frozen"), "nothing more is drawn")
	var digest: int = s.run.sheets.table.sheet.digest()
	var first: PackedByteArray = PackedByteArray()
	for h: MinerHandle in hs:
		var held: int = h.connection.sheet.frozen["digest"]
		assert_eq(held, digest, "%s: the server's sheet" % h.name)
		assert_eq(str(h.connection.sheet.frozen["run_uuid"]), s.run.header.run_uuid)
		var png: PackedByteArray = MapCard.render(h.connection.sheet, CARD_PX).save_png_to_buffer()
		if first.is_empty():
			first = png
		assert_true(png == first, "%s draws the same card, byte for byte" % h.name)
	var image: Image = MapCard.render(ann.connection.sheet, CARD_PX)
	assert_eq(image.get_size(), Vector2i(CARD_PX, CARD_PX))
	var inked: int = 0
	for y: int in range(0, CARD_PX, 2):
		for x: int in range(0, CARD_PX, 2):
			inked += 1 if image.get_pixel(x, y).v < 0.5 else 0
	assert_gt(inked, 100, "pencil on the paper")


func test_the_card_adds_nothing_and_differs_only_by_filter_and_blocks() -> void:
	var s: Scenario = T.camp(1802, self, ServerConfig.Mode.PUBLIC)
	var ann: MinerHandle = T.walk_up(s, "ann")
	var bob: MinerHandle = T.walk_up(s, "bob", 1)
	var cid: MinerHandle = T.at_table(s, "cid", 2)
	s.run.sheets.sync.blocks_of = func(slot: int) -> Array: return ["ann"] if slot == cid.slot else []
	s.step(2)
	_draw_a_map(s, ann, bob)
	var authors: Array[String] = []
	bob.connection.sheet.filter = func(text: String, author: String) -> String:
		authors.append(author)
		return text.to_upper()
	s.run.sheets.table.freeze(s.run, "wipe")
	var hs: Array[MinerHandle] = [ann, bob, cid]
	assert_true(_until_cards(s, hs))
	var ann_card: PackedByteArray = MapCard.render(ann.connection.sheet, CARD_PX).save_png_to_buffer()
	var bob_card: PackedByteArray = MapCard.render(bob.connection.sheet, CARD_PX).save_png_to_buffer()
	assert_true(authors.has("ann"), "Bob's card passed Ann's label through the filter")
	assert_false(bob_card == ann_card, "filtered, Bob's label reads otherwise")
	# Cid blocks Ann: his frozen sheet, and his card, have nothing of hers.
	assert_eq(cid.connection.sheet.sheet.count(), 2, "only Bob's line and dot")
	var bobs_only: ClientSheet = ClientSheet.new()
	for raw: Variant in bob.connection.sheet.sheet.strokes.keys():
		var st: SheetStroke = bob.connection.sheet.sheet.strokes[raw]
		if st.points[0].y >= 300:
			bobs_only.sheet.add_stroke(st)
	var cid_card: PackedByteArray = MapCard.render(cid.connection.sheet, CARD_PX).save_png_to_buffer()
	assert_true(cid_card == MapCard.render(bobs_only, CARD_PX).save_png_to_buffer(), "the card of the sheet without Ann's")
	# The card carries pixels only: no text, date or metadata chunk where a name or code could ride.
	for card: PackedByteArray in [ann_card, bob_card, cid_card]:
		var chunks: Array[String] = _chunk_types(card)
		assert_true(chunks.has("IDAT"))
		for chunk: String in chunks:
			assert_false(chunk in ["tEXt", "zTXt", "iTXt", "eXIf", "tIME"], "a %s chunk in the card" % chunk)


## The PNG's chunk types, in order.
func _chunk_types(png: PackedByteArray) -> Array[String]:
	var out: Array[String] = []
	var at: int = 8
	while at + 8 <= png.size():
		var length: int = (png[at] << 24) | (png[at + 1] << 16) | (png[at + 2] << 8) | png[at + 3]
		out.append(png.slice(at + 4, at + 8).get_string_from_ascii())
		at += 12 + length
	return out


func test_the_card_is_kept_by_choice_on_disk_and_in_steam() -> void:
	var cs: ClientSheet = ClientSheet.new()
	cs.sheet.add_stroke(SheetStroke.make(1, -1, PackedVector2Array([Vector2(0, 0), Vector2(100, 50)])))
	var image: Image = MapCard.render(cs, 128)
	var uuid: String = "test-card-%d" % Time.get_ticks_usec()
	var path: String = MapCard.save(image, uuid)
	assert_eq(path, "user://map_cards/%s.png" % uuid)
	assert_true(FileAccess.file_exists(path))
	var back: Image = Image.load_from_file(path)
	assert_eq(back.get_size(), Vector2i(128, 128))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	assert_eq(MapCard.save(image, "../escape"), "", "a run uuid is a file name, nothing else")
	var steam: SteamApi = FakeSteam.new()
	steam.init(0)
	assert_true(MapCard.to_steam_library(steam, path, image))
	var fake: Object = steam
	var shots: Array = fake.get(&"screenshots")
	assert_eq(shots.size(), 1, "into the screenshot library")
	assert_false(MapCard.to_steam_library(null, path, image), "without Steam, the file only")

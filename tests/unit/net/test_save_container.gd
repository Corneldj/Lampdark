extends "res://tests/scenario/kit/scenario_test.gd"
## NET-09's save container and seal: a container opens to the header and sections it was built from;
## one changed byte in any section fails its seal and the whole save is refused; a truncated or
## foreign file is no save. Seeds and stream states never appear outside the sealed sections, in
## the file or in anything sent to a member, and no client code opens a save.

const S = preload("res://tests/scenario/net/save_world.gd")

const HEADER: Dictionary = {"run_uuid": "u-1", "seq": 3, "parent_hash": "ab", "kind": "snapshot", "build": "b",
	"generator": "none", "templates": "none", "bundle": "x", "mode": 0}


func before_all() -> void:
	assert_true(Tuning.load_server())


func _sections() -> Dictionary:
	var big: PackedByteArray = PackedByteArray()
	for i: int in 5000:
		big.append(i % 7)
	return {"run": var_to_bytes({"run_seed": 77}), "state": big, "empty": PackedByteArray()}


func test_a_container_opens_to_what_it_was_built_from() -> void:
	var bytes: PackedByteArray = SaveContainer.build(HEADER, _sections())
	assert_eq(bytes.slice(0, 4), SaveContainer.MAGIC)
	var opened: Dictionary = SaveContainer.open(bytes)
	assert_true(Variants.flag(opened["ok"]))
	assert_eq(Variants.dict(opened["header"]), HEADER)
	var got: Dictionary = opened["sections"]
	var want: Dictionary = _sections()
	for raw: Variant in want.keys():
		var a: PackedByteArray = got.get(raw, PackedByteArray([1]))
		var b: PackedByteArray = want[raw]
		assert_true(a == b, "section %s round-trips" % str(raw))
	assert_eq(SaveContainer.read_header(bytes), HEADER, "the plain header, nothing opened")
	var sizes: Dictionary = SaveContainer.sizes(bytes)
	assert_eq(int(Variants.number(sizes["total"])), bytes.size())


func test_the_seal_refuses_any_change() -> void:
	var plain: PackedByteArray = "a lamp at the grab point".to_utf8_buffer()
	var sealed: PackedByteArray = LbSeal.seal(plain)
	assert_true(LbSeal.verify(sealed))
	assert_eq(LbSeal.open(sealed), plain)
	assert_false(sealed == LbSeal.seal(plain), "a fresh IV each time")
	for at: int in [0, 16, sealed.size() / 2, sealed.size() - 1]:
		var bad: PackedByteArray = sealed.duplicate()
		bad[at] = bad[at] ^ 0x01
		assert_false(LbSeal.verify(bad), "byte %d changed: refused" % at)
		assert_true(LbSeal.open(bad).is_empty())
	assert_true(LbSeal.open(sealed.slice(0, 20)).is_empty(), "too short to be sealed")


func test_a_tampered_save_is_refused() -> void:
	var bytes: PackedByteArray = SaveContainer.build(HEADER, _sections())
	var bad: PackedByteArray = bytes.duplicate()
	bad[bad.size() - 40] = bad[bad.size() - 40] ^ 0x20
	var opened: Dictionary = SaveContainer.open(bad)
	assert_false(Variants.flag(opened["ok"]))
	assert_eq(str(opened["error"]), "seal")
	assert_true(Variants.dict(opened["sections"]).is_empty(), "nothing of it is used")
	var path: String = "user://net09_unit/tampered/snapshot.lmpb"
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(bad)
	f.close()
	var r: Dictionary = SaveResume.open_file(path)
	assert_false(Variants.flag(r["ok"]))
	assert_eq(str(r["error"]), SaveResume.ERR_SEAL)
	gut.p("refused: %s" % str(r["message"]))


func test_a_truncated_or_foreign_file_is_no_save() -> void:
	var bytes: PackedByteArray = SaveContainer.build(HEADER, _sections())
	for cut: int in [3, 12, bytes.size() / 2, bytes.size() - 1]:
		assert_eq(str(SaveContainer.open(bytes.slice(0, cut))["error"]), "format", "cut at %d" % cut)
	var longer: PackedByteArray = bytes.duplicate()
	longer.append(0)
	assert_eq(str(SaveContainer.open(longer)["error"]), "format", "trailing bytes")
	var foreign: PackedByteArray = bytes.duplicate()
	foreign[0] = 0x58
	assert_eq(str(SaveContainer.open(foreign)["error"]), "format", "another magic")
	assert_eq(SaveContainer.read_header(foreign), {})


func test_a_member_assembles_the_same_file_from_the_parts() -> void:
	var sealed: Dictionary = {}
	var want: Dictionary = _sections()
	for raw: Variant in want.keys():
		var plain: PackedByteArray = want[raw]
		sealed[raw] = SaveContainer.seal_section(plain)
	var order: PackedStringArray = PackedStringArray(["empty", "run", "state"])
	var a: PackedByteArray = SaveContainer.assemble(HEADER, sealed, order)
	var store: SaveStore = SaveStore.new()
	store.root = "user://net09_unit/member"
	var payload: PackedByteArray = SaveWire.save_data("u-1", 3, HEADER, order, sealed)
	assert_eq(store.on_save_data(payload), 3, "acknowledged")
	assert_true(FileAccess.get_file_as_bytes(store.path_of("u-1")) == a, "the member's file is the server's")
	assert_eq(store.on_save_data(payload.slice(0, payload.size() - 3)), -1, "a malformed message is dropped")


func test_seeds_and_streams_stay_inside_the_sealed_sections() -> void:
	# A long seed: a short one's decimal digits turn up by chance in the plain bundle hash.
	S.clear(941941941941)
	var s: Scenario = make(S.cfg(941941941941))
	var ann: MinerHandle = S.miner(s, "ann", Vector2i(3, 3))
	S.miner(s, "bob", Vector2i(8, 3))
	s.step(10)
	assert_true(s.run.falls.fall_unconscious(s.run, ann.entity_id, FallCause.Cause.ROOF_FALL))
	assert_true(S.until_saved(s, 1))
	s.step(10)
	s.run.saves.flush()
	var secrets: Array[PackedByteArray] = []
	var seed_bytes: PackedByteArray = PackedByteArray()
	seed_bytes.resize(8)
	seed_bytes.encode_s64(0, s.run.header.run_seed)
	secrets.append(seed_bytes)
	secrets.append(str(s.run.header.run_seed).to_utf8_buffer())
	var streams: Dictionary = s.run.stream_states()
	assert_false(streams.is_empty())
	for raw: Variant in streams.values():
		var b: PackedByteArray = PackedByteArray()
		b.resize(8)
		b.encode_s64(0, Variants.whole(raw))
		secrets.append(b)
	var header: Dictionary = SaveContainer.read_header(FileAccess.get_file_as_bytes(S.snapshot_path(s)))
	var keys: Array = header.keys()
	keys.sort()
	assert_eq(keys, ["build", "bundle", "deepest", "generator", "kind", "list", "mode", "parent_hash", "run_time_s", "run_uuid", "seq", "templates"],
		"the plain header holds versions and chain fields only, and MOD-05's resume line")
	var blobs: Array[PackedByteArray] = [FileAccess.get_file_as_bytes(S.snapshot_path(s)),
		FileAccess.get_file_as_bytes(s.run.saves.run_dir().path_join(Saves.JOURNAL_FILE))]
	for h: MinerHandle in s.miners:
		for m: Dictionary in h.capture.messages:
			var t: int = int(Variants.number(m["type"]))
			if t == Protocol.Msg.SAVE_DATA or t == Protocol.Msg.JOURNAL:
				var raw_bytes: PackedByteArray = m["bytes"]
				blobs.append(raw_bytes)
	assert_gt(blobs.size(), 3)
	var found: int = 0
	for blob: PackedByteArray in blobs:
		var hex: String = blob.hex_encode()
		for secret: PackedByteArray in secrets:
			if hex.contains(secret.hex_encode()):
				found += 1
	assert_eq(found, 0, "no seed or stream state outside a sealed section")


## FND-03's layering: client code stores saves, never opens one.
func test_no_client_code_opens_a_save() -> void:
	var forbidden: Array[String] = ["LbSeal", "SaveContainer.open", "SaveResume", "Snapshot.", "Journal.", "Saves.read_journal"]
	var hits: Array[String] = []
	for path: String in _scripts("res://client"):
		var text: String = FileAccess.get_file_as_string(path)
		for word: String in forbidden:
			if text.contains(word):
				hits.append("%s: %s" % [path, word])
	assert_eq(hits, [] as Array[String])


func _scripts(dir: String) -> Array[String]:
	var out: Array[String] = []
	var d: DirAccess = DirAccess.open(dir)
	if d == null:
		return out
	for sub: String in d.get_directories():
		out.append_array(_scripts(dir.path_join(sub)))
	for f: String in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	return out

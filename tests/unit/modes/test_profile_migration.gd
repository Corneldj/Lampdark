extends GutTest
## MOD-01: save, load and migration from schema 1 round-trip without loss; fields a newer version
## wrote are kept; the store writes and reads the file, merges remote copies and survives a bad file.
## Never: a typed name, stats or items in the profile; nothing but name, number, badge and shown pages
## in what another client may see; no server code reads a profile.


func before_all() -> void:
	assert_true(Tuning.load_client())


func test_round_trip_and_schema_one() -> void:
	var p: Profile = Profile.create(76561198030964382, 99)
	p.preferred_badge = 4
	var ids: Array[int] = []
	for m: RosterMiner in p.state().roster:
		ids.append(m.id)
	p.send_below("r", ids[0], 1)
	p.apply_outcome("r", ids[0], OutcomeEvent.Outcome.DEAD, 2)
	p.hire(ids[0], 1, 3)
	var d: Dictionary = p.to_dict()
	d["future_field"] = {"kept": true}
	var reread: Dictionary = JSON.parse_string(JSON.stringify(d))
	var back: Profile = Profile.from_dict(reread)
	assert_eq(back.steam_id, 76561198030964382, "the 64-bit id survives JSON")
	var back_d: Dictionary = back.to_dict()
	assert_eq(JSON.stringify(back_d), JSON.stringify(d), "nothing lost, the unknown field kept")
	var v1: Dictionary = {"schema_version": 1, "steam_id": "42", "seed": "7", "miners": [
		{"id": 1, "name": NameDrawer.full(NameDrawer.period_names()[5]), "lamp": 114},
		{"id": 2, "name": NameDrawer.full(NameDrawer.period_names()[6]), "lamp": 207},
		{"id": 3, "name": NameDrawer.full(NameDrawer.period_names()[7]), "lamp": 131}],
		"outcomes": [{"run": "old", "miner": 2, "outcome": "left_below", "at": 5}], "theme": "dark"}
	var m: Profile = Profile.from_dict(v1)
	var s: Profile.State = m.state()
	assert_eq(s.roster.size(), 2, "the old Left Below stands")
	assert_eq(s.roster[0].lamp_number, 114)
	assert_eq(s.roster[0].full_name(), NameDrawer.full(NameDrawer.period_names()[5]))
	assert_eq(str(m.extra.get("theme", "")), "dark", "kept")
	assert_eq(int(Variants.number(m.to_dict()["schema_version"])), Profile.SCHEMA_VERSION)


func test_the_store() -> void:
	var store: ProfileStore = ProfileStore.new()
	store.dir = "user://test_profiles_mod01"
	DirAccess.make_dir_recursive_absolute(store.dir)
	var saved: Array[Dictionary] = []
	store.on_saved.append(func(d: Dictionary) -> void: saved.append(d))
	var p: Profile = store.load_or_create(555)
	assert_eq(saved.size(), 1, "a new profile is saved, and handed to the cloud hooks")
	var other: Profile = Profile.from_dict(p.to_dict())
	other.apply_outcome("elsewhere", other.state().roster[0].id, OutcomeEvent.Outcome.LEFT_BELOW, 9)
	store.remote_copies.append(func() -> Array: return [other.to_dict()])
	var merged: Profile = store.load_or_create(555)
	assert_eq(merged.state().roster.size(), 2, "the remote copy's death stands")
	var f: FileAccess = FileAccess.open(store.path_for(777), FileAccess.WRITE)
	f.store_string("{ not json")
	f.close()
	store.remote_copies.clear()
	var fresh: Profile = store.load_or_create(777)
	assert_eq(fresh.state().roster.size(), 3, "an unreadable file is set aside and a profile made")
	assert_true(FileAccess.file_exists(store.path_for(777) + ".unreadable"))
	for path: String in [store.path_for(555), store.path_for(777), store.path_for(777) + ".unreadable"]:
		DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(store.dir)


func test_never() -> void:
	var p: Profile = Profile.create(9, 9)
	var keys: Array = p.to_dict().keys()
	keys.sort()
	assert_eq(keys, ["events", "founding", "preferred_badge", "schema_version", "seed", "steam_id"], "no stats, items or currency")
	var miner: RosterMiner = p.state().roster[0]
	var shown: Array = miner.public_view(2).keys()
	shown.sort()
	assert_eq(shown, ["badge", "book_pages", "lamp_number", "name"], "all another client may see")
	for path: String in ["res://shared/profile/profile.gd", "res://shared/profile/name_drawer.gd", "res://client/profile/profile_store.gd"]:
		var text: String = FileAccess.get_file_as_string(path)
		assert_false(text.contains("LineEdit") or text.contains("TextEdit") or text.contains("set_name("), "no typed name: %s" % path)
	var server_files: Array[String] = []
	for f: String in _scripts("res://server"):
		var text: String = FileAccess.get_file_as_string(f)
		for cls: String in ["ProfileStore", "Profile.", "RosterMiner", "OutcomeEvent", "NameDrawer"]:
			if text.contains(cls):
				server_files.append("%s names %s" % [f, cls])
	assert_eq(server_files, [] as Array[String], "servers never read profile files")


func _scripts(dir: String) -> Array[String]:
	var out: Array[String] = []
	for f: String in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d: String in DirAccess.get_directories_at(dir):
		out.append_array(_scripts(dir.path_join(d)))
	return out

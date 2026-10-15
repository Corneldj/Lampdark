class_name ProfileStore
extends RefCounted
## MOD-01 (Proposed): the player's profile on this PC, keyed by SteamID64 (a few kB). It loads and
## saves with Steam offline and no backend (Night Shift). Other copies (Steam Cloud through STM-05,
## the backend's mirror through STM-10) come in through `remote_copies` and merge by union of the log;
## each save goes out through `on_saved`. A file that cannot be read is moved aside, never lost.

const DIR: String = "user://profiles"

## () -> Array of profile dictionaries from elsewhere (STM-05, STM-10). None until they land.
var remote_copies: Array[Callable] = []
## (profile dictionary) -> void after each local save (STM-05 and STM-10 upload it).
var on_saved: Array[Callable] = []
var dir: String = DIR


func path_for(steam_id: int) -> String:
	return dir.path_join("%d.json" % steam_id)


## The player's profile: the local copy merged with every remote one, or a new one.
func load_or_create(steam_id: int) -> Profile:
	var p: Profile = _read(path_for(steam_id))
	for source: Callable in remote_copies:
		for raw: Variant in Variants.array(source.call()):
			var other: Profile = Profile.from_dict(Variants.dict(raw))
			if other.steam_id != steam_id:
				continue
			if p == null:
				p = other
			else:
				p.merge(other)
	if p == null:
		var salt: int = Crypto.new().generate_random_bytes(8).decode_s64(0)
		p = Profile.create(steam_id, salt ^ steam_id)
		save(p)
	return p


func save(p: Profile) -> Error:
	DirAccess.make_dir_recursive_absolute(dir)
	var path: String = path_for(p.steam_id)
	var tmp: String = path + ".tmp"
	var f: FileAccess = FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	var d: Dictionary = p.to_dict()
	f.store_string(JSON.stringify(d, "\t"))
	f.close()
	var err: Error = DirAccess.rename_absolute(tmp, path)
	if err == OK:
		for hook: Callable in on_saved:
			hook.call(d)
	return err


func _read(path: String) -> Profile:
	if not FileAccess.file_exists(path):
		return null
	var json: JSON = JSON.new()
	var parsed: Variant = json.data if json.parse(FileAccess.get_file_as_string(path)) == OK else null
	if not parsed is Dictionary:
		DirAccess.rename_absolute(path, path + ".unreadable")
		Log.warn("profile: %s was unreadable; set aside" % path.get_file())
		return null
	var d: Dictionary = parsed
	return Profile.from_dict(d)

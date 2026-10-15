class_name SaveStore
extends RefCounted
## NET-09 (GDD §15.10): a member's copy of the run's saves. The server sends each snapshot's changed
## sections, sealed (SAVE_DATA, bulk lane), and every fall and death the tick it happens (JOURNAL,
## control lane). The client keeps them under <root>/<run UUID>/ for STM-05's Cloud sync and a
## resume from its copy, acknowledging each snapshot (SAVE_ACK). It never opens a sealed section or
## entry: it stores bytes and assembles the file from the parts it was given.

const SNAPSHOT_FILE: String = "snapshot.lmpb"
const JOURNAL_FILE: String = "journal.bin"

var root: String = "user://saves"
## The last snapshot stored: run UUID -> {seq, header, order, sections (name -> sealed bytes)}.
var runs: Dictionary = {}
## The journal entries stored: {uuid, bytes, at_usec}.
var journal_entries: Array[Dictionary] = []


## A SAVE_DATA payload: merged into the copy and written; the sequence number to acknowledge (-1:
## malformed).
func on_save_data(payload: PackedByteArray) -> int:
	var d: Dictionary = SaveWire.read_save_data(payload)
	if d.is_empty():
		return -1
	var uuid: String = d["uuid"]
	var r: Dictionary = runs.get(uuid, {"seq": 0, "header": {}, "order": PackedStringArray(), "sections": {}})
	var sections: Dictionary = r["sections"]
	var changed: Dictionary = d["changed"]
	for raw: Variant in changed.keys():
		sections[raw] = changed[raw]
	r["seq"] = d["seq"]
	r["header"] = d["header"]
	r["order"] = d["order"]
	runs[uuid] = r
	var order: PackedStringArray = r["order"]
	for n: String in order:
		if not sections.has(n):
			return -1  # a section never sent: not a whole copy yet
	var header: Dictionary = r["header"]
	_write_atomic(_dir(uuid).path_join(SNAPSHOT_FILE), SaveContainer.assemble(header, sections, order))
	return int(Variants.number(d["seq"]))


## A JOURNAL payload: appended to the copy's journal at once.
func on_journal(payload: PackedByteArray, now_usec: int) -> bool:
	var d: Dictionary = SaveWire.read_journal(payload)
	if d.is_empty():
		return false
	var entry: PackedByteArray = d["entry"]
	var path: String = _dir(str(d["uuid"])).path_join(JOURNAL_FILE)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f: FileAccess = FileAccess.open(path, FileAccess.READ_WRITE) if FileAccess.file_exists(path) else FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.seek_end()
	f.store_32(entry.size())
	f.store_buffer(entry)
	f.close()
	journal_entries.append({"uuid": d["uuid"], "bytes": entry, "at_usec": now_usec})
	return true


func path_of(uuid: String) -> String:
	return _dir(uuid).path_join(SNAPSHOT_FILE)


func _dir(uuid: String) -> String:
	return root.path_join(uuid.validate_filename())


static func _write_atomic(path: String, bytes: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var tmp: String = path + ".tmp"
	var f: FileAccess = FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_buffer(bytes)
	f.close()
	DirAccess.rename_absolute(tmp, path)

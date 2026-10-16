class_name MapTable
extends RefCounted
## LFT-14: the map table in base camp (Gameplay §12.7, §14.3), the crew's only map: one shared
## survey sheet, drawn only by miners at the table with its close-up open. It holds the sheet, who
## drew what (by identity, so a resume keeps it), and the sheet's copy in the diff log's run-level
## section (GEN-13: kept through knock-offs and resumes, gone with the run after Lamp Check). It
## never draws, snaps or updates anything itself: a road drawn open stays open after a fall until
## someone rubs it out (§8.1). At the cage's departure or a wipe the sheet freezes for the map card.
## Server-only.

signal frozen_now(cause: String)

## A stroke's record: "s<id>" -> author u16 and its blob; a label's: "l<id>" -> author u16,
## x s16, y s16, a length byte and its UTF-8; and the author table and next id under "meta".
const META: String = "meta"

var sheet: Sheet = Sheet.new()
## Identities (SteamIDs, or dev names) of everyone who has drawn, by author index.
var authors: PackedStringArray = PackedStringArray()
var next_id: int = 1
var frozen: bool = false
var frozen_tick: int = -1
var freeze_cause: String = ""
var _section: DiffLog.Section = null


func bind(run: RunState) -> void:
	if run.diff_log != null:
		_section = run.diff_log.run_section(DiffLog.MAP_TABLE)
		# Before every save and compaction: the next id, so a resume never reuses one.
		run.diff_log.on_refresh(func(_r: RunState) -> void: _keep_meta())


## The author index of `identity`, added to the table on first use.
func author_index(identity: String) -> int:
	var at: int = authors.find(identity)
	if at >= 0:
		return at
	authors.append(identity)
	_keep_meta()
	return authors.size() - 1


## The author index of `identity`, or -1 if they never drew.
func author_of(identity: String) -> int:
	return authors.find(identity)


func identity_of(author: int) -> String:
	return authors[author] if author >= 0 and author < authors.size() else ""


## A fresh id; ids are never reused within a run.
func take_id() -> int:
	var id: int = next_id
	next_id += 1
	return id


func at_cap() -> bool:
	return sheet.count() >= Tuning.i(&"mine.sheet_max_strokes")


func keep_stroke(s: SheetStroke) -> void:
	if _section == null:
		return
	var raw: PackedByteArray = PackedByteArray()
	raw.resize(2)
	raw.encode_u16(0, s.author)
	raw.append_array(s.encoded())
	_section.put_raw("s%d" % s.id, raw)


func keep_label(l: SheetLabel) -> void:
	if _section == null:
		return
	var raw: PackedByteArray = PackedByteArray()
	raw.resize(6)
	raw.encode_u16(0, l.author)
	raw.encode_s16(2, int(l.anchor.x))
	raw.encode_s16(4, int(l.anchor.y))
	var text: PackedByteArray = l.text.to_utf8_buffer()
	raw.append(text.size())
	raw.append_array(text)
	_section.put_raw("l%d" % l.id, raw)


func forget(id: int) -> void:
	if _section != null and not _section.erase("s%d" % id):
		_section.erase("l%d" % id)


## Rebuilds the sheet from the diff log's section (NET-09's resume, after the log is restored).
func load_from_section() -> void:
	sheet.clear()
	authors = PackedStringArray()
	next_id = 1
	if _section == null:
		return
	var meta: Dictionary = _section.get_payload(META)
	authors = PackedStringArray(Variants.array(meta.get("authors", [])))
	next_id = maxi(1, int(Variants.number(meta.get("next_id", 1))))
	for key: String in _section.keys():
		if key == META or key.length() < 2:
			continue
		var id: int = key.substr(1).to_int()
		var raw: PackedByteArray = _section.get_raw(key)
		if key.begins_with("s") and raw.size() > 2:
			var r: Array = SheetStroke.decode(raw, 2)
			if not r.is_empty():
				var points: PackedVector2Array = r[0]
				sheet.add_stroke(SheetStroke.make(id, raw.decode_u16(0), points))
		elif key.begins_with("l") and raw.size() >= 7:
			var n: int = raw[6]
			var text: String = raw.slice(7, 7 + n).get_string_from_utf8()
			sheet.add_label(SheetLabel.make(id, raw.decode_u16(0), Vector2(raw.decode_s16(2), raw.decode_s16(4)), text))
		next_id = maxi(next_id, id + 1)


## The sheet as the cage left it (LFT-10's departure) or at a wipe (LFT-11): nothing more is drawn
## and every client is sent all of it for the map card.
func freeze(run: RunState, cause: String) -> void:
	if frozen:
		return
	frozen = true
	frozen_tick = run.tick
	freeze_cause = cause
	_keep_meta()
	Log.info("map table frozen (%s) at tick %d: %d strokes and labels" % [cause, run.tick, sheet.count()])
	frozen_now.emit(cause)


func _keep_meta() -> void:
	if _section != null:
		_section.put(META, {"authors": Array(authors), "next_id": next_id})

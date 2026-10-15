class_name RosterMiner
extends RefCounted
## MOD-01 (Gameplay §13.2): one named miner of a player's roster: a period name from the list (never
## typed), a lamp number for life, a character voice, and their Pocket Book's pages. While a run that
## holds them is unfinished they are Below and cannot be sent again; a miner who dies or is Left
## Below leaves the roster for good.

var id: int = 0
var given: String = ""
var surname: String = ""
var woman: bool = false
var lamp_number: int = 0
## SND-13's character voice, 0-7: by default from the name, changeable at the Pithead.
var voice_id: int = 0
## MOD-02's creature pages, by id.
var book_pages: Array[String] = []
## Derived by Profile.state(): the unfinished run that holds them ("" when Available), and why they
## left ("" while on the roster).
var below_run: String = ""
var left: String = ""


static func make(miner_id: int, name: Dictionary, lamp: int) -> RosterMiner:
	var m: RosterMiner = RosterMiner.new()
	m.id = miner_id
	m.given = str(name.get("given", ""))
	m.surname = str(name.get("surname", ""))
	m.woman = Variants.flag(name.get("woman", false))
	m.lamp_number = lamp
	m.voice_id = VoiceChoice.default_for(m.full_name())
	return m


func full_name() -> String:
	return "%s %s" % [given, surname]


func available() -> bool:
	return below_run.is_empty() and left.is_empty()


## What another client may know of this miner (seated: MOD-03, NET-08's lobby audit): the name, the
## lamp number, the badge and the pages shown. Never anything else of the profile.
func public_view(badge: int) -> Dictionary:
	return {"name": full_name(), "lamp_number": lamp_number, "badge": badge, "book_pages": book_pages.duplicate()}


func to_dict() -> Dictionary:
	return {"id": id, "given": given, "surname": surname, "woman": woman, "lamp_number": lamp_number, "voice_id": voice_id,
		"book_pages": book_pages.duplicate()}


static func from_dict(d: Dictionary) -> RosterMiner:
	var m: RosterMiner = RosterMiner.new()
	m.id = int(Variants.number(d.get("id", 0)))
	m.given = str(d.get("given", ""))
	m.surname = str(d.get("surname", ""))
	m.woman = Variants.flag(d.get("woman", false))
	m.lamp_number = int(Variants.number(d.get("lamp_number", 0)))
	m.voice_id = int(Variants.number(d.get("voice_id", VoiceChoice.default_for(m.full_name()))))
	for p: Variant in Variants.array(d.get("book_pages", [])):
		m.book_pages.append(str(p))
	return m

class_name SheetLabel
extends RefCounted
## LFT-14: one typed label on a sheet: one line, one size, horizontal, in a pencil hand (plain
## type with that option); its anchor is the left end of the line, at its middle. It counts as one
## stroke toward mine.sheet_max_strokes and the rubber takes it whole.

var id: int = 0
## Server only: the author's index; -1 on a client.
var author: int = -1
## Client only, public lobbies only: the author's SteamID for STM-08's FilterText; never shown.
var author_identity: String = ""
var anchor: Vector2 = Vector2.ZERO
var text: String = ""


static func make(label_id: int, by: int, at: Vector2, words: String) -> SheetLabel:
	var l: SheetLabel = SheetLabel.new()
	l.id = label_id
	l.author = by
	l.anchor = at
	l.text = words
	return l


func rect() -> Rect2:
	return SheetOps.label_rect(anchor, text)

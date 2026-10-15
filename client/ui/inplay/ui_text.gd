class_name UiText
extends RefCounted
## UI-01: the in-play elements' text, by key only (data/text/*.json until UI-07's translations). An
## unknown key shows nothing, never itself: no free text reaches the screen. STM-01's Steam failure
## screen and streamer-mode names, and STM-02's dev lobby, read it too.

const FILES: Array[String] = ["res://data/text/ui_inplay.json", "res://data/text/verbs.json", "res://data/text/items.json",
	"res://data/text/captions_feel.json", "res://data/text/callouts/en.json", "res://data/text/steam.json",
	"res://data/text/lobby.json", "res://data/text/closeups.json", "res://data/text/captions.json"]

static var _strings: Dictionary = {}


static func text(key: String) -> String:
	if _strings.is_empty():
		for path: String in FILES:
			if FileAccess.file_exists(path):
				var doc: Dictionary = Variants.dict(JSON.parse_string(FileAccess.get_file_as_string(path)))
				_strings.merge(Variants.dict(doc.get("strings", {})))
	return str(_strings.get(key, ""))


## Every key the in-play elements may show (the content lint reads them).
static func keys() -> Array[String]:
	text("")
	var out: Array[String] = []
	for k: Variant in _strings.keys():
		out.append(str(k))
	return out

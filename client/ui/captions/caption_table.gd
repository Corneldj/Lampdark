class_name CaptionTable
extends RefCounted
## UI-03: every sound type's caption kind and text key (data/text/captions.json): SND-02's NoiseTypes
## as caption.noise.<id> and SND-03's LocalSounds as caption.local.<id>. A record flagged diffuse is
## always a diffuse tell (no direction), and takes the type's .diffuse text when it has one (taps in
## the rock: '[taps in the rock]'). Text goes through UiText; nothing here carries a distance.

enum Kind { POSITIONAL = 0, DIFFUSE = 1, VOICE = 2, CALLOUT = 3, SILENCE = 4 }

const PATH: String = "res://data/text/captions.json"
const KINDS: Dictionary = {"positional": Kind.POSITIONAL, "diffuse": Kind.DIFFUSE, "voice": Kind.VOICE, "callout": Kind.CALLOUT,
	"silence": Kind.SILENCE}

static var _kinds: Dictionary = {}


## The catalogue id of a played type ("rock_tap", "moth_stir"), or "".
static func id_of(type: int) -> String:
	if LocalSounds.is_local(type):
		return LocalSounds.id_of(type)
	return NoiseTypes.id_of(type as NoiseTypes.Type) if NoiseTypes.Type.values().has(type) else ""


static func has(type: int) -> bool:
	_load()
	return _kinds.has(id_of(type))


static func kind_of(type: int, flags: int = 0) -> Kind:
	_load()
	if (flags & AudioRecord.DIFFUSE) != 0:
		return Kind.DIFFUSE
	var name: String = str(_kinds.get(id_of(type), "positional"))
	var k: int = KINDS.get(name, Kind.POSITIONAL)
	return k as Kind


static func key_of(type: int, flags: int = 0) -> String:
	var id: String = id_of(type)
	if id.is_empty():
		return ""
	var key: String = ("caption.local." if LocalSounds.is_local(type) else "caption.noise.") + id
	if (flags & AudioRecord.DIFFUSE) != 0 and not UiText.text(key + ".diffuse").is_empty():
		return key + ".diffuse"
	return key


static func _load() -> void:
	if not _kinds.is_empty():
		return
	var doc: Dictionary = Variants.dict(JSON.parse_string(FileAccess.get_file_as_string(PATH)))
	_kinds = Variants.dict(doc.get("kinds", {}))

class_name NoiseCatalogue
extends RefCounted
## SND-02's catalogue of every sound the mine can make, read from data/sound/noise_catalogue.json
## with each entry's level, rate and duration from tuning, and its struck flag from CRT-12's
## classification (tapper.deaf_struck_kinds / tapper.deaf_not_struck_kinds). Server-only.

const PATH: String = "res://data/sound/noise_catalogue.json"
const TICK_HZ: float = 20.0


class Entry:
	extends RefCounted
	var type: NoiseTypes.Type = NoiseTypes.Type.NONE
	var id: String = ""
	## 0 for voice and callouts, whose level comes with each emission (their band's np).
	var np: float = 0.0
	var np_key: String = ""
	## Ticks between a periodic emitter's events; 0 for a one-shot.
	var rate_ticks: int = 0
	var rate_key: String = ""
	var duration_s: float = 0.5
	var struck: bool = false
	var vocal: bool = false
	var category: String = ""
	var caption: String = ""
	var sample: String = ""
	var owner: String = ""
	var source: String = ""


var entries: Dictionary = {}
## Catalogue ids classified neither struck nor not struck (must stay empty).
var unclassified: PackedStringArray = PackedStringArray()
var silent: PackedStringArray = PackedStringArray()
var not_events: PackedStringArray = PackedStringArray()


static func load_default() -> NoiseCatalogue:
	var catalogue: NoiseCatalogue = NoiseCatalogue.new()
	catalogue._load(Variants.dict(JSON.parse_string(FileAccess.get_file_as_string(PATH))))
	return catalogue


func entry(type: NoiseTypes.Type) -> Entry:
	if not entries.has(type):
		return null
	var e: Entry = entries[type]
	return e


func _load(doc: Dictionary) -> void:
	var struck: Array[String] = Tuning.list_s(&"tapper.deaf_struck_kinds")
	var not_struck: Array[String] = Tuning.list_s(&"tapper.deaf_not_struck_kinds")
	var default_duration: float = Tuning.f(&"noise.event_duration_s")
	for raw: Variant in Variants.array(doc.get("types", [])):
		var d: Dictionary = Variants.dict(raw)
		var e: Entry = Entry.new()
		e.id = str(d.get("id", ""))
		e.type = NoiseTypes.from_id(e.id)
		if e.type == NoiseTypes.Type.NONE:
			push_error("NoiseCatalogue: '%s' has no NoiseTypes id" % e.id)
			continue
		e.np_key = str(d.get("np_key", ""))
		e.np = Tuning.f(StringName(e.np_key)) if not e.np_key.is_empty() else 0.0
		e.rate_key = str(d.get("rate_key", ""))
		if not e.rate_key.is_empty():
			e.rate_ticks = maxi(1, roundi(Tuning.f(StringName(e.rate_key)) * TICK_HZ))
		var duration_key: String = str(d.get("duration_key", ""))
		if not duration_key.is_empty():
			e.duration_s = Tuning.f(StringName(duration_key))
		elif e.rate_ticks > 0:
			e.duration_s = e.rate_ticks / TICK_HZ
		else:
			e.duration_s = default_duration
		e.vocal = Variants.flag(d.get("vocal", false))
		e.struck = struck.has(e.id)
		if e.struck == not_struck.has(e.id):
			unclassified.append(e.id)
		e.category = str(d.get("category", ""))
		e.caption = str(d.get("caption", ""))
		e.sample = str(d.get("sample", ""))
		e.owner = str(d.get("owner", ""))
		e.source = str(d.get("source", ""))
		entries[e.type] = e
	for raw: Variant in Variants.array(doc.get("silent", [])):
		silent.append(str(Variants.dict(raw).get("id", "")))
	for raw: Variant in Variants.array(doc.get("not_road_graph_events", [])):
		not_events.append(str(Variants.dict(raw).get("id", "")))

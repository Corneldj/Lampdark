class_name AmbientBeds
extends Node
## SND-03 (GDD §14.2): silence is a sound. The mine's quiet bed (drips, timber, air, seam) always plays
## below everything, never a drone or a stinger, so its stopping is an event; base camp's bed (the
## emergency lamps' hum, the shaft's draught) plays while the server says the miner is inside. Layers
## change only on AmbientCues from the server (base camp, DIR-02's cooling seam, MNR-11's silent
## canary): nothing stops by itself. Each start and end raises `silence_caption` for UI-03.

signal silence_caption(layer: StringName, start: bool)

const MINE_LAYERS: Array[StringName] = [&"drips", &"timber", &"air", &"seam"]
const BASE_CAMP_LAYERS: Array[StringName] = [&"hum", &"draught"]

## layer -> AudioStreamPlayer
var players: Dictionary = {}
## SND-04: the deafened dip on every bed (0 when hearing), dB.
var dip_db: float = 0.0


func _ready() -> void:
	for layer: StringName in MINE_LAYERS:
		_start(layer, false)


func playing(layer: StringName) -> bool:
	return players.has(layer)


## One server cue: {layer, start, fade_s}. `base_camp` stands for its two layers.
func apply(cue: Dictionary) -> void:
	var layer: StringName = StringName(str(cue.get("layer", "")))
	var start: bool = Variants.flag(cue.get("start", false))
	var layers: Array[StringName] = BASE_CAMP_LAYERS if layer == AmbientMessages.BASE_CAMP else ([layer] as Array[StringName])
	for l: StringName in layers:
		if start:
			_start(l, true)
		else:
			_stop(l)
	silence_caption.emit(layer, start)


func _start(layer: StringName, _cued: bool) -> void:
	if players.has(layer):
		return
	var p: AudioStreamPlayer = AudioStreamPlayer.new()
	p.stream = SampleBank.bed(str(layer))
	p.bus = "Ambience"
	p.volume_db = Tuning.f(&"noise.bed_volume_db") + dip_db
	add_child(p)
	if is_inside_tree():
		p.play()
	players[layer] = p


## SND-04: dips every bed (deafened), or lifts the dip (0).
func set_dip_db(db: float) -> void:
	dip_db = db
	for raw: Variant in players.values():
		var p: AudioStreamPlayer = raw
		p.volume_db = Tuning.f(&"noise.bed_volume_db") + dip_db


func _stop(layer: StringName) -> void:
	if not players.has(layer):
		return
	var p: AudioStreamPlayer = players[layer]
	players.erase(layer)
	p.queue_free()

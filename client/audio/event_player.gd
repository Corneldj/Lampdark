class_name EventPlayer
extends Node
## SND-03: plays exactly the sounds the server delivered to this client, from the record's position
## or points (it derives no other), at the level that arrived:
##   gain_db = -noise.playback_edge_attenuation_db x (1 - remaining / level) + the masks' gain_db
## (a record at level 0 arrives at full delivered level). Muffled records go through the Muffled bus;
## diffuse tells through Tells (from their points, or noise.diffuse_emitter_count emitters 120 degrees
## apart at noise.diffuse_emitter_distance_tiles from the listener); local emitters through Ambience;
## vocal sounds through Voice. No added distance cue. At most noise.max_event_voices voices: the
## quietest is stolen first. Every played record raises `caption` for UI-03 (a diffuse one without a
## direction); a real record and an illusion with the same bytes play and caption identically.
## SND-04: every voice is a source in the native SpatialMixer, placed in tiles and heard by
## MinerListener's ears (which also set `listener`).

signal caption(type: int, direction: Variant)

## The one native mixer (SND-07's voice frames and SND-11's callouts play through it too).
var mixer: SpatialMixer = null
## Where the ears are, tiles (MinerListener sets it each frame).
var listener: Vector2 = Vector2.ZERO
## [source id, gain_db, at (tiles), bus, pitch, type] for each voice playing.
var voices: Array[Array] = []
## VIS-08's sputter: one looping source per guttering flame the client holds (no event of its own).
var sputter_voices: Array[int] = []
var sputter_at: Array[Vector2] = []


func _init(spatial: SpatialMixer = null) -> void:
	mixer = spatial
	if mixer == null:
		mixer = SpatialMixer.new()
		mixer.name = "SpatialMixer"
		add_child(mixer)


static func gain_db(record: AudioRecord) -> float:
	var edge: float = Tuning.f(&"noise.playback_edge_attenuation_db")
	var falloff: float = 0.0
	if record.level_np > 0.0:
		falloff = -edge * (1.0 - clampf(record.remaining_np / record.level_np, 0.0, 1.0))
	return falloff + record.gain_db


static func bus_for(record: AudioRecord) -> String:
	if (record.flags & AudioRecord.MUFFLED) != 0:
		return "Muffled"
	if (record.flags & AudioRecord.DIFFUSE) != 0:
		return "Tells"
	if (record.flags & AudioRecord.LOCAL) != 0:
		return "Ambience"
	if record.voice >= 0:
		return "Voice"
	return "Game"


## Where a record plays from: its points; a diffuse record without points from emitters 120 degrees
## apart around the listener (a random rotation, `seed_value`); otherwise its apparent position.
func emitters(record: AudioRecord, seed_value: int) -> Array[Vector2]:
	if not record.points.is_empty():
		return record.points.duplicate()
	if (record.flags & AudioRecord.DIFFUSE) == 0:
		return [record.apparent] as Array[Vector2]
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var start: float = rng.randf() * TAU
	var n: int = Tuning.i(&"noise.diffuse_emitter_count")
	var d: float = Tuning.f(&"noise.diffuse_emitter_distance_tiles")
	var out: Array[Vector2] = []
	for i: int in n:
		out.append(listener + Vector2.from_angle(start + TAU * i / n) * d)
	return out


func play(record: AudioRecord, number: int = 0) -> void:
	if VisualEvents.is_visual(record.type):
		return  # VIS-09's puffs and bursts are drawn, never played
	var db: float = gain_db(record)
	var samples: PackedFloat32Array = SampleBank.pcm(SampleBank.stream(record.type))
	var rate: float = SampleBank.RATE
	if record.type == NoiseTypes.Type.FALL_SCREAM and record.voice >= 0:
		# SND-15: with no voice on the mic, the fallen's character screams (SND-13's line).
		var ids: PackedStringArray = VoiceManifest.voice_ids()
		var line: PackedFloat32Array = VoiceBank.pcm(ids[record.voice], "scream", "take_1") if record.voice < ids.size() else PackedFloat32Array()
		if not line.is_empty():
			samples = line
			rate = 48000.0
	var bus: String = bus_for(record)
	var pitch: float = 1.0 + Tuning.f(&"noise.pitch_variation") * (float(posmod(number * 7919, 21)) / 10.0 - 1.0)
	for at: Vector2 in emitters(record, number):
		var id: int = mixer.add(samples, rate * pitch, at, db, bus)
		voices.append([id, db, at, bus, pitch, record.type])
	_enforce_cap()
	caption.emit(record.type, null if (record.flags & AudioRecord.DIFFUSE) != 0 else record.apparent - listener)


## The flames guttering now (tiles): an identity record's flame byte with FlameFlags.GUTTER, and the
## own flame from the own block (shuttered or slotted included). Never a migration gutter.
func set_sputters(at: Array[Vector2]) -> void:
	while sputter_voices.size() > at.size():
		var gone: int = sputter_voices.pop_back()
		mixer.remove(gone)
	var bed: PackedFloat32Array = SampleBank.pcm(SampleBank.bed("sputter"))
	while sputter_voices.size() < at.size():
		sputter_voices.append(mixer.add(bed, SampleBank.RATE, at[sputter_voices.size()], 0.0, "Game", true))
	for i: int in at.size():
		mixer.move(sputter_voices[i], at[i])
	sputter_at = at.duplicate()


func _process(_delta: float) -> void:
	var playing: Array[Array] = []
	for v: Array in voices:
		if mixer.has(int(Variants.number(v[0]))):
			playing.append(v)
	voices = playing


func _enforce_cap() -> void:
	var cap: int = Tuning.i(&"noise.max_event_voices")
	while voices.size() > cap:
		var quietest: int = 0
		for i: int in voices.size():
			if float(Variants.number(voices[i][1])) < float(Variants.number(voices[quietest][1])):
				quietest = i
		var v: Array = voices[quietest]
		voices.remove_at(quietest)
		mixer.remove(int(Variants.number(v[0])))

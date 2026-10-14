class_name AudioBuses
extends RefCounted
## SND-03: the mix. Master (a hard limiter at noise.limiter_ceiling_dbfs, so a real scream or a shot
## stays loud but safe) <- Game (with Muffled: a low-pass at noise.muffle_lowpass_hz for sounds that
## crossed a closed portal), Tells, Ambience, Voice, Callouts, Ringing, Knocks (SND-15: no option
## touches it), Pithead. Built at runtime
## (idempotent); the Tells bus carries the tell volume option (noise.tell_volume_db's range), which
## scales only what was delivered; the Ringing bus carries the ringing volume option (SND-04).

const BUSES: Array[String] = ["Game", "Muffled", "Tells", "Ambience", "Voice", "Callouts", "Ringing", "Knocks", "Pithead"]


static func install() -> void:
	for bus: String in BUSES:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			var i: int = AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus)
			AudioServer.set_bus_send(i, "Game" if bus == "Muffled" else "Master")
	var muffled: int = AudioServer.get_bus_index("Muffled")
	if AudioServer.get_bus_effect_count(muffled) == 0:
		var lp: AudioEffectLowPassFilter = AudioEffectLowPassFilter.new()
		lp.cutoff_hz = Tuning.f(&"noise.muffle_lowpass_hz")
		AudioServer.add_bus_effect(muffled, lp)
	var master: int = AudioServer.get_bus_index("Master")
	var has_limiter: bool = false
	for e: int in AudioServer.get_bus_effect_count(master):
		if AudioServer.get_bus_effect(master, e) is AudioEffectHardLimiter:
			has_limiter = true
	if not has_limiter:
		var lim: AudioEffectHardLimiter = AudioEffectHardLimiter.new()
		lim.ceiling_db = Tuning.f(&"noise.limiter_ceiling_dbfs")
		AudioServer.add_bus_effect(master, lim, 0)
	set_tell_volume_db(Tuning.f(&"noise.tell_volume_db"))
	set_ringing_volume_db(Tuning.f(&"noise.ringing_volume_db"))


## An option's value clamped to its tuning key's range.
static func clamp_option(key: StringName, db: float) -> float:
	var entry: Dictionary = Variants.dict(Tuning.current.entries.get(str(key), {}))
	var lo: float = float(Variants.number(entry.get("min", db)))
	var hi: float = float(Variants.number(entry.get("max", db)))
	return clampf(db, lo, hi)


## The tell volume option, clamped to its range (-6 to +6 dB).
static func set_tell_volume_db(db: float) -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Tells"), clamp_option(&"noise.tell_volume_db", db))


## SND-04: the ringing volume option, clamped to its range (-12 to 0 dB). The Ringing bus only: the
## deafened dip (the server's on events, Deafness's on the beds) never changes with it.
static func set_ringing_volume_db(db: float) -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Ringing"), clamp_option(&"noise.ringing_volume_db", db))

class_name AudioOptions
extends RefCounted
## SND-04 (GDD §14.5): the audio options this ticket owns, kept in user://audio.cfg (Proposed; UI-06
## draws the page, STM-05 syncs the profile). The output mode: headphones (the binaural path) by
## default on PC, where first launch recommends them; speakers on a Steam Deck until the player
## chooses; mono, which UI-03 pairs with direction-only arcs. The ringing volume, -12 to 0 dB
## (noise.ringing_volume_db's range), which never changes the deafened dip.

const PATH: String = "user://audio.cfg"

var output_mode: SpatialMixer.Mode = SpatialMixer.Mode.HEADPHONES
## True once the player has picked an output mode themselves.
var chosen: bool = false
var ringing_volume_db: float = 0.0


static func on_steam_deck() -> bool:
	return OS.get_environment("SteamDeck") == "1"


static func default_mode(steam_deck: bool) -> SpatialMixer.Mode:
	return SpatialMixer.Mode.SPEAKERS if steam_deck else SpatialMixer.Mode.HEADPHONES


static func defaults(steam_deck: bool) -> AudioOptions:
	var o: AudioOptions = AudioOptions.new()
	o.output_mode = default_mode(steam_deck)
	o.ringing_volume_db = Tuning.f(&"noise.ringing_volume_db")
	return o


## First launch on a PC: UI-06 recommends headphones.
func recommend_headphones(steam_deck: bool) -> bool:
	return not chosen and not steam_deck


## Mono comes with direction-only arcs (UI-03).
func direction_only_arcs() -> bool:
	return output_mode == SpatialMixer.Mode.MONO


func choose_output(mode: SpatialMixer.Mode) -> void:
	output_mode = mode
	chosen = true


func set_ringing_volume_db(db: float) -> void:
	ringing_volume_db = AudioBuses.clamp_option(&"noise.ringing_volume_db", db)


func apply(mixer: SpatialMixer) -> void:
	mixer.set_mode(output_mode)
	AudioBuses.set_ringing_volume_db(ringing_volume_db)


static func load_from(path: String = PATH, steam_deck: bool = on_steam_deck()) -> AudioOptions:
	var o: AudioOptions = defaults(steam_deck)
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(path) != OK:
		return o
	o.chosen = Variants.flag(cfg.get_value("output", "chosen", false))
	if o.chosen:
		var m: int = int(Variants.number(cfg.get_value("output", "mode", o.output_mode)))
		o.output_mode = clampi(m, 0, SpatialMixer.Mode.MONO) as SpatialMixer.Mode
	o.set_ringing_volume_db(float(Variants.number(cfg.get_value("deafened", "ringing_volume_db", o.ringing_volume_db))))
	return o


func save_to(path: String = PATH) -> Error:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value("output", "chosen", chosen)
	cfg.set_value("output", "mode", int(output_mode))
	cfg.set_value("deafened", "ringing_volume_db", ringing_volume_db)
	return cfg.save(path)

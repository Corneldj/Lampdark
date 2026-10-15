class_name DarkMix
extends RefCounted
## RSC-04 (Gameplay §11.8): being out cold sounds like it. The server already sends the unconscious
## only the game sound round their body, each record muffled and rescue.unconscious_gain_db down;
## while out cold (and not watching a teammate) the Muffled bus's low-pass drops to
## rescue.unconscious_lowpass_hz, and returns to noise.muffle_lowpass_hz on waking. The dream
## channel is dry and plays on the Voice bus, untouched.


static func apply(out_cold: bool) -> void:
	var bus: int = AudioServer.get_bus_index("Muffled")
	if bus < 0 or AudioServer.get_bus_effect_count(bus) == 0:
		return
	var lp: AudioEffectLowPassFilter = AudioServer.get_bus_effect(bus, 0) as AudioEffectLowPassFilter
	if lp == null:
		return
	lp.cutoff_hz = cutoff_hz(out_cold)


static func cutoff_hz(out_cold: bool) -> float:
	return float(Tuning.i(&"rescue.unconscious_lowpass_hz")) if out_cold else Tuning.f(&"noise.muffle_lowpass_hz")

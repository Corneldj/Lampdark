extends GutTest
## RSC-04: out cold, the Muffled bus's low-pass drops to rescue.unconscious_lowpass_hz; awake it is
## noise.muffle_lowpass_hz again. The Voice bus (the dream channel) is never filtered by it.


func before_all() -> void:
	assert_true(Tuning.load_client())
	AudioBuses.install()


func after_all() -> void:
	DarkMix.apply(false)


func _cutoff() -> float:
	var lp: AudioEffectLowPassFilter = AudioServer.get_bus_effect(AudioServer.get_bus_index("Muffled"), 0) as AudioEffectLowPassFilter
	return lp.cutoff_hz


func test_out_cold_and_awake() -> void:
	DarkMix.apply(true)
	assert_almost_eq(_cutoff(), 800.0, 1e-3, "out cold: 800 Hz")
	assert_almost_eq(_cutoff(), float(Tuning.i(&"rescue.unconscious_lowpass_hz")), 1e-3)
	DarkMix.apply(false)
	assert_almost_eq(_cutoff(), Tuning.f(&"noise.muffle_lowpass_hz"), 1e-3, "awake again")
	assert_eq(AudioServer.get_bus_effect_count(AudioServer.get_bus_index("Voice")), 0, "the dream channel's bus is dry")

extends GutTest
## SND-03 (client): every catalogued noise has a placeholder sample, made without error and the same
## each time; HAZ-03's collapse creak is a creak (the timber bed's groan), not a burst.


func test_every_noise_has_a_sample() -> void:
	for raw: Variant in NoiseTypes.Type.values():
		var type: int = int(Variants.number(raw))
		if type == NoiseTypes.Type.NONE:
			continue
		var w: AudioStreamWAV = SampleBank.stream(type)
		assert_not_null(w, NoiseTypes.id_of(type as NoiseTypes.Type))
		assert_gt(w.data.size(), 0, "%s has sound" % NoiseTypes.id_of(type as NoiseTypes.Type))


func test_the_creak_groans() -> void:
	var creak: AudioStreamWAV = SampleBank.stream(NoiseTypes.Type.COLLAPSE_CREAK)
	assert_gte(creak.data.size(), roundi(1.4 * SampleBank.RATE) * 2, "long enough for the groan (16-bit mono)")
	assert_eq(creak.data, SampleBank.make("creak", 1.5, NoiseTypes.Type.COLLAPSE_CREAK, 1.0).data, "the timber's creak, the same each time")

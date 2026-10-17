extends GutTest
## RSC-06 (Gameplay §9.5, §11.9): the lampman's remarks. Every FallCause has one, keyed by its name;
## none names a hard variant (One Lamp, No Chalk, Dead Lines; Gameplay §13.6) or a run condition
## (HAZ-07's hazards.condition_weights), nor says "variant" or "condition": he is never wrong about a
## default rule, and he never gives a quiet change away.

const REMARKS: String = "res://data/text/lampman/remarks.json"
## Gameplay §13.6's hard variants (no data file lists them yet: MOD-03's lobby options will).
const VARIANTS: Array[String] = ["one lamp", "no chalk", "dead lines"]


func before_all() -> void:
	assert_true(Tuning.load_server())


func _remarks() -> Dictionary:
	return Variants.dict(Variants.dict(JSON.parse_string(FileAccess.get_file_as_string(REMARKS))).get("strings", {}))


func test_every_cause_has_a_remark() -> void:
	var strings: Dictionary = _remarks()
	for raw: Variant in FallCause.Cause.values():
		var key: String = "lampman.remark." + FallCause.name_of(int(Variants.number(raw)))
		assert_true(strings.has(key) and not str(strings[key]).is_empty(), "%s has a line" % key)


func test_no_remark_names_a_variant_or_a_condition() -> void:
	var banned: Array[String] = VARIANTS.duplicate()
	for raw: Variant in Tuning.table(&"hazards.condition_weights").keys():
		banned.append(str(raw).replace("_", " "))
	banned.append_array(["variant", "condition"] as Array[String])
	assert_gt(banned.size(), VARIANTS.size() + 2, "the run conditions are read from tuning")
	var strings: Dictionary = _remarks()
	for key: Variant in strings.keys():
		var text: String = str(strings[key]).to_lower()
		for word: String in banned:
			assert_false(text.contains(word), "%s names '%s'" % [key, word])

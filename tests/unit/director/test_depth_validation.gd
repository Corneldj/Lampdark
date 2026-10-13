extends GutTest
## DIR-04's validation: a _by_ring array of four or six entries is rejected, and so is any key
## that would let a speed, reach, tell or wind-up vary with depth. No depth key reaches a client.


func _entry(value: Variant, type: String = "by_ring") -> Dictionary:
	return {"value": value, "type": type, "unit": "s", "source": "Gameplay §10.6", "starting": false, "visibility": "server", "kind": "param"}


func _errors(key: String, entry: Dictionary) -> String:
	return "\n".join(PackedStringArray(TuningSchema.validate_entry(key, entry, ["s", "tiles"] as Array[String])))


func test_five_entries() -> void:
	assert_eq(_errors("moth.sight_tiles_by_ring", _entry([1, 2, 3, 4, 5])), "")
	assert_string_contains(_errors("moth.sight_tiles_by_ring", _entry([1, 2, 3, 4])), "exactly 5 values")
	assert_string_contains(_errors("moth.sight_tiles_by_ring", _entry([1, 2, 3, 4, 5, 6])), "exactly 5 values")
	assert_string_contains(_errors("moth.sight_tiles_by_ring", _entry([1, 2, 3, 4, 5], "float_list")), "must be of type by_ring")


func test_never_faster_longer_armed_or_quicker() -> void:
	for key: String in ["stythe.speed_by_ring", "tapper.windup_s_by_ring", "tapper.reach_tiles_by_ring", "moth.tell_reach_by_ring", "moth.hunt_speed_by_ring"]:
		assert_string_contains(_errors(key, _entry([1, 2, 3, 4, 5])), "never varies with depth", key)


func test_no_depth_key_reaches_a_client() -> void:
	assert_true(Tuning.load_server())
	for key: Variant in Tuning.current.entries.keys():
		if str(key).begins_with("depth."):
			assert_eq(str(Variants.dict(Tuning.current.entries[key]).get("visibility", "")), "server", "%s is server-only" % key)
	var client: String = FileAccess.get_file_as_string("res://data/tuning/_client.json")
	assert_false(client.contains("\"depth."), "the client table carries no depth key")

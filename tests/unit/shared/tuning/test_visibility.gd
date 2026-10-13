extends GutTest
## Server-only keys never reach a client (FND-05, Gameplay §5.10).

const Fixture = preload("res://tests/unit/shared/tuning/tuning_fixture.gd")


func test_client_table_holds_client_keys_only() -> void:
	var table: Dictionary = Fixture.valid_set().client_table()
	var keys: Dictionary = table["keys"]
	assert_eq(keys.keys().size(), 2)
	assert_has(keys, "moth.client_radius_tiles")
	assert_has(keys, "net.tick_hz")
	assert_does_not_have(keys, "moth.windup_s")


func test_client_set_refuses_server_keys() -> void:
	var path: String = Fixture.ROOT.path_join("client_table.json")
	DirAccess.make_dir_recursive_absolute(Fixture.ROOT)
	Fixture.store(path, Fixture.valid_set().client_table())
	var client: TuningSet = TuningSet.new()
	assert_eq(client.load_client_table(path), [] as Array[String])
	assert_almost_eq(client.f(&"moth.client_radius_tiles"), 4.0, 0.0001)
	assert_eq(client.f(&"moth.windup_s"), 0.0)
	assert_push_error("unknown or server-only")


func test_client_table_with_a_server_key_is_rejected() -> void:
	var path: String = Fixture.ROOT.path_join("bad_client_table.json")
	DirAccess.make_dir_recursive_absolute(Fixture.ROOT)
	Fixture.store(path, {"keys": {"moth.windup_s": {"value": 1.0, "type": "float", "visibility": "server"}}})
	var errors: Array[String] = TuningSet.new().load_client_table(path)
	assert_string_contains("\n".join(PackedStringArray(errors)), "server-only key in the client table")


func test_shipped_client_table_has_no_server_key() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TuningSet.CLIENT_TABLE))
	var keys: Dictionary = Variants.dict(Variants.dict(parsed).get("keys", {}))
	assert_gt(keys.size(), 0)
	for key: Variant in keys.keys():
		assert_eq(str(Variants.dict(keys[key]).get("visibility")), "client", "%s is client-visible" % key)


func test_client_hash_differs_from_server_hash() -> void:
	var tuning: TuningSet = Fixture.valid_set()
	assert_ne(tuning.content_hash("client"), tuning.content_hash())

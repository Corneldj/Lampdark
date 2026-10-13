extends GutTest
## LbHash and LbRng reproduce the golden file through the GDScript binding (FND-06).

const GOLDEN: String = "res://native/tests/golden/rng_golden.json"
const DOMAINS: String = "res://shared/ids/hash_domains.json"

var golden: Dictionary


func before_all() -> void:
	golden = Variants.dict(JSON.parse_string(FileAccess.get_file_as_string(GOLDEN)))
	assert_false(golden.is_empty(), "golden file loads")


## "0x" + 16 hex digits -> the int64 holding that bit pattern.
static func bits(text: String) -> int:
	var high: int = text.substr(2, 8).hex_to_int()
	var low: int = text.substr(10, 8).hex_to_int()
	return (high << 32) | low


static func bits_list(values: Variant) -> PackedInt64Array:
	var out: PackedInt64Array = PackedInt64Array()
	for value: Variant in Variants.array(values):
		out.append(bits(str(value)))
	return out


func _section(name: String) -> Array:
	return Variants.array(golden.get(name, []))


func test_mix64() -> void:
	var cases: Array = _section("mix64")
	assert_eq(cases.size(), 64)
	for pair: Variant in cases:
		var row: Array = Variants.array(pair)
		assert_eq(LbHash.mix64(bits(str(row[0]))), bits(str(row[1])), "mix64(%s)" % row[0])


func test_hash_u64() -> void:
	var cases: Array = _section("hash_u64")
	assert_eq(cases.size(), 100)
	for raw: Variant in cases:
		var c: Dictionary = Variants.dict(raw)
		var got: int = LbHash.hash(bits(str(c["seed"])), int(Variants.number(c["domain"])), bits_list(c["keys"]))
		assert_eq(got, bits(str(c["hash"])))


func test_sub_seed() -> void:
	for raw: Variant in _section("sub_seed"):
		var c: Dictionary = Variants.dict(raw)
		var got: int = LbHash.sub_seed(bits(str(c["seed"])), int(Variants.number(c["domain"])),
			bits_list(c["keys"]), int(Variants.number(c["attempt"])))
		assert_eq(got, bits(str(c["value"])))


func test_streams() -> void:
	assert_eq(_section("streams").size(), 8)
	for raw: Variant in _section("streams"):
		var c: Dictionary = Variants.dict(raw)
		var rng: LbRng = LbRng.from_seed(bits(str(c["seed"])))
		for expected: int in bits_list(c["outputs"]):
			assert_eq(rng.next_u64(), expected)


func test_range_including_extremes() -> void:
	for raw: Variant in _section("range"):
		var c: Dictionary = Variants.dict(raw)
		var rng: LbRng = LbRng.from_seed(bits(str(c["seed"])))
		var lo: int = bits(str(c["lo"]))
		var hi: int = bits(str(c["hi"]))
		for expected: int in bits_list(c["draws"]):
			var got: int = rng.range(lo, hi)
			assert_eq(got, expected)
			assert_true(got >= lo and got <= hi, "%d in [%d, %d]" % [got, lo, hi])


func test_chance_pick_shuffle_unit() -> void:
	for raw: Variant in _section("chance_ppm"):
		var c: Dictionary = Variants.dict(raw)
		var rng: LbRng = LbRng.from_seed(bits(str(c["seed"])))
		var ppm: int = int(Variants.number(c["ppm"]))
		for expected: Variant in Variants.array(c["results"]):
			assert_eq(rng.chance_ppm(ppm), Variants.number(expected) == 1.0)
	for raw: Variant in _section("pick_weighted"):
		var c: Dictionary = Variants.dict(raw)
		var rng: LbRng = LbRng.from_seed(bits(str(c["seed"])))
		var weights: PackedInt64Array = PackedInt64Array()
		for w: Variant in Variants.array(c["weights"]):
			weights.append(int(Variants.number(w)))
		for expected: Variant in Variants.array(c["picks"]):
			var pick: int = rng.pick_weighted(weights)
			assert_eq(pick, int(Variants.number(expected)))
			assert_gt(weights[pick], 0, "never a zero weight")
	for raw: Variant in _section("shuffle"):
		var c: Dictionary = Variants.dict(raw)
		var rng: LbRng = LbRng.from_seed(bits(str(c["seed"])))
		var items: Array = range(int(Variants.number(c["n"])))
		rng.shuffle(items)
		var expected: Array = []
		for v: Variant in Variants.array(c["result"]):
			expected.append(int(Variants.number(v)))
		assert_eq(items, expected)
	for raw: Variant in _section("unit_double"):
		var c: Dictionary = Variants.dict(raw)
		var rng: LbRng = LbRng.from_seed(bits(str(c["seed"])))
		for raw53: int in bits_list(c["raw53"]):
			assert_eq(rng.unit_double(), float(raw53) / 9007199254740992.0)


func test_bit_patterns_round_trip() -> void:
	var big: int = bits("0xffffffffffffffff")
	assert_eq(big, -1, "2^64-1 shows as -1")
	assert_eq(LbHash.to_hex(big), "ffffffffffffffff")
	assert_eq(LbHash.to_hex(bits("0x8000000000000000")), "8000000000000000")
	var rng: LbRng = LbRng.from_seed(big)
	assert_eq(rng.get_state(), big, "the seed's bits survive the boundary")


func test_state_round_trip() -> void:
	var rng: LbRng = LbRng.from_seed(77)
	for _i: int in 10:
		rng.next_u64()
	var saved: int = rng.get_state()
	var first: PackedInt64Array = PackedInt64Array()
	for _i: int in 20:
		first.append(rng.next_u64())
	var restored: LbRng = LbRng.from_seed(0)
	restored.set_state(saved)
	for expected: int in first:
		assert_eq(restored.next_u64(), expected)


func test_errors() -> void:
	var rng: LbRng = LbRng.from_seed(1)
	assert_eq(rng.pick_weighted(PackedInt64Array([0, 0, 0])), -1)
	assert_push_error("pick_weighted")
	assert_eq(rng.range(6, 5), 6)
	assert_push_error("is above hi")
	assert_eq(rng.range(5, 5), 5)


func test_script_values_only_in_debug() -> void:
	var rng: LbRng = LbRng.from_seed(5)
	assert_eq(rng.has_method(&"script_values"), OS.is_debug_build())
	if rng.has_method(&"script_values"):
		var plain: int = LbRng.from_seed(5).next_u64()
		rng.call(&"script_values", PackedInt64Array([111, 222]))
		assert_eq(rng.next_u64(), 111)
		assert_eq(rng.next_u64(), 222)
		assert_eq(rng.next_u64(), plain)


func test_version_and_domain_constants() -> void:
	assert_eq(LbHash.VERSION, 1)
	var registry: Dictionary = Variants.dict(JSON.parse_string(FileAccess.get_file_as_string(DOMAINS)))
	var entries: Array = Variants.array(registry.get("domains", []))
	assert_eq(entries.size(), HashDomain.ALL.size())
	for raw: Variant in entries:
		var entry: Dictionary = Variants.dict(raw)
		var generated_id: int = int(Variants.number(HashDomain.ALL.get(str(entry["name"]), -1)))
		assert_eq(generated_id, int(Variants.number(entry["id"])), str(entry["name"]))
	assert_eq(HashDomain.GEN_BIOME, 5)
